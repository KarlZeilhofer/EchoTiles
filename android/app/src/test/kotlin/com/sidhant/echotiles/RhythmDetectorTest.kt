package com.sidhant.echotiles

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.*

class RhythmDetectorTest {
    @Test fun sustainsAreNeverLongerThanFourSeconds() {
        val detector = RhythmDetector()
        repeat(RhythmDetector.RATE * 7) { i ->
            val t = i.toDouble() / RhythmDetector.RATE
            detector.add(if (t in 0.5..6.5) 0.1 * sin(2 * PI * 440 * t) else 0.0)
        }
        val result = detector.finish(7.0)
        assertEquals(4, result["version"])
        @Suppress("UNCHECKED_CAST")
        val candidates = result["candidates"] as List<Map<String, Any>>
        assertEquals(4.0, candidates.first()["duration"] as Double, 0.001)
        assertTrue(candidates.all { it["duration"] as Double <= 4.0 })
    }

    @Test fun twoBandAttacksAreMarkedButSingleTonesAreNotDoubled() {
        fun analyze(both: Boolean): List<Map<String, Any>> {
            val detector = RhythmDetector()
            repeat(RhythmDetector.RATE * 3) { i ->
                val t = i.toDouble() / RhythmDetector.RATE
                val p = (t - 0.5).mod(0.5)
                val sample = if (t >= 0.5 && p < 0.06)
                    0.3 * exp(-p * 40) * (sin(2 * PI * 110 * p) + if (both) sin(2 * PI * 1760 * p) else 0.0) else 0.0
                detector.add(sample)
            }
            @Suppress("UNCHECKED_CAST")
            return detector.finish(3.0)["candidates"] as List<Map<String, Any>>
        }
        assertTrue(analyze(true).any { it["doubleAccent"] == true })
        assertTrue(analyze(false).none { it["doubleAccent"] == true })
    }
    private fun pulses(duration: Double, spacing: Double, start: Double = 0.5): Map<String, Any> {
        val detector = RhythmDetector()
        for (i in 0 until (duration * RhythmDetector.RATE).toInt()) {
            val time = i.toDouble() / RhythmDetector.RATE
            val phase = (time - start).mod(spacing)
            val tone = if (time >= start && phase < 0.07)
                0.8 * sin(2 * PI * 440 * phase) * exp(-phase * 40) else 0.0
            detector.add(tone)
        }
        return detector.finish(duration)
    }

    @Test fun detectsActualOnsetsAndTempo() {
        val result = pulses(8.0, 0.5)
        @Suppress("UNCHECKED_CAST")
        val notes = result["notes"] as List<Map<String, Any>>
        assertTrue("Expected clicks, got ${notes.size}", notes.size in 13..16)
        for (note in notes) {
            val time = note["time"] as Double
            val nearest = 0.5 + round((time - 0.5) / 0.5) * 0.5
            assertTrue("Onset $time not aligned with $nearest", abs(time - nearest) < 0.075)
            assertTrue(note["lane"] as Int in 0..3)
        }
        assertEquals(120.0, result["bpm"] as Double, 5.0)
    }

    @Test fun densityIncreasesDuringFastSong() {
        val result = pulses(20.0, 0.2)
        @Suppress("UNCHECKED_CAST")
        val notes = result["notes"] as List<Map<String, Any>>
        val first = notes.count { (it["time"] as Double) in 1.0..5.0 }
        val last = notes.count { (it["time"] as Double) in 15.0..19.0 }
        assertTrue("End should contain more notes: $first -> $last", last > first)
    }

    @Test fun silenceDoesNotInventTiles() {
        val detector = RhythmDetector()
        repeat(RhythmDetector.RATE * 2) { detector.add(0.0) }
        try { detector.finish(2.0); fail("Silence must fail analysis") }
        catch (e: IllegalStateException) { assertTrue(e.message!!.contains("No distinct")) }
    }

    @Test fun detectsFirstAndLastNotesAndKeepsOrder() {
        val result = pulses(2.1, 0.5, 0.0)
        @Suppress("UNCHECKED_CAST")
        val notes = result["notes"] as List<Map<String, Any>>
        assertTrue((notes.first()["time"] as Double) < 0.075)
        assertTrue((notes.last()["time"] as Double) > 1.95)
        assertTrue(notes.zipWithNext().all { (a,b) -> (b["time"] as Double) > (a["time"] as Double) })
    }
    @Test fun sustainDurationsFollowAudibleLengths() {
        val detector = RhythmDetector()
        val tones = listOf(Triple(0.5, 0.55, 440.0), Triple(1.5, 1.25, 660.0))
        for (i in 0 until (3.2 * RhythmDetector.RATE).toInt()) {
            val t = i.toDouble() / RhythmDetector.RATE
            var sample = 0.0
            for ((start, length, frequency) in tones) {
                val phase = t - start
                if (phase >= 0 && phase < length) {
                    val envelope = min(1.0, phase / 0.01) * min(1.0, (length - phase) / 0.02)
                    sample += 0.6 * envelope * sin(2 * PI * frequency * phase)
                }
            }
            detector.add(sample)
        }
        @Suppress("UNCHECKED_CAST")
        val notes = detector.finish(3.2)["notes"] as List<Map<String, Any>>
        for ((start, length, _) in tones) {
            val note = notes.minBy { abs((it["time"] as Double) - start) }
            assertEquals(start, note["time"] as Double, 0.08)
            assertEquals(length, note["duration"] as Double, 0.10)
        }
    }

