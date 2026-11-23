package com.melody.music

import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.io.IOException
import java.util.concurrent.TimeUnit

class NewPipeDownloader private constructor(
    private val client: OkHttpClient
) : Downloader() {

    companion object {
        const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0"

        @Volatile
        private var instance: NewPipeDownloader? = null

        fun getInstance(): NewPipeDownloader {
            return instance ?: synchronized(this) {
                instance ?: NewPipeDownloader(
                    OkHttpClient.Builder()
                        .connectTimeout(10, TimeUnit.SECONDS)
                        .readTimeout(15, TimeUnit.SECONDS)
                        .build()
                ).also { instance = it }
            }
        }
    }

    @Throws(IOException::class, ReCaptchaException::class)
    override fun execute(request: Request): Response {
        val httpMethod = request.httpMethod()
        val url = request.url()
        val headers = request.headers()
        val dataToSend = request.dataToSend()

        val builder = okhttp3.Request.Builder()
            .url(url)
            .header("User-Agent", USER_AGENT)

        for ((key, values) in headers) {
            builder.removeHeader(key)
            for (value in values) {
                builder.addHeader(key, value)
            }
        }

        val requestBody = if (dataToSend != null) {
            val contentType = headers["Content-Type"]?.firstOrNull() ?: "application/json"
            dataToSend.toRequestBody(contentType.toMediaTypeOrNull())
        } else null

        when (httpMethod.uppercase()) {
            "POST" -> builder.post(requestBody ?: ByteArray(0).toRequestBody(null))
            "HEAD" -> builder.head()
            else -> builder.get()
        }

        val okHttpResponse = client.newCall(builder.build()).execute()
        val responseCode = okHttpResponse.code

        if (responseCode == 429) {
            okHttpResponse.close()
            throw ReCaptchaException("reCaptcha Challenge requested", url)
        }

        val responseBodyString = okHttpResponse.body?.string() ?: ""
        val responseHeaders = okHttpResponse.headers.toMultimap()
        val latestUrl = okHttpResponse.request.url.toString()

        return Response(responseCode, okHttpResponse.message, responseHeaders, responseBodyString, latestUrl)
    }
}
