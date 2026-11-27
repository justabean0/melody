package com.melody.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.media.app.NotificationCompat.MediaStyle
import java.net.URL
import kotlin.concurrent.thread

class MediaNotificationService : Service() {
    companion object {
        const val CHANNEL_ID = "melody_playback_channel"
        const val NOTIFICATION_ID = 1001

        const val PREFS_NAME = "melody_native_prefs"
        const val KEY_BACKGROUND_PLAYBACK_ENABLED = "background_playback_enabled"
        const val IDLE_TEARDOWN_DELAY_MS = 900_000L // 15 minutes
        var idleTeardownDelayMs: Long = IDLE_TEARDOWN_DELAY_MS

        var activeInstance: MediaNotificationService? = null
            private set

        const val ACTION_PLAY = "com.melody.music.ACTION_PLAY"
        const val ACTION_PAUSE = "com.melody.music.ACTION_PAUSE"
        const val ACTION_NEXT = "com.melody.music.ACTION_NEXT"
        const val ACTION_PREV = "com.melody.music.ACTION_PREV"
        const val ACTION_STOP = "com.melody.music.ACTION_STOP"
        const val ACTION_DISMISS = "com.melody.music.ACTION_DISMISS"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_ARTIST = "extra_artist"
        const val EXTRA_IS_PLAYING = "extra_is_playing"
        const val EXTRA_THUMBNAIL_URL = "extra_thumbnail_url"
        const val EXTRA_DURATION_MS = "extra_duration_ms"
        const val EXTRA_POSITION_MS = "extra_position_ms"
    }

    private var currentTitle: String = "Melody"
    private var currentArtist: String = "Playing music"
    private var currentDurationMs: Long = 0L
    private var currentPositionMs: Long = 0L
    private var lastPositionUpdateTimeMs: Long = 0L
    private var currentIsPlaying: Boolean = false
    private var mediaSession: MediaSessionCompat? = null
    private var currentThumbnailUrl: String? = null
    private var currentArtwork: Bitmap? = null

    private fun getCurrentLivePositionMs(): Long {
        if (!currentIsPlaying || lastPositionUpdateTimeMs == 0L) {
            return currentPositionMs
        }
        val elapsed = SystemClock.elapsedRealtime() - lastPositionUpdateTimeMs
        val estimated = currentPositionMs + elapsed
        return if (currentDurationMs > 0L) estimated.coerceAtMost(currentDurationMs) else estimated
    }

    private val idleHandler = Handler(Looper.getMainLooper())
    private val idleTeardownRunnable = Runnable {
        android.util.Log.d("MelodyMedia", "15-minute idle teardown triggered (app in background and playback stopped/paused)")
        MelodyApplication.sendPlaybackAction("idleTeardown")
        stopPlaybackService()
        if (!MelodyApplication.isActivityAlive) {
            MelodyApplication.destroyEngineAndExit()
        }
    }
    private var isIdleArmed = false

