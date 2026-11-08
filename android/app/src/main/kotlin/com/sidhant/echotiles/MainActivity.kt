package com.sidhant.echotiles

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.CancellationException

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var cancelled: AtomicBoolean? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "echotiles/analysis")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> { cancelled?.set(true); result.success(null) }
                "analyze" -> {
                    val path = call.argument<String>("path")
                    if (path == null) { result.error("INPUT", "Missing audio path", null); return@setMethodCallHandler }
                    if (cancelled != null) { result.error("BUSY", "An analysis is already running", null); return@setMethodCallHandler }
                    val token = AtomicBoolean(false)
                    cancelled = token
                    worker.execute {
                        try {
                            val analysis = AudioAnalyzer(applicationContext).analyze(path, token) { progress ->
                                runOnUiThread { channel.invokeMethod("progress", progress) }
                            }
                            runOnUiThread { cancelled = null; result.success(analysis) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                cancelled = null
                                result.error(if (e is CancellationException) "CANCELLED" else "ANALYSIS", e.message ?: "Cannot decode this audio file", null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        cancelled?.set(true)
        worker.shutdownNow()
        super.onDestroy()
    }
}
