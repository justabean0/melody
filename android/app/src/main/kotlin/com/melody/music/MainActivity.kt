package com.melody.music

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    companion object {
        private const val UPDATER_CHANNEL = "com.melody.music/updater"
        private const val PLAYBACK_CHANNEL = "com.melody.music/playback"

        private var playbackChannel: MethodChannel? = null

        fun sendPlaybackAction(action: String) {
            val flutterAction = when {
                action == MediaNotificationService.ACTION_PLAY || action == MediaNotificationService.ACTION_PAUSE -> "playPause"
                action == MediaNotificationService.ACTION_NEXT -> "next"
                action == MediaNotificationService.ACTION_PREV -> "prev"
                action.startsWith("seek:") -> action
                else -> return
            }
            playbackChannel?.invokeMethod("onNotificationAction", flutterAction)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Request POST_NOTIFICATIONS permission on Android 13+ (API 33+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }

        // 1. In-App Updater Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> {
                    try {
                        val pInfo = packageManager.getPackageInfo(packageName, 0)
                        val versionName = pInfo.versionName ?: "1.0.0"
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            pInfo.versionCode.toLong()
                        }
                        result.success(mapOf(
                            "versionName" to versionName,
                            "versionCode" to versionCode
                        ))
                    } catch (e: Exception) {
                        result.error("VERSION_ERROR", e.message, null)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_PATH", "File path cannot be null or empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }

                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            file
                        )

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 2. Persistent Media Playback Notification Channel
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAYBACK_CHANNEL)
        playbackChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Melody"
                    val artist = call.argument<String>("artist") ?: "Playing music"
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val thumbnailUrl = call.argument<String>("thumbnailUrl")
                    val durationMs = call.argument<Number>("durationMs")?.toLong() ?: 0L
                    val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L

                    val intent = Intent(this, MediaNotificationService::class.java).apply {
                        putExtra(MediaNotificationService.EXTRA_TITLE, title)
                        putExtra(MediaNotificationService.EXTRA_ARTIST, artist)
                        putExtra(MediaNotificationService.EXTRA_IS_PLAYING, isPlaying)
                        putExtra(MediaNotificationService.EXTRA_DURATION_MS, durationMs)
                        putExtra(MediaNotificationService.EXTRA_POSITION_MS, positionMs)
                        if (!thumbnailUrl.isNullOrEmpty()) {
                            putExtra(MediaNotificationService.EXTRA_THUMBNAIL_URL, thumbnailUrl)
                        }
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "hideNotification" -> {
                    val intent = Intent(this, MediaNotificationService::class.java).apply {
                        action = MediaNotificationService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        playbackChannel = null
        super.onDestroy()
    }
}
