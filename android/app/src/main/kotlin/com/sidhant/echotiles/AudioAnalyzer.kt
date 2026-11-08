package com.sidhant.echotiles

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import java.nio.ByteOrder
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

class AudioAnalyzer(private val context: Context) {
    fun analyze(path: String, cancelled: AtomicBoolean, progress: (Double) -> Unit): Map<String, Any> {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            when {
                path.startsWith("assets/") -> context.assets.openFd("flutter_assets/${Uri.encode(path, "/")}").use {
                    extractor.setDataSource(it.fileDescriptor, it.startOffset, it.length)
                }
                path.startsWith("content://") -> extractor.setDataSource(context, Uri.parse(path), null)
                else -> extractor.setDataSource(path)
            }
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("No audio track found")
            extractor.selectTrack(track)
            val input = extractor.getTrackFormat(track)
            val durationUs = if (input.containsKey(MediaFormat.KEY_DURATION)) input.getLong(MediaFormat.KEY_DURATION) else 0L
            require(durationUs <= 60L * 60 * 1_000_000) { "Please use a song shorter than one hour." }
            val codec = MediaCodec.createDecoderByType(input.getString(MediaFormat.KEY_MIME)!!)
            decoder = codec
            codec.configure(input, null, null, 0)
            codec.start()
            var sampleRate = input.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = input.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            var inputDone = false
            var outputDone = false
            val info = MediaCodec.BufferInfo()
            val detector = RhythmDetector()
            var phase = 0.0
            var sum = 0.0
            var sumCount = 0
            var decodedSeconds = 0.0
            var lastProgress = -1
            var lastOutput = System.nanoTime()
            while (!outputDone) {
                if (cancelled.get()) throw CancellationException("Analysis cancelled")
                check((System.nanoTime() - lastOutput) < 30_000_000_000L) { "Audio decoder timed out" }
                if (!inputDone) {
                    val index = codec.dequeueInputBuffer(1000)
                    if (index >= 0) {
                        val buffer = codec.getInputBuffer(index)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = codec.dequeueOutputBuffer(info, 1000)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val format = codec.outputFormat
                    sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) encoding = format.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    require(encoding == AudioFormat.ENCODING_PCM_16BIT || encoding == AudioFormat.ENCODING_PCM_FLOAT) { "Unsupported PCM encoding" }
                } else if (index >= 0) {
                    lastOutput = System.nanoTime()
                    val buffer = codec.getOutputBuffer(index)!!.order(ByteOrder.LITTLE_ENDIAN)
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val frameBytes = channels * if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
                    while (buffer.remaining() >= frameBytes) {
                        var mono = 0.0
                        repeat(channels) {
                            mono += if (encoding == AudioFormat.ENCODING_PCM_FLOAT) buffer.float.toDouble() else buffer.short / 32768.0
                        }
                        mono /= channels
                        decodedSeconds += 1.0 / sampleRate
                        check(decodedSeconds <= 3600) { "Please use a song shorter than one hour." }
                        sum += mono; sumCount++
                        phase += RhythmDetector.RATE
                        while (phase >= sampleRate) {
                            detector.add(sum / max(1, sumCount))
                            phase -= sampleRate
                            // Reuse the current sample when upsampling low-rate recordings.
                            if (phase >= sampleRate) { sum = mono; sumCount = 1 } else { sum = 0.0; sumCount = 0 }
                        }
                    }
                    outputDone = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(index, false)
                    val percent = if (durationUs > 0) ((info.presentationTimeUs * 95 / durationUs).toInt()).coerceIn(0, 95) else 0
                    if (percent != lastProgress) { lastProgress = percent; progress(percent / 100.0) }
                }
            }
            if (cancelled.get()) throw CancellationException("Analysis cancelled")
            val result = detector.finish(max(decodedSeconds, durationUs / 1_000_000.0))
            if (cancelled.get()) throw CancellationException("Analysis cancelled")
            progress(1.0)
            return result
        } finally {
            try { decoder?.stop() } catch (_: Exception) { }
            decoder?.release()
            extractor.release()
        }
    }
}
