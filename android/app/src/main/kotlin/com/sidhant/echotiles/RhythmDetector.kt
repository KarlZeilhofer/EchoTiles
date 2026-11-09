package com.sidhant.echotiles

import kotlin.math.*

/** Streaming spectral-flux detector. Only one FFT window and compact features
 * are retained, rather than a whole decoded song. No network or ML model. */
class RhythmDetector {
    companion object {
        const val RATE = 22050
        private const val WINDOW = 1024
        private const val HOP = 441
    }
    private data class Frame(val time: Double, val flux: Double, val rms: Double, val pitch: Double, val peakBin: Int, val tonality: Double, val profile: FloatArray)
    private val samples = DoubleArray(WINDOW)
    private val previous = DoubleArray(WINDOW / 2)
    private val window = DoubleArray(WINDOW) { 0.5 - 0.5 * cos(2 * PI * it / (WINDOW - 1)) }
    private val frames = ArrayList<Frame>()
    private val bands = IntArray(WINDOW / 2) { i ->
        (ln(max(1.0, i.toDouble() * RATE / WINDOW / 65.0)) / ln(2.0) * 6).toInt().coerceIn(0, 47)
    }
    private var count = WINDOW / 2 // zero padding lets us detect notes at time zero
    private var total = 0L
    private var sinceFrame = 0

    fun add(sample: Double) {
        samples[count % WINDOW] = sample
        count++
        total++
        sinceFrame++
        if (count >= WINDOW && sinceFrame >= HOP) {
            sinceFrame = 0
            analyzeFrame()
        }
    }

    private fun analyzeFrame() {
        val re = DoubleArray(WINDOW)
        val im = DoubleArray(WINDOW)
        var energy = 0.0
        for (i in 0 until WINDOW) {
            val s = samples[(count + i) % WINDOW]
            re[i] = s * window[i]
            energy += s * s
        }
        fft(re, im)
        var flux = 0.0
        var weighted = 0.0
        var weight = 0.0
        val power = DoubleArray(WINDOW / 2)
        var totalPower = 0.0
        val strongest = DoubleArray(12)
        val bandPower = DoubleArray(48)
        var peakBin = 2
        for (i in 2 until WINDOW / 2) {
            power[i] = re[i] * re[i] + im[i] * im[i]
            totalPower += power[i]
            bandPower[bands[i]] += power[i]
            if (power[i] > strongest.last()) {
                var slot = strongest.lastIndex
                while (slot > 0 && power[i] > strongest[slot - 1]) {
                    strongest[slot] = strongest[slot - 1]; slot--
                }
                strongest[slot] = power[i]
            }
            if (power[i] > power[peakBin]) peakBin = i
            val magnitude = ln(1 + 10 * sqrt(power[i]))
            flux += max(0.0, magnitude - previous[i])
            previous[i] = magnitude
            weighted += i * magnitude * magnitude
            weight += magnitude * magnitude
        }
        val profile = FloatArray(48) { i ->
            (0.6 * bandPower[i] + (if (i > 0) 0.2 * bandPower[i - 1] else 0.0) +
                (if (i < 47) 0.2 * bandPower[i + 1] else 0.0)).toFloat()
        }
        normalize(profile)
        frames.add(Frame(max(0.0, (total - WINDOW / 2.0) / RATE), flux,
            sqrt(energy / WINDOW), if (weight > 0) weighted / weight * RATE / WINDOW else 0.0,
            peakBin, if (totalPower > 0) strongest.sum() / totalPower else 0.0, profile))
    }

    fun finish(duration: Double): Map<String, Any> {
        // Flush the final partial window; candidate timestamps are still clipped to the song.
        repeat(WINDOW / 2) { add(0.0) }
        val peaks = ArrayList<Frame>()
        for (i in frames.indices) {
            val f = frames[i]
            if (f.time > duration || f.rms < 0.00002 || f.flux < 0.05) continue
            val before = if (i == 0) 0.0 else (max(0, i - 3) until i).map { frames[it].rms }.average()
            val after = (min(frames.lastIndex, i + 1)..min(frames.lastIndex, i + 3)).map { frames[it].rms }.average()
            if (after < 0.000015 || (before > 0 && after < before * 0.4)) continue
            val attack = max(f.rms, after) > before * 1.10
            val changedSound = after >= before * 0.6 && similarity(
                frames[max(0, i - 2)].profile, frames[min(frames.lastIndex, i + 2)].profile) < 0.85
            // Quantization/vibrato and note releases can create positive FFT
            // flux without a new audible attack. Don't make phantom tap notes.
            if (!attack && !changedSound) continue
            val left = max(0, i - 25)
            val right = min(frames.lastIndex, i + 25)
            val mean = (left..right).sumOf { frames[it].flux } / (right - left + 1)
            val variance = (left..right).sumOf { (frames[it].flux - mean).pow(2) } / (right - left + 1)
            if (f.flux < mean + 0.35 * sqrt(variance)) continue
            if ((max(0, i - 2)..min(frames.lastIndex, i + 2)).any { frames[it].flux > f.flux }) continue
            if (peaks.isNotEmpty() && f.time - peaks.last().time < 0.12) {
                if (f.flux > peaks.last().flux) peaks[peaks.lastIndex] = f
            } else peaks.add(f)
        }
        check(peaks.isNotEmpty()) { "No distinct notes or beats found. Try another recording." }
        val bpm = estimateTempo(peaks.map { it.time })
        val pitches = peaks.map { it.pitch }.sorted()
        val selected = ArrayList<Frame>()
        for (peak in peaks) {
            // Keep actual onsets, progressively admit quicker passages and weaker accents.
            val progress = (peak.time / duration).coerceIn(0.0, 1.0)
            val minimumGap = 0.38 - 0.24 * progress
            if (selected.isEmpty() || peak.time - selected.last().time >= minimumGap) selected.add(peak)
        }
        fun describe(source: List<Frame>): List<Map<String, Any>> {
            var previousToneEnd = 0.0
            return source.map { f ->
                val lane = if (pitches.last() - pitches.first() < 20) 1 else
                    (1..3).count { f.pitch > pitches[min(pitches.lastIndex, pitches.size * it / 4)] }
                val index = frames.binarySearchBy(f.time) { it.time }.coerceAtLeast(0)
                val duplicate = f.time < previousToneEnd && similarity(
                    frames[max(0, index - 3)].profile,
                    frames[min(frames.lastIndex, index + 3)].profile) >= 0.65
                val hold = if (duplicate) 0.0 else estimateSustain(index, duration)
                if (hold > 0) previousToneEnd = f.time + hold
                val prior = frames[max(0, index - 3)].profile
                val low = f.profile.take(13).sum()
                val high = f.profile.drop(24).sum()
                val weight = f.profile.sum()
                val doubleAccent = hold < 1.0 && min(low, high) > weight * 0.15 &&
                    low > prior.take(13).sum() * 1.5 && high > prior.drop(24).sum() * 1.5
                mapOf("time" to f.time, "lane" to lane, "duration" to min(4.0, hold),
                    "strength" to f.flux, "doubleAccent" to doubleAccent)
            }
        }
        return mapOf("version" to 4, "duration" to duration, "bpm" to bpm,
            "notes" to describe(selected), "candidates" to describe(peaks))
    }

