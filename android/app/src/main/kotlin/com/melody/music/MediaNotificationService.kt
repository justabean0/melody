package com.melody.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

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
    }

    private var currentIsPlaying: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep foreground service alive when app is cleared from recent apps if playing
        if (!currentIsPlaying) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        val action = intent.action
        if (action != null) {
            when (action) {
                ACTION_STOP -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                    } else {
                        @Suppress("DEPRECATION")
                        stopForeground(true)
                    }
                    stopSelf()
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
        currentIsPlaying = isPlaying

        val notification = buildNotification(title, artist, isPlaying)
        startForeground(NOTIFICATION_ID, notification)

        return START_STICKY
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

    private fun buildNotification(title: String, artist: String, isPlaying: Boolean): Notification {
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

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(artist)
            .setContentIntent(openPendingIntent)
            .setOngoing(isPlaying)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_media_previous, "Previous", prevPending)
            .addAction(
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (isPlaying) "Pause" else "Play",
                playPausePending
            )
            .addAction(android.R.drawable.ic_media_next, "Next", nextPending)
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setShowActionsInCompactView(0, 1, 2)
            )

        return builder.build()
    }
}
