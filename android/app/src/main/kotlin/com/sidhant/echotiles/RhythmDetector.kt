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
    private data class Frame(val time: Double, val flux: Double, val rms: Double, val pitch: Double, val peakBin: Int, val tonality: Double)
    private val samples = DoubleArray(WINDOW)
    private val previous = DoubleArray(WINDOW / 2)
    private val window = DoubleArray(WINDOW) { 0.5 - 0.5 * cos(2 * PI * it / (WINDOW - 1)) }
    private val frames = ArrayList<Frame>()
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
        var peakBin = 2
        for (i in 2 until WINDOW / 2) {
            power[i] = re[i] * re[i] + im[i] * im[i]
            totalPower += power[i]
            if (power[i] > power[peakBin]) peakBin = i
            val magnitude = ln(1 + 10 * sqrt(power[i]))
            flux += max(0.0, magnitude - previous[i])
            previous[i] = magnitude
            weighted += i * magnitude * magnitude
            weight += magnitude * magnitude
        }
        val tonalPower = (max(2, peakBin - 1)..min(WINDOW / 2 - 1, peakBin + 1)).sumOf { power[it] }
        frames.add(Frame(max(0.0, (total - WINDOW / 2.0) / RATE), flux,
            sqrt(energy / WINDOW), if (weight > 0) weighted / weight * RATE / WINDOW else 0.0,
            peakBin, if (totalPower > 0) tonalPower / totalPower else 0.0))
    }

    fun finish(duration: Double): Map<String, Any> {
        // Flush the final partial window; candidate timestamps are still clipped to the song.
        repeat(WINDOW / 2) { add(0.0) }
        val peaks = ArrayList<Frame>()
        for (i in frames.indices) {
            val f = frames[i]
            if (f.time > duration || f.rms < 0.001 || f.flux < 0.5) continue
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
        var previousToneEnd = 0.0
        var previousToneBin = -1
        val notes = selected.map { f ->
            val lane = if (pitches.last() - pitches.first() < 20) 1 else
                (1..3).count { f.pitch > pitches[min(pitches.lastIndex, pitches.size * it / 4)] }
            val index = frames.binarySearchBy(f.time) { it.time }.coerceAtLeast(0)
            val sustain = if (f.time < previousToneEnd && abs(f.peakBin - previousToneBin) <= max(1, previousToneBin / 16))
                0.0 to previousToneBin else estimateSustain(index, duration)
            // An accent during an already-held tone should not start a second
            // copy of that same sustained note. Other accents remain tap notes.
            val duplicate = f.time < previousToneEnd && abs(sustain.second - previousToneBin) <= max(1, previousToneBin / 16)
            val hold = if (duplicate) 0.0 else sustain.first
            if (hold > 0) { previousToneEnd = f.time + hold; previousToneBin = sustain.second }
            mapOf("time" to f.time, "lane" to lane, "duration" to hold)
        }
        return mapOf("version" to 2, "duration" to duration, "bpm" to bpm, "notes" to notes)
    }

    /** Conservative dominant-tone sustain: require a stable narrow-band sound,
     * and stop at silence, a pitch change, or the track end. A quiet gap alone
     * never turns a short percussion hit into a hold. */
    private fun estimateSustain(onset: Int, duration: Double): Pair<Double, Int> {
        val start = frames[onset].time
        val attackEnd = min(frames.lastIndex, onset + 4)
        val reference = (onset..attackEnd).maxOf { frames[it].rms }
        val anchor = (min(onset + 1, attackEnd)..attackEnd).firstOrNull {
            frames[it].tonality >= 0.45 && frames[it].rms >= reference * 0.35
        } ?: return 0.0 to -1
        val bin = frames[anchor].peakBin
        var firstBad = -1
        var end = duration
        for (i in anchor..frames.lastIndex) {
            val f = frames[i]
            if (f.time > duration) break
            val stable = f.rms >= max(0.002, reference * 0.18) && f.tonality >= 0.35 &&
                abs(f.peakBin - bin) <= max(1, bin / 16)
            if (stable) firstBad = -1 else {
                if (firstBad < 0) firstBad = i
                if (i - firstBad >= 2) { end = frames[firstBad].time; break }
            }
        }
        val length = (end - start).coerceAtLeast(0.0)
        return (if (length >= 0.4) length else 0.0) to bin
    }

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
