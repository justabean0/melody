package com.melody.music

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    companion object {
        fun sendPlaybackAction(action: String) {
            MelodyApplication.sendPlaybackAction(action)
        }
    }

    override fun getCachedEngineId(): String? = MelodyApplication.CACHED_ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkNotificationPermission()
    }

    override fun onResume() {
        super.onResume()
        checkNotificationPermission()
    }

    private fun checkNotificationPermission() {
        // Request POST_NOTIFICATIONS permission on Android 13+ (API 33+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
    }
}
