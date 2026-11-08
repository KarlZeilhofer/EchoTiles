package com.sidhant.echotiles

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.*

class RhythmDetectorTest {
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

}