    fun isBackgroundPlaybackEnabled(): Boolean {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_BACKGROUND_PLAYBACK_ENABLED, false)
    }

    fun checkIdleTeardown() {
        val inBackground = !MelodyApplication.isActivityInForeground
        val isPausedOrStopped = !currentIsPlaying
        if (inBackground && isPausedOrStopped) {
            armIdleTeardown()
        } else {
            cancelIdleTeardown()
        }
    }

    fun armIdleTeardown() {
        if (!isIdleArmed) {
            android.util.Log.d("MelodyMedia", "Arming idle teardown timer ($idleTeardownDelayMs ms)")
            idleHandler.removeCallbacks(idleTeardownRunnable)
            idleHandler.postDelayed(idleTeardownRunnable, idleTeardownDelayMs)
            isIdleArmed = true
        }
    }

    fun cancelIdleTeardown() {
        if (isIdleArmed) {
            android.util.Log.d("MelodyMedia", "Canceling idle teardown timer")
            idleHandler.removeCallbacks(idleTeardownRunnable)
            isIdleArmed = false
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        createNotificationChannel()
        initMediaSession()
        checkIdleTeardown()
    }

    override fun onDestroy() {
        cancelIdleTeardown()
        if (activeInstance == this) {
            activeInstance = null
        }
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    private fun initMediaSession() {
        android.util.Log.d("MelodyMedia", "initMediaSession called")
        mediaSession = MediaSessionCompat(this, "MelodyMediaSession").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    android.util.Log.d("MelodyMedia", "MediaSessionCompat.Callback.onPlay triggered")
                    currentIsPlaying = true
                    checkIdleTeardown()
                    updatePlaybackState(true, currentPositionMs)
                    val notif = buildNotification(currentTitle, currentArtist, true, currentArtwork)
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(NOTIFICATION_ID, notif)
                    MelodyApplication.sendPlaybackAction(ACTION_PLAY)
                }

                override fun onPause() {
                    android.util.Log.d("MelodyMedia", "MediaSessionCompat.Callback.onPause triggered")
                    val livePos = getCurrentLivePositionMs()
                    currentPositionMs = livePos
                    currentIsPlaying = false
                    checkIdleTeardown()
                    updatePlaybackState(false, livePos)
                    val notif = buildNotification(currentTitle, currentArtist, false, currentArtwork)
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(NOTIFICATION_ID, notif)
                    MelodyApplication.sendPlaybackAction(ACTION_PAUSE)
                }

                override fun onSkipToNext() {
                    MelodyApplication.sendPlaybackAction(ACTION_NEXT)
                }

                override fun onSkipToPrevious() {
                    MelodyApplication.sendPlaybackAction(ACTION_PREV)
                }

                override fun onSeekTo(pos: Long) {
                    MelodyApplication.sendPlaybackAction("seek:$pos")
                    currentPositionMs = pos
                    updatePlaybackState(currentIsPlaying, pos)
                }

                override fun onStop() {
                    android.util.Log.d("MelodyMedia", "MediaSessionCompat.Callback.onStop triggered")
                    MelodyApplication.sendPlaybackAction(ACTION_STOP)
                    stopPlaybackService()
                    if (!MelodyApplication.isActivityAlive) {
                        MelodyApplication.destroyEngineAndExit()
                    }
                }
            })
            isActive = true
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val bgEnabled = isBackgroundPlaybackEnabled()
        android.util.Log.d("MelodyMedia", "onTaskRemoved: bgEnabled=$bgEnabled, currentIsPlaying=$currentIsPlaying")
        if (!bgEnabled || !currentIsPlaying) {
            MelodyApplication.sendPlaybackAction(ACTION_STOP)
            stopPlaybackService()
            if (!MelodyApplication.isActivityAlive) {
                MelodyApplication.destroyEngineAndExit()
            }
        } else {
            checkIdleTeardown()
        }
        super.onTaskRemoved(rootIntent)
    }

    private fun stopPlaybackService() {
        cancelIdleTeardown()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(NOTIFICATION_ID)
            mediaSession?.isActive = false
            mediaSession?.release()
            mediaSession = null
        } catch (_: Exception) {}
        stopSelf()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d("MelodyMedia", "onStartCommand: action=${intent?.action}, title=${intent?.getStringExtra(EXTRA_TITLE)}, isPlaying=${intent?.getBooleanExtra(EXTRA_IS_PLAYING, false)}")
        if (intent == null) return START_NOT_STICKY

        val action = intent.action
        if (action != null) {
            when (action) {
                ACTION_STOP -> {
                    android.util.Log.d("MelodyMedia", "ACTION_STOP received (from Dart hideNotification)")
                    stopPlaybackService()
                    return START_NOT_STICKY
                }
                ACTION_DISMISS -> {
                    android.util.Log.d("MelodyMedia", "ACTION_DISMISS received (notification dismissed by user)")
                    MelodyApplication.sendPlaybackAction(ACTION_STOP)
                    stopPlaybackService()
                    if (!MelodyApplication.isActivityAlive) {
                        // User dismissed notification AND app is not in recent apps -> terminate completely
                        MelodyApplication.destroyEngineAndExit()
                    }
                    return START_NOT_STICKY
                }
                ACTION_PLAY -> {
                    currentIsPlaying = true
                    checkIdleTeardown()
                    updatePlaybackState(true, currentPositionMs)
                    val notif = buildNotification(currentTitle, currentArtist, true, currentArtwork)
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(NOTIFICATION_ID, notif)
                    MelodyApplication.sendPlaybackAction(action)
                    return START_STICKY
                }
                ACTION_PAUSE -> {
                    val livePos = getCurrentLivePositionMs()
                    currentPositionMs = livePos
                    currentIsPlaying = false
                    checkIdleTeardown()
                    updatePlaybackState(false, livePos)
                    val notif = buildNotification(currentTitle, currentArtist, false, currentArtwork)
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(NOTIFICATION_ID, notif)
                    MelodyApplication.sendPlaybackAction(action)
                    return START_STICKY
                }
                ACTION_NEXT, ACTION_PREV -> {
                    MelodyApplication.sendPlaybackAction(action)
                    return START_STICKY
                }
            }
        }

        val title = intent.getStringExtra(EXTRA_TITLE) ?: currentTitle
        val artist = intent.getStringExtra(EXTRA_ARTIST) ?: currentArtist
        val isPlaying = intent.getBooleanExtra(EXTRA_IS_PLAYING, currentIsPlaying)
        val thumbnailUrl = intent.getStringExtra(EXTRA_THUMBNAIL_URL)
        val durationMs = intent.getLongExtra(EXTRA_DURATION_MS, currentDurationMs)
        val positionMs = intent.getLongExtra(EXTRA_POSITION_MS, currentPositionMs)

        currentTitle = title
        currentArtist = artist
        currentIsPlaying = isPlaying
        currentDurationMs = durationMs
        currentPositionMs = positionMs

        // Ensure MediaSession is initialized and active
        if (mediaSession == null) {
            initMediaSession()
        }

        // Update PlaybackStateCompat with accurate position and elapsed time
        updatePlaybackState(isPlaying, positionMs)

        // Check if artwork needs to be fetched or cleared for local tracks without art
        if (thumbnailUrl.isNullOrEmpty()) {
            currentThumbnailUrl = null
            currentArtwork = null
            updateMetadata(title, artist, null, durationMs)
        } else if (thumbnailUrl != currentThumbnailUrl) {
            currentThumbnailUrl = thumbnailUrl
            currentArtwork = null
            fetchArtworkAsync(thumbnailUrl, title, artist, durationMs, isPlaying)
        } else {
            updateMetadata(title, artist, currentArtwork, durationMs)
        }

        val notification = buildNotification(title, artist, isPlaying, currentArtwork)

        // Android 14+ requires explicit FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK flag
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        checkIdleTeardown()

        return START_STICKY
    }

    private fun updatePlaybackState(isPlaying: Boolean, positionMs: Long) {
        val state = if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        val actions = PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_SEEK_TO or
                PlaybackStateCompat.ACTION_STOP

        currentPositionMs = positionMs
        lastPositionUpdateTimeMs = SystemClock.elapsedRealtime()

        val playbackState = PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(
                state,
                positionMs,
                if (isPlaying) 1.0f else 0.0f,
                lastPositionUpdateTimeMs
            )
            .build()

        mediaSession?.setPlaybackState(playbackState)
    }

    private fun updateMetadata(title: String, artist: String, artwork: Bitmap?, durationMs: Long) {
        val metaBuilder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, "Melody Music")

        if (durationMs > 0L) {
            metaBuilder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
        }

        if (artwork != null) {
            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, artwork)
            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, artwork)
        }
        mediaSession?.setMetadata(metaBuilder.build())
    }

    private fun fetchArtworkAsync(urlStr: String, title: String, artist: String, durationMs: Long, isPlaying: Boolean) {
        thread {
            try {
                val bitmap: Bitmap? = if (urlStr.startsWith("content://") || urlStr.startsWith("file://")) {
                    contentResolver.openInputStream(android.net.Uri.parse(urlStr))?.use { input ->
                        BitmapFactory.decodeStream(input)
                    }
                } else {
                    val url = URL(urlStr)
                    val connection = url.openConnection()
                    connection.connectTimeout = 3000
                    connection.readTimeout = 3000
                    connection.doInput = true
                    connection.connect()
                    connection.getInputStream().use { input ->
                        BitmapFactory.decodeStream(input)
                    }
                }
                currentArtwork = bitmap

                updateMetadata(title, artist, bitmap, durationMs)

                // Re-post notification with loaded artwork
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val updatedNotification = buildNotification(title, artist, isPlaying, bitmap)
                manager.notify(NOTIFICATION_ID, updatedNotification)
            } catch (_: Exception) {
                currentArtwork = null
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Music Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows active playback controls"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, artist: String, isPlaying: Boolean, artwork: Bitmap?): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val openPendingIntent = PendingIntent.getActivity(this, 0, openIntent, flags)

        val prevIntent = Intent(this, MediaNotificationService::class.java).apply { action = ACTION_PREV }
        val prevPending = PendingIntent.getService(this, 1, prevIntent, flags)

        val playPauseAction = if (isPlaying) ACTION_PAUSE else ACTION_PLAY
        val playPauseIntent = Intent(this, MediaNotificationService::class.java).apply { action = playPauseAction }
        val playPausePending = PendingIntent.getService(this, 2, playPauseIntent, flags)

        val nextIntent = Intent(this, MediaNotificationService::class.java).apply { action = ACTION_NEXT }
        val nextPending = PendingIntent.getService(this, 3, nextIntent, flags)

        val stopIntent = Intent(this, MediaNotificationService::class.java).apply { action = ACTION_STOP }
        val stopPending = PendingIntent.getService(this, 4, stopIntent, flags)

        val dismissIntent = Intent(this, MediaNotificationService::class.java).apply { action = ACTION_DISMISS }
        val dismissPending = PendingIntent.getService(this, 5, dismissIntent, flags)

        val mediaStyle = MediaStyle()
            .setShowActionsInCompactView(0, 1, 2)
        mediaSession?.sessionToken?.let {
            mediaStyle.setMediaSession(it)
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(artist)
            .setContentIntent(openPendingIntent)
            .setDeleteIntent(dismissPending)
            .setOngoing(isPlaying)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setStyle(mediaStyle)
            .addAction(android.R.drawable.ic_media_previous, "Previous", prevPending)
            .addAction(
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (isPlaying) "Pause" else "Play",
                playPausePending
            )
            .addAction(android.R.drawable.ic_media_next, "Next", nextPending)

        if (artwork != null) {
            builder.setLargeIcon(artwork)
        }

        return builder.build()
    }
}
