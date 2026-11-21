package com.melody.music

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    companion object {
        const val BATTERY_CHANNEL = "com.melody.music/battery"

        fun sendPlaybackAction(action: String) {
            MelodyApplication.sendPlaybackAction(action)
        }

        fun registerBatteryChannel(messenger: io.flutter.plugin.common.BinaryMessenger, context: Context) {
            MethodChannel(messenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                            val isIgnoring = powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false
                            result.success(isIgnoring)
                        } else {
                            result.success(true)
                        }
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:${context.packageName}")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                context.startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                try {
                                    val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    context.startActivity(fallbackIntent)
                                    result.success(true)
                                } catch (e2: Exception) {
                                    result.error("BATTERY_INTENT_ERROR", e2.message, null)
                                }
                            }
                        } else {
                            result.success(true)
                        }
                    }
                    "openBatteryOptimizationSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                context.startActivity(fallbackIntent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("BATTERY_INTENT_ERROR", e2.message, null)
                            }
                        }
                    }
                    "setBackgroundPlaybackEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val prefs = context.getSharedPreferences(MediaNotificationService.PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putBoolean(MediaNotificationService.KEY_BACKGROUND_PLAYBACK_ENABLED, enabled).apply()
                        result.success(true)
                    }
                    "getBackgroundPlaybackEnabled" -> {
                        val prefs = context.getSharedPreferences(MediaNotificationService.PREFS_NAME, Context.MODE_PRIVATE)
                        val enabled = prefs.getBoolean(MediaNotificationService.KEY_BACKGROUND_PLAYBACK_ENABLED, true)
                        result.success(enabled)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun getCachedEngineId(): String? = MelodyApplication.CACHED_ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerBatteryChannel(flutterEngine.dartExecutor.binaryMessenger, this)
    }
}
