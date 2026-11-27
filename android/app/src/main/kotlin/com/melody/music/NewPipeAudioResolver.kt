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

    private fun normalizeQuality(rawQuality: String?): String {
        return when (rawQuality?.trim()?.lowercase(Locale.ROOT)) {
            "low" -> "Low"
            "medium" -> "Medium"
            else -> "High"
        }
    }

    private fun isM4aStream(stream: AudioStream): Boolean {
        val mime = stream.format?.mimeType?.lowercase(Locale.ROOT) ?: ""
        val formatName = stream.format?.name?.lowercase(Locale.ROOT) ?: ""
        return mime.contains("mp4") ||
            formatName.contains("m4a") ||
            stream.itag == 139 ||
            stream.itag == 140 ||
            stream.itag == 141
    }

    private fun selectAudioStream(
        streams: List<AudioStream>,
        quality: String,
        preferM4a: Boolean = false
    ): AudioStream {
        if (preferM4a) {
            val m4aCandidates = streams.filter(::isM4aStream)
            if (m4aCandidates.isNotEmpty()) {
                return m4aCandidates.sortedWith { a, b ->
                    val cmp = b.averageBitrate.compareTo(a.averageBitrate)
                    if (cmp != 0) cmp else b.itag.compareTo(a.itag)
                }.first()
            }
            return streams.sortedWith { a, b ->
                val cmp = b.averageBitrate.compareTo(a.averageBitrate)
                if (cmp != 0) cmp else b.itag.compareTo(a.itag)
            }.first()
        }

        val tier = normalizeQuality(quality)
        if (streams.size <= 1) return streams.first()

        fun itagPriority(itag: Int): Int {
            return if (tier == "High") {
                when (itag) {
                    251 -> 2
                    140 -> 1
                    else -> 0
                }
            } else {
                when (itag) {
                    140 -> 2
                    251 -> 1
                    else -> 0
                }
            }
        }

        return streams.sortedWith { a, b ->
            val aBitrate = a.averageBitrate
            val bBitrate = b.averageBitrate
            val aHasBitrate = aBitrate > 0
            val bHasBitrate = bBitrate > 0
            if (aHasBitrate != bHasBitrate) {
                return@sortedWith if (aHasBitrate) -1 else 1
            }

            if (aHasBitrate && bHasBitrate) {
                when (tier) {
                    "Low" -> {
                        val cmp = aBitrate.compareTo(bBitrate)
                        if (cmp != 0) return@sortedWith cmp
                    }
                    "Medium" -> {
                        val aInBand = aBitrate in 96..144
                        val bInBand = bBitrate in 96..144
                        if (aInBand != bInBand) {
                            return@sortedWith if (aInBand) -1 else 1
                        }
                        val aDist = kotlin.math.abs(aBitrate - 128)
                        val bDist = kotlin.math.abs(bBitrate - 128)
                        val distCmp = aDist.compareTo(bDist)
                        if (distCmp != 0) return@sortedWith distCmp
                        val highTie = bBitrate.compareTo(aBitrate)
                        if (highTie != 0) return@sortedWith highTie
                    }
                    else -> {
                        val cmp = bBitrate.compareTo(aBitrate)
                        if (cmp != 0) return@sortedWith cmp
                    }
                }
            }

            itagPriority(b.itag).compareTo(itagPriority(a.itag))
        }.first()
    }

    @Throws(Exception::class)
    fun resolveAudioStream(
        videoId: String,
        quality: String = "High",
        preferM4a: Boolean = false
    ): Map<String, Any?> {
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

        val normalizedQuality = normalizeQuality(quality)
        val selectedStream = selectAudioStream(validStreams, normalizedQuality, preferM4a)

        val streamUrl = selectedStream.content
        val itag = selectedStream.itag
        val bitrate = selectedStream.averageBitrate
        val formatName = selectedStream.format?.name ?: "unknown"
        val mimeType = selectedStream.format?.mimeType ?: "audio/*"
        val durationMs = streamInfo.duration * 1000L

        Log.d(TAG, "Resolved audio for $videoId (quality=$normalizedQuality): itag=$itag, bitrate=${bitrate}kbps, format=$formatName")

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
