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
}
