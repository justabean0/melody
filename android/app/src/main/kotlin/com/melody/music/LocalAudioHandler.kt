package com.melody.music

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors

object LocalAudioHandler {
    const val CHANNEL_NAME = "com.melody.music/local_audio"
    const val REQUEST_CODE_AUDIO_PERMISSION = 4201
    private const val PREFS_NAME = "melody_native_prefs"
    private const val KEY_AUDIO_PERMISSION_REQUESTED = "audio_permission_requested"

    private val ioExecutor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var pendingPermissionResult: MethodChannel.Result? = null

    private fun readPermissionsForSdk(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_AUDIO)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun requestPermissionsForSdk(): Array<String> {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> {
                arrayOf(Manifest.permission.READ_MEDIA_AUDIO)
            }
            Build.VERSION.SDK_INT <= Build.VERSION_CODES.P -> {
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                )
            }
            else -> {
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
            }
        }
    }

    fun hasReadAudioPermission(context: Context): Boolean {
        return readPermissionsForSdk().all { perm ->
            ContextCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasWriteStoragePermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_EXTERNAL_STORAGE
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun computePermanentlyDenied(context: Context, activity: Activity?): Boolean {
        if (hasReadAudioPermission(context)) return false
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val requestedBefore = prefs.getBoolean(KEY_AUDIO_PERMISSION_REQUESTED, false)
        if (!requestedBefore || activity == null) return false
        val anyRationale = readPermissionsForSdk().any { perm ->
            ActivityCompat.shouldShowRequestPermissionRationale(activity, perm)
        }
        return !anyRationale
    }

    fun register(
        messenger: BinaryMessenger,
        context: Context,
        activityProvider: () -> Activity?
    ) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAudioPermission" -> {
                    result.success(hasReadAudioPermission(appContext))
                }
                "getAudioPermissionStatus" -> {
                    val granted = hasReadAudioPermission(appContext)
                    val permanentlyDenied = computePermanentlyDenied(appContext, activityProvider())
                    result.success(
                        mapOf(
                            "granted" to granted,
                            "permanentlyDenied" to permanentlyDenied
                        )
                    )
                }
                "requestAudioPermission" -> {
                    val granted = hasReadAudioPermission(appContext) &&
                        (Build.VERSION.SDK_INT > Build.VERSION_CODES.P || hasWriteStoragePermission(appContext))
                    if (granted) {
                        result.success(
                            mapOf(
                                "granted" to true,
                                "permanentlyDenied" to false
                            )
                        )
                        return@setMethodCallHandler
                    }
                    val activity = activityProvider()
                    if (activity == null) {
                        result.error("NO_ACTIVITY", "Foreground activity unavailable for permission prompt", null)
                        return@setMethodCallHandler
                    }
                    pendingPermissionResult?.error(
                        "CANCELLED",
                        "Superseded by another permission request",
                        null
                    )
                    pendingPermissionResult = result

                    appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(KEY_AUDIO_PERMISSION_REQUESTED, true)
                        .apply()

                    ActivityCompat.requestPermissions(
                        activity,
                        requestPermissionsForSdk(),
                        REQUEST_CODE_AUDIO_PERMISSION
                    )
                }
                "openAppSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:${appContext.packageName}")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        appContext.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
                "scanLocalAudio" -> {
                    val melodyOnly = call.argument<Boolean>("melodyOnly") ?: false
                    ioExecutor.execute {
                        try {
                            val tracks = scanMediaStoreAudio(appContext, melodyOnly)
                            mainHandler.post { result.success(tracks) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "saveTrackToMediaStore" -> {
                    val tempFilePath = call.argument<String>("tempFilePath")
                    val title = call.argument<String>("title") ?: "Unknown Track"
                    val artist = call.argument<String>("artist") ?: "Unknown Artist"
                    val extension = (call.argument<String>("extension") ?: "m4a")
                        .trimStart('.')
                        .ifEmpty { "m4a" }
                    val mimeType = call.argument<String>("mimeType") ?: "audio/mp4"

                    if (tempFilePath.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "tempFilePath must not be empty", null)
                        return@setMethodCallHandler
                    }

                    ioExecutor.execute {
                        try {
                            val saved = commitTrackToMediaStore(
                                context = appContext,
                                tempFilePath = tempFilePath,
                                title = title,
                                artist = artist,
                                extension = extension,
                                mimeType = mimeType
                            )
                            mainHandler.post { result.success(saved) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("SAVE_MEDIASTORE_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
        activity: Activity
    ): Boolean {
        if (requestCode != REQUEST_CODE_AUDIO_PERMISSION) return false
        val pending = pendingPermissionResult ?: return false
        pendingPermissionResult = null

        val granted = hasReadAudioPermission(activity.applicationContext)
        val permanentlyDenied = computePermanentlyDenied(activity.applicationContext, activity)
        pending.success(
            mapOf(
                "granted" to granted,
                "permanentlyDenied" to permanentlyDenied
            )
        )
        return true
    }

    private fun sanitizeFileComponent(raw: String, fallback: String): String {
        val cleaned = raw
            .replace(Regex("""[/\\:*?"<>|\u0000-\u001F]"""), " ")
            .replace(Regex("""\s+"""), " ")
            .trim()
        if (cleaned.isEmpty()) return fallback
        return if (cleaned.length > 80) cleaned.substring(0, 80).trim() else cleaned
    }

    private fun commitTrackToMediaStore(
        context: Context,
        tempFilePath: String,
        title: String,
        artist: String,
        extension: String,
        mimeType: String
    ): Map<String, Any?> {
        val sourceFile = File(tempFilePath)
        if (!sourceFile.exists() || sourceFile.length() <= 0L) {
            throw IllegalStateException("Temporary downloaded file is missing or empty")
        }

        val cleanTitle = sanitizeFileComponent(title, "Melody Track")
        val cleanArtist = sanitizeFileComponent(artist, "Unknown Artist")
        val baseName = "$cleanTitle - $cleanArtist"
        val displayName = "$baseName.$extension"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Audio.Media.TITLE, title.trim().ifEmpty { cleanTitle })
                put(MediaStore.Audio.Media.ARTIST, artist.trim().ifEmpty { cleanArtist })
                put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/Melody")
                put(MediaStore.Audio.Media.IS_MUSIC, 1)
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }

            val insertedUri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Failed to create MediaStore row in Music/Melody")

            try {
                resolver.openOutputStream(insertedUri)?.use { out ->
                    sourceFile.inputStream().use { input ->
                        input.copyTo(out)
                    }
                } ?: throw IllegalStateException("Unable to open MediaStore output stream")

                val publishValues = ContentValues().apply {
                    put(MediaStore.Audio.Media.IS_PENDING, 0)
                }
                resolver.update(insertedUri, publishValues, null, null)

                return mapOf(
                    "contentUri" to insertedUri.toString(),
                    "displayName" to displayName,
                    "relativePath" to "${Environment.DIRECTORY_MUSIC}/Melody/"
                )
            } catch (e: Exception) {
                try {
                    resolver.delete(insertedUri, null, null)
                } catch (_: Exception) {}
                throw e
            }
        } else {
            if (!hasWriteStoragePermission(context)) {
                throw SecurityException("WRITE_EXTERNAL_STORAGE permission is required to save music on Android 9 and below")
            }

            val musicRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
            val melodyDir = File(musicRoot, "Melody")
            if (!melodyDir.exists() && !melodyDir.mkdirs()) {
                throw IllegalStateException("Could not create Music/Melody directory")
            }

            var targetFile = File(melodyDir, displayName)
            var counter = 1
            while (targetFile.exists()) {
                targetFile = File(melodyDir, "$baseName ($counter).$extension")
                counter++
            }

            sourceFile.inputStream().use { input ->
                targetFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }

            var resolvedUri: Uri? = null
            val latch = java.util.concurrent.CountDownLatch(1)
            MediaScannerConnection.scanFile(
                context,
                arrayOf(targetFile.absolutePath),
                arrayOf(mimeType)
            ) { _, uri ->
                resolvedUri = uri
                latch.countDown()
            }
            latch.await(2, java.util.concurrent.TimeUnit.SECONDS)

            val uriString = (resolvedUri ?: Uri.fromFile(targetFile)).toString()
            return mapOf(
                "contentUri" to uriString,
                "filePath" to targetFile.absolutePath,
                "displayName" to targetFile.name,
                "relativePath" to "Music/Melody/"
            )
        }
    }

    private fun scanMediaStoreAudio(
        context: Context,
        melodyOnly: Boolean
    ): List<Map<String, Any?>> {
        if (!melodyOnly && !hasReadAudioPermission(context)) {
            return emptyList()
        }

        val resolver = context.contentResolver
        val tracks = mutableListOf<Map<String, Any?>>()

        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.ALBUM_ID
        ).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                add(MediaStore.Audio.Media.RELATIVE_PATH)
                add(MediaStore.Audio.Media.IS_PENDING)
            } else {
                @Suppress("DEPRECATION")
                add(MediaStore.Audio.Media.DATA)
            }
        }.toTypedArray()

        val selection: String
        val selectionArgs: Array<String>?
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (melodyOnly) {
                selection = "(${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ? OR ${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?) AND ${MediaStore.Audio.Media.IS_PENDING} = 0"
                selectionArgs = arrayOf("%Music/Melody%", "%Music\\Melody%")
            } else {
                selection = "(${MediaStore.Audio.Media.IS_MUSIC} != 0 OR ${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?) AND ${MediaStore.Audio.Media.IS_PENDING} = 0"
                selectionArgs = arrayOf("%Music/Melody%")
            }
        } else {
            @Suppress("DEPRECATION")
            val dataCol = MediaStore.Audio.Media.DATA
            if (melodyOnly) {
                selection = "$dataCol LIKE ?"
                selectionArgs = arrayOf("%/Music/Melody/%")
            } else {
                selection = "(${MediaStore.Audio.Media.IS_MUSIC} != 0 OR $dataCol LIKE ?)"
                selectionArgs = arrayOf("%/Music/Melody/%")
            }
        }

        val sortOrder = "${MediaStore.Audio.Media.DATE_ADDED} DESC"
        resolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleIdx = cursor.getColumnIndex(MediaStore.Audio.Media.TITLE)
            val artistIdx = cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST)
            val albumIdx = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM)
            val durationIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)
            val dateAddedIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DATE_ADDED)
            val displayNameIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
            val albumIdIdx = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM_ID)
            val relPathIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)
            } else {
                -1
            }
            @Suppress("DEPRECATION")
            val dataIdx = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIdx)
                val contentUri = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    id
                ).toString()

                val rawTitle = if (titleIdx >= 0) cursor.getString(titleIdx) else null
                val rawDisplayName = if (displayNameIdx >= 0) cursor.getString(displayNameIdx) else null
                val title = rawTitle?.trim().takeIf { !it.isNullOrEmpty() }
                    ?: rawDisplayName?.substringBeforeLast('.')?.trim().takeIf { !it.isNullOrEmpty() }
                    ?: "Unknown Track"

                val rawArtist = if (artistIdx >= 0) cursor.getString(artistIdx) else null
                val artist = if (rawArtist.isNullOrBlank() || rawArtist.equals("<unknown>", ignoreCase = true)) {
                    "Unknown Artist"
                } else {
                    rawArtist.trim()
                }

                val rawAlbum = if (albumIdx >= 0) cursor.getString(albumIdx) else null
                val album = if (rawAlbum.isNullOrBlank() || rawAlbum.equals("<unknown>", ignoreCase = true)) {
                    null
                } else {
                    rawAlbum.trim()
                }

                val durationMs = if (durationIdx >= 0) cursor.getLong(durationIdx).coerceAtLeast(0L) else 0L
                val dateAdded = if (dateAddedIdx >= 0) cursor.getLong(dateAddedIdx).coerceAtLeast(0L) else 0L

                val relPath = when {
                    relPathIdx >= 0 -> cursor.getString(relPathIdx) ?: ""
                    dataIdx >= 0 -> cursor.getString(dataIdx) ?: ""
                    else -> ""
                }
                val normalizedPath = relPath.replace('\\', '/').lowercase(Locale.ROOT)
                val isMelodyDownload = normalizedPath.contains("music/melody")

                val albumId = if (albumIdIdx >= 0) cursor.getLong(albumIdIdx) else -1L
                val albumArtUri = if (albumId > 0L) {
                    ContentUris.withAppendedId(
                        Uri.parse("content://media/external/audio/albumart"),
                        albumId
                    ).toString()
                } else {
                    null
                }

                tracks.add(
                    mapOf(
                        "id" to id.toString(),
                        "contentUri" to contentUri,
                        "title" to title,
                        "artist" to artist,
                        "album" to album,
                        "durationMs" to durationMs,
                        "dateAdded" to dateAdded,
                        "relativePath" to relPath,
                        "displayName" to (rawDisplayName ?: ""),
                        "isMelodyDownload" to isMelodyDownload,
                        "albumArtUri" to albumArtUri
                    )
                )
            }
        }

        return tracks
    }
}
