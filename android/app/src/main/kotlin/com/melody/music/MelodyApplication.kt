package com.melody.music

import android.app.Activity
import android.app.Application
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File

class MelodyApplication : Application() {
    companion object {
        const val CACHED_ENGINE_ID = "melody_cached_engine"
        const val PLAYBACK_CHANNEL = "com.melody.music/playback"
        const val UPDATER_CHANNEL = "com.melody.music/updater"
        const val DIAGNOSTICS_CHANNEL = "com.melody.music/diagnostics"

        var flutterEngine: FlutterEngine? = null
            private set
        var playbackChannel: MethodChannel? = null
            private set

        var isActivityAlive: Boolean = false
            private set
        var isActivityInForeground: Boolean = false
            private set
        var currentActivity: Activity? = null
            private set

        private val mainHandler = Handler(Looper.getMainLooper())

        fun sendPlaybackAction(action: String) {
            android.util.Log.d("MelodyMedia", "sendPlaybackAction: action=$action, channel=$playbackChannel")
            val flutterAction = when {
                action == MediaNotificationService.ACTION_PLAY -> "play"
                action == MediaNotificationService.ACTION_PAUSE -> "pause"
                action == MediaNotificationService.ACTION_NEXT -> "next"
                action == MediaNotificationService.ACTION_PREV -> "prev"
                action == MediaNotificationService.ACTION_STOP -> "stop"
                action.startsWith("seek:") -> action
                else -> return
            }
            mainHandler.post {
                android.util.Log.d("MelodyMedia", "Invoking onNotificationAction: $flutterAction")
                playbackChannel?.invokeMethod("onNotificationAction", flutterAction)
            }
        }

        fun destroyEngineAndExit() {
            android.util.Log.d("MelodyMedia", "destroyEngineAndExit called: terminating background engine and process")
            mainHandler.post {
                try {
                    flutterEngine?.destroy()
                    FlutterEngineCache.getInstance().remove(CACHED_ENGINE_ID)
                    flutterEngine = null
                    playbackChannel = null
                } catch (_: Exception) {}
                Process.killProcess(Process.myPid())
            }
        }
    }

    override fun onCreate() {
        super.onCreate()

        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            private var aliveCount = 0
            private var resumedCount = 0

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                aliveCount++
                isActivityAlive = aliveCount > 0
                currentActivity = activity
                android.util.Log.d("MelodyMedia", "Activity created. isActivityAlive=$isActivityAlive (aliveCount=$aliveCount)")
            }

            override fun onActivityStarted(activity: Activity) {
                currentActivity = activity
            }

            override fun onActivityResumed(activity: Activity) {
                resumedCount++
                isActivityInForeground = resumedCount > 0
                currentActivity = activity
            }

            override fun onActivityPaused(activity: Activity) {
                resumedCount--
                isActivityInForeground = resumedCount > 0
            }

            override fun onActivityStopped(activity: Activity) {
                if (currentActivity == activity) {
                    currentActivity = null
                }
            }

            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

            override fun onActivityDestroyed(activity: Activity) {
                aliveCount--
                isActivityAlive = aliveCount > 0
                if (currentActivity == activity) {
                    currentActivity = null
                }
                android.util.Log.d("MelodyMedia", "Activity destroyed. isActivityAlive=$isActivityAlive (aliveCount=$aliveCount)")
            }
        })

        // 1. Initialize FlutterEngine
        val engine = FlutterEngine(this)

        // 2. Register all plugins (GeneratedPluginRegistrant)
        GeneratedPluginRegistrant.registerWith(engine)

        // 3. Cache the pre-warmed FlutterEngine
        FlutterEngineCache.getInstance().put(CACHED_ENGINE_ID, engine)

        // 4. Start Dart execution with default entrypoint
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )

        flutterEngine = engine

        // 5. Setup persistent Playback Channel
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, PLAYBACK_CHANNEL)
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

        // 6. Setup persistent In-App Updater Channel
        MethodChannel(engine.dartExecutor.binaryMessenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
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
                        val isDebug = packageName.endsWith(".debug")
                        result.success(mapOf(
                            "versionName" to versionName,
                            "versionCode" to versionCode,
                            "packageName" to packageName,
                            "isDebug" to isDebug
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

        // 7. Setup Diagnostics Channel (Share & Save Crash Logs)
        MethodChannel(engine.dartExecutor.binaryMessenger, DIAGNOSTICS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareLogFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val title = call.argument<String>("title") ?: "Melody Diagnostic Log"
                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_PATH", "File path cannot be null or empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "Log file does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }

                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            file
                        )

                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            putExtra(Intent.EXTRA_SUBJECT, title)
                            putExtra(Intent.EXTRA_TEXT, "Attached Melody Diagnostic Log ($title)")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }

                        val chooser = Intent.createChooser(shareIntent, title).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        val targetContext = currentActivity ?: this
                        targetContext.startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_ERROR", e.message, null)
                    }
                }
                "saveToDownloads" -> {
                    val content = call.argument<String>("content") ?: ""
                    val fileName = call.argument<String>("fileName") ?: "melody_crash_log.txt"

                    try {
                        val savedPath: String
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
                                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                            }
                            val resolver = contentResolver
                            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                ?: throw Exception("Failed to create MediaStore entry in Downloads")
                            resolver.openOutputStream(uri)?.use { os ->
                                os.write(content.toByteArray(Charsets.UTF_8))
                            }
                            savedPath = "Downloads/$fileName"
                        } else {
                            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                            if (!downloadsDir.exists()) downloadsDir.mkdirs()
                            val file = File(downloadsDir, fileName)
                            file.writeText(content, Charsets.UTF_8)
                            savedPath = file.absolutePath
                        }
                        result.success(savedPath)
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
