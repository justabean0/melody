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
import android.os.IBinder
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

        const val ACTION_PLAY = "com.melody.music.ACTION_PLAY"
        const val ACTION_PAUSE = "com.melody.music.ACTION_PAUSE"
        const val ACTION_NEXT = "com.melody.music.ACTION_NEXT"
        const val ACTION_PREV = "com.melody.music.ACTION_PREV"
        const val ACTION_STOP = "com.melody.music.ACTION_STOP"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_ARTIST = "extra_artist"
        const val EXTRA_IS_PLAYING = "extra_is_playing"
        const val EXTRA_THUMBNAIL_URL = "extra_thumbnail_url"
    }

    private var currentIsPlaying: Boolean = false
    private var mediaSession: MediaSessionCompat? = null
    private var currentThumbnailUrl: String? = null
    private var currentArtwork: Bitmap? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        initMediaSession()
    }

    private fun initMediaSession() {
        mediaSession = MediaSessionCompat(this, "MelodyMediaSession").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    MainActivity.sendPlaybackAction(ACTION_PLAY)
                }

                override fun onPause() {
                    MainActivity.sendPlaybackAction(ACTION_PAUSE)
                }

                override fun onSkipToNext() {
                    MainActivity.sendPlaybackAction(ACTION_NEXT)
                }

                override fun onSkipToPrevious() {
                    MainActivity.sendPlaybackAction(ACTION_PREV)
                }

                override fun onStop() {
                    MainActivity.sendPlaybackAction(ACTION_STOP)
                }
            })
            isActive = true
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep foreground service alive when app is cleared from recent apps if playing
        if (!currentIsPlaying) {
            stopPlaybackService()
        }
        super.onTaskRemoved(rootIntent)
    }

    private fun stopPlaybackService() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            mediaSession?.isActive = false
            mediaSession?.release()
            mediaSession = null
        } catch (_: Exception) {}
        stopSelf()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        val action = intent.action
        if (action != null) {
            when (action) {
                ACTION_STOP -> {
                    stopPlaybackService()
                    return START_NOT_STICKY
                }
                ACTION_PLAY, ACTION_PAUSE, ACTION_NEXT, ACTION_PREV -> {
                    MainActivity.sendPlaybackAction(action)
                    return START_STICKY
                }
            }
        }

        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Melody"
        val artist = intent.getStringExtra(EXTRA_ARTIST) ?: "Playing music"
        val isPlaying = intent.getBooleanExtra(EXTRA_IS_PLAYING, true)
        val thumbnailUrl = intent.getStringExtra(EXTRA_THUMBNAIL_URL)
        currentIsPlaying = isPlaying

        // Ensure MediaSession is initialized and active
        if (mediaSession == null) {
            initMediaSession()
        }

        // Update PlaybackStateCompat
        updatePlaybackState(isPlaying)

        // Check if artwork needs to be fetched
        if (thumbnailUrl != null && thumbnailUrl != currentThumbnailUrl) {
            currentThumbnailUrl = thumbnailUrl
            fetchArtworkAsync(thumbnailUrl, title, artist, isPlaying)
        } else {
            updateMetadata(title, artist, currentArtwork)
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

        return START_STICKY
    }

    private fun updatePlaybackState(isPlaying: Boolean) {
        val state = if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        val actions = PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_STOP

        val playbackState = PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(state, PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1.0f)
            .build()

        mediaSession?.setPlaybackState(playbackState)
    }

    private fun updateMetadata(title: String, artist: String, artwork: Bitmap?) {
        val metaBuilder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, "Melody Music")

        if (artwork != null) {
            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, artwork)
            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, artwork)
        }
        mediaSession?.setMetadata(metaBuilder.build())
    }

    private fun fetchArtworkAsync(urlStr: String, title: String, artist: String, isPlaying: Boolean) {
        thread {
            try {
                val url = URL(urlStr)
                val connection = url.openConnection()
                connection.connectTimeout = 3000
                connection.readTimeout = 3000
                connection.doInput = true
                connection.connect()
                val input = connection.getInputStream()
                val bitmap = BitmapFactory.decodeStream(input)
                currentArtwork = bitmap

                updateMetadata(title, artist, bitmap)

                // Re-post notification with loaded artwork
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val updatedNotification = buildNotification(title, artist, isPlaying, bitmap)
                manager.notify(NOTIFICATION_ID, updatedNotification)
            } catch (_: Exception) {}
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

        val mediaStyle = MediaStyle()
            .setShowActionsInCompactView(0, 1, 2)
        mediaSession?.sessionToken?.let {
            mediaStyle.setMediaSession(it)
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(artist)
            .setContentIntent(openPendingIntent)
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

    override fun onDestroy() {
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }
}
