package com.example.botswana_plot_finder

import android.hardware.GeomagneticField
import android.media.AudioManager
import android.media.ToneGenerator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tone: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pathfinder/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "beep" -> {
                        beep()
                        result.success(null)
                    }
                    "declination" -> {
                        val lat = call.number("lat")
                        val lon = call.number("lon")
                        val alt = call.number("alt")
                        val field = GeomagneticField(
                            lat.toFloat(),
                            lon.toFloat(),
                            alt.toFloat(),
                            System.currentTimeMillis(),
                        )
                        // Positive = east of true north. Botswana is west, so negative.
                        result.success(field.declination.toDouble())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun beep() {
        try {
            val gen = tone ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100).also {
                tone = it
            }
            gen.startTone(ToneGenerator.TONE_PROP_BEEP, 200)
        } catch (e: Exception) {
        }
    }

    override fun onDestroy() {
        tone?.release()
        tone = null
        super.onDestroy()
    }
}

private fun io.flutter.plugin.common.MethodCall.number(key: String): Double {
    return when (val v = argument<Any>(key)) {
        is Double -> v
        is Float -> v.toDouble()
        is Int -> v.toDouble()
        is Long -> v.toDouble()
        else -> 0.0
    }
}