    /** Track the spectral shape rather than a single loudest FFT bin. This
     * survives vocal vibrato/formant changes and follows quiet, audible decay.
     * Actual silence, a new spectral shape, and track end still stop a hold. */
    private fun estimateSustain(onset: Int, duration: Double): Double {
        val start = frames[onset].time
        val attackEnd = min(frames.lastIndex, onset + 5)
        val reference = (onset..attackEnd).maxOf { frames[it].rms }
        val floor = max(0.000015, reference * 0.005)
        val decayFrame = frames[min(frames.lastIndex, onset + 20)]
        val fading = decayFrame.time <= duration && decayFrame.rms > floor &&
            decayFrame.rms < reference * 0.75
        val anchor = (min(onset + 1, attackEnd)..attackEnd).firstOrNull {
            (frames[it].tonality >= 0.32 || fading) && frames[it].rms >= reference * 0.25
        } ?: return 0.0
        val original = frames[anchor].profile
        val tracking = original.copyOf()
        var firstBad = -1
        var end = duration
        for (i in anchor..frames.lastIndex) {
            val f = frames[i]
            if (f.time > duration) break
            val stable = f.rms >= floor && (f.tonality >= 0.22 || fading) &&
                similarity(f.profile, tracking) >= 0.60 &&
                similarity(f.profile, original) >= 0.12 &&
                (!fading || f.rms < reference * 1.25)
            if (stable) {
                firstBad = -1
                for (band in tracking.indices) tracking[band] = 0.9f * tracking[band] + 0.1f * f.profile[band]
                normalize(tracking)
            } else {
                if (firstBad < 0) firstBad = i
                if (i - firstBad >= 3) { end = frames[firstBad].time; break }
            }
        }
        val length = (end - start).coerceAtLeast(0.0)
        return if (length >= 0.4) length else 0.0
    }

    private fun normalize(profile: FloatArray) {
        val norm = sqrt(profile.sumOf { it.toDouble() * it })
        if (norm > 0) for (i in profile.indices) profile[i] = (profile[i] / norm).toFloat()
    }

    private fun similarity(a: FloatArray, b: FloatArray): Double =
        a.indices.sumOf { a[it].toDouble() * b[it] }

    private fun estimateTempo(times: List<Double>): Double {
        if (times.size < 3) return 0.0
        val votes = DoubleArray(201)
        for (i in 1 until times.size) {
            val gap = times[i] - times[i - 1]
            if (gap !in 0.12..1.5) continue
            var tempo = 60 / gap
            while (tempo < 70) tempo *= 2
            while (tempo > 180) tempo /= 2
            for (b in 60..200) votes[b] += exp(-0.5 * ((b - tempo) / 2.0).pow(2))
        }
        val best = (60..200).maxBy { votes[it] }
        return if (votes[best] > 0) best.toDouble() else 0.0
    }

    private fun fft(re: DoubleArray, im: DoubleArray) {
        var j = 0
        for (i in 1 until WINDOW) {
            var bit = WINDOW shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                val t = re[i]; re[i] = re[j]; re[j] = t
            }
        }
        var length = 2
        while (length <= WINDOW) {
            val angle = -2 * PI / length
            val wr = cos(angle); val wi = sin(angle)
            for (start in 0 until WINDOW step length) {
                var ur = 1.0; var ui = 0.0
                for (k in 0 until length / 2) {
                    val a = start + k; val b = a + length / 2
                    val vr = re[b] * ur - im[b] * ui
                    val vi = re[b] * ui + im[b] * ur
                    re[b] = re[a] - vr; im[b] = im[a] - vi
                    re[a] += vr; im[a] += vi
                    val next = ur * wr - ui * wi
                    ui = ur * wi + ui * wr; ur = next
                }
            }
            length *= 2
        }
    }
}
