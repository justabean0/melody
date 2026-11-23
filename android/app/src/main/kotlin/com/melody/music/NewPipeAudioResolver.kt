package com.melody.music

import android.net.Uri
import android.util.Log
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import java.net.InetAddress
import java.util.Locale

object NewPipeAudioResolver {
    private const val TAG = "NewPipeResolver"
    private val VIDEO_ID_REGEX = Regex("^[a-zA-Z0-9_-]{11}$")

    @Volatile
    private var isInitialized = false

    @Synchronized
    fun ensureInitialized() {
        if (!isInitialized) {
            NewPipe.init(NewPipeDownloader.getInstance())
            isInitialized = true
            Log.d(TAG, "NewPipeExtractor initialized successfully")
        }
    }

    /**
     * Security validation for the resolved stream URL.
     * Rejects non-HTTPS, loopback, private IPs, credentials, or malicious targets.
     */
    private fun isValidPublicStreamUrl(rawUrl: String): Boolean {
        try {
            val uri = Uri.parse(rawUrl)
            if (uri.scheme?.lowercase(Locale.ROOT) != "https") return false
            if (uri.userInfo != null) return false

            val host = uri.host?.lowercase(Locale.ROOT) ?: return false
            if (host.isEmpty()) return false

            if (host == "localhost" || host.endsWith(".local") || host.endsWith(".internal")) {
                return false
            }

            // Check for private / loopback IP addresses (IPv4 & IPv6 literals)
            try {
                val ipRegex = Regex("^(\\d{1,3}\\.){3}\\d{1,3}$")
                val isIpv6 = (host.startsWith("[") && host.endsWith("]")) || host.contains(":")
                val cleanHost = if (host.startsWith("[") && host.endsWith("]")) host.substring(1, host.length - 1) else host
                if (ipRegex.matches(host) || isIpv6) {
                    val inet = InetAddress.getByName(cleanHost)
                    if (inet.isLoopbackAddress || inet.isSiteLocalAddress || inet.isLinkLocalAddress || inet.isAnyLocalAddress || inet.isMulticastAddress) {
                        return false
                    }
                }
            } catch (_: Exception) {}

            return true
        } catch (_: Exception) {
            return false
        }
    }

    @Throws(Exception::class)
    fun resolveAudioStream(videoId: String): Map<String, Any?> {
        // Strict Security validation on videoId input
        if (!VIDEO_ID_REGEX.matches(videoId)) {
            throw IllegalArgumentException("Invalid YouTube videoId format: $videoId")
        }

        ensureInitialized()

        val watchUrl = "https://www.youtube.com/watch?v=$videoId"
        val streamInfo = StreamInfo.getInfo(ServiceList.YouTube, watchUrl)

        val audioStreams = streamInfo.audioStreams ?: emptyList<AudioStream>()
        if (audioStreams.isEmpty()) {
            throw IllegalStateException("No audio streams available for $videoId")
        }

        // Filter valid playable audio streams
        val validStreams = audioStreams.filter { stream ->
            val content = stream.content
            !content.isNullOrEmpty() &&
                isValidPublicStreamUrl(content) &&
                stream.deliveryMethod != DeliveryMethod.TORRENT
        }

        if (validStreams.isEmpty()) {
            throw IllegalStateException("No valid HTTPS public audio streams found for $videoId")
        }

        // Rank audio streams:
        // Priority 1: itag 140 (M4A / AAC 128kbps - universal, instant hardware decode on Android)
        // Priority 2: itag 251 (Opus 160kbps)
        // Priority 3: Other audio streams with highest bitrate
        val selectedStream = validStreams.sortedWith { a, b ->
            val aItag = a.itag
            val bItag = b.itag

            val aIs140 = aItag == 140
            val bIs140 = bItag == 140
            if (aIs140 && !bIs140) return@sortedWith -1
            if (!aIs140 && bIs140) return@sortedWith 1

            val aIs251 = aItag == 251
            val bIs251 = bItag == 251
            if (aIs251 && !bIs251) return@sortedWith -1
            if (!aIs251 && bIs251) return@sortedWith 1

            val aBitrate = a.averageBitrate
            val bBitrate = b.averageBitrate
            bBitrate.compareTo(aBitrate)
        }.first()

        val streamUrl = selectedStream.content
        val itag = selectedStream.itag
        val bitrate = selectedStream.averageBitrate
        val formatName = selectedStream.format?.name ?: "unknown"
        val mimeType = selectedStream.format?.mimeType ?: "audio/*"
        val durationMs = streamInfo.duration * 1000L

        Log.d(TAG, "Resolved audio for $videoId: itag=$itag, bitrate=${bitrate}kbps, format=$formatName")

        return mapOf(
            "url" to streamUrl,
            "itag" to itag,
            "bitrate" to bitrate,
            "format" to formatName,
            "mimeType" to mimeType,
            "durationMs" to durationMs
        )
    }
}