    @Test fun shortHitsAndBroadbandNoiseAreNotHolds() {
        @Suppress("UNCHECKED_CAST")
        val hits = pulses(5.0, 0.5)["notes"] as List<Map<String, Any>>
        assertTrue(hits.all { it["duration"] as Double == 0.0 })
        val detector = RhythmDetector()
        val random = java.util.Random(7)
        repeat(RhythmDetector.RATE * 3) { i ->
            val t = i.toDouble() / RhythmDetector.RATE
            detector.add(if (t in 0.5..2.5) random.nextDouble() - 0.5 else 0.0)
        }
        @Suppress("UNCHECKED_CAST")
        val noise = detector.finish(3.0)["notes"] as List<Map<String, Any>>
        assertTrue(noise.all { it["duration"] as Double == 0.0 })
    }

    @Test fun aPitchChangeEndsThePreviousHold() {
        val detector = RhythmDetector()
        repeat(RhythmDetector.RATE * 3) { i ->
            val t = i.toDouble() / RhythmDetector.RATE
            detector.add(if (t in 0.5..2.5) 0.6 * sin(2 * PI * (if (t < 1.5) 440 else 880) * t) else 0.0)
        }
        @Suppress("UNCHECKED_CAST")
        val notes = detector.finish(3.0)["notes"] as List<Map<String, Any>>
        val first = notes.minBy { abs((it["time"] as Double) - 0.5) }
        assertEquals(1.0, first["duration"] as Double, 0.1)
        assertTrue(notes.all { (it["time"] as Double) + (it["duration"] as Double) <= 3.001 })
    }

    @Test fun veryQuietSustainedNotesRemainSliders() {
        val detector = RhythmDetector()
        repeat(RhythmDetector.RATE * 4) { i ->
            val t = i.toDouble() / RhythmDetector.RATE
            detector.add(if (t in 0.5..2.5) 0.0003 * sin(2 * PI * 440 * t) else 0.0)
        }
        @Suppress("UNCHECKED_CAST")
        val notes = detector.finish(4.0)["notes"] as List<Map<String, Any>>
        val note = notes.minBy { abs((it["time"] as Double) - 0.5) }
        assertEquals(2.0, note["duration"] as Double, 0.12)
        assertTrue((note["time"] as Double) + (note["duration"] as Double) < 2.65)
    }

    @Test fun fadingTonesFollowTheAudibleTailAndStopAtSilence() {
        val detector = RhythmDetector()
        repeat(RhythmDetector.RATE * 4) { i ->
            val t = i.toDouble() / RhythmDetector.RATE
            val phase = t - 0.5
            detector.add(if (phase >= 0 && phase < 2.5)
                0.3 * exp(-2 * phase) * sin(2 * PI * 440 * phase) else 0.0)
        }
        @Suppress("UNCHECKED_CAST")
        val notes = detector.finish(4.0)["notes"] as List<Map<String, Any>>
        val note = notes.minBy { abs((it["time"] as Double) - 0.5) }
        assertTrue("Fade cut too soon: $note", note["duration"] as Double > 2.25)
        assertTrue((note["time"] as Double) + (note["duration"] as Double) < 3.12)
    }

    @Test fun longVocalLikeHarmonicsSurviveVibratoAndChangingDominantHarmonics() {
        val detector = RhythmDetector()
        var angle = 0.0
        repeat(RhythmDetector.RATE * 4) { i ->
            val t = i.toDouble() / RhythmDetector.RATE
            val phase = t - 0.5
            angle += 2 * PI * (180 + 5 * sin(2 * PI * 5 * t)) / RhythmDetector.RATE
            val blend = (phase / 2.5).coerceIn(0.0, 1.0)
            val voice = (1 - blend) * sin(angle) + 0.6 * sin(2 * angle) +
                blend * sin(3 * angle) + 0.5 * sin(4 * angle)
            detector.add(if (phase >= 0 && phase < 2.5) 0.01 * voice else 0.0)
        }
        @Suppress("UNCHECKED_CAST")
        val notes = detector.finish(4.0)["notes"] as List<Map<String, Any>>
        val note = notes.minBy { abs((it["time"] as Double) - 0.5) }
        assertTrue("Vocal fragmented into taps: $notes", note["duration"] as Double > 2.2)
        assertTrue((note["time"] as Double) + (note["duration"] as Double) < 3.15)
        assertTrue("Vibrato created phantom taps: $notes", notes.none { (it["time"] as Double) in 0.7..2.9 })
    }

    @Test fun unpitchedDecayCanBeHeldButNotTheFollowingSilence() {
        val detector = RhythmDetector()
        val random = java.util.Random(23)
        repeat(RhythmDetector.RATE * 4) { i ->
            val t = i.toDouble() / RhythmDetector.RATE
            val phase = t - 0.5
            detector.add(if (phase >= 0 && phase < 2.5)
                0.2 * exp(-1.2 * phase) * (random.nextDouble() - 0.5) else 0.0)
        }
        @Suppress("UNCHECKED_CAST")
        val notes = detector.finish(4.0)["notes"] as List<Map<String, Any>>
        val note = notes.minBy { abs((it["time"] as Double) - 0.5) }
        assertTrue("Decay fragmented into taps: $note", note["duration"] as Double > 2.2)
        assertTrue((note["time"] as Double) + (note["duration"] as Double) < 3.15)
    }

}
