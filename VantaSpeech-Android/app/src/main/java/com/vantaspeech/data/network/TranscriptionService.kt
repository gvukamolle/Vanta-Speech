package com.vantaspeech.data.network

import android.content.Context
import android.net.Uri
import com.vantaspeech.data.model.TranscriptionResult
import com.vantaspeech.data.model.TranscriptionState
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import java.io.File
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TranscriptionService @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var baseUrl: String = "http://localhost:8080/"
    private var api: TranscriptionApi? = null

    fun updateServerUrl(url: String) {
        val normalizedUrl = if (url.endsWith("/")) url else "$url/"
        if (normalizedUrl != baseUrl) {
            baseUrl = normalizedUrl
            api = null // Reset API to recreate with new URL
        }
    }

    private fun getApi(): TranscriptionApi {
        if (api == null) {
            val loggingInterceptor = HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            }

            val client = OkHttpClient.Builder()
                .addInterceptor(loggingInterceptor)
                .connectTimeout(30, TimeUnit.SECONDS)
                .readTimeout(5, TimeUnit.MINUTES)
                .writeTimeout(5, TimeUnit.MINUTES)
                .build()

            api = Retrofit.Builder()
                .baseUrl(baseUrl)
                .client(client)
                .addConverterFactory(MoshiConverterFactory.create())
                .build()
                .create(TranscriptionApi::class.java)
        }
        return api!!
    }

    suspend fun transcribe(audioFilePath: String): TranscriptionState = withContext(Dispatchers.IO) {
        try {
            val file = File(audioFilePath)
            if (!file.exists()) {
                return@withContext TranscriptionState.Error("Audio file not found")
            }

            val mimeType = getMimeType(file.extension)
            val requestBody = file.asRequestBody(mimeType.toMediaTypeOrNull())
            val multipartBody = MultipartBody.Part.createFormData(
                "file",
                file.name,
                requestBody
            )

            val response = getApi().transcribe(multipartBody)

            if (response.isSuccessful) {
                response.body()?.let { result ->
                    TranscriptionState.Success(result)
                } ?: TranscriptionState.Error("Empty response from server")
            } else {
                val errorBody = response.errorBody()?.string()
                TranscriptionState.Error(errorBody ?: "Unknown error: ${response.code()}")
            }
        } catch (e: Exception) {
            TranscriptionState.Error(e.message ?: "Transcription failed")
        }
    }

    private fun getMimeType(extension: String): String {
        return when (extension.lowercase()) {
            "m4a" -> "audio/mp4"
            "ogg", "opus" -> "audio/ogg"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "aac" -> "audio/aac"
            else -> "audio/*"
        }
    }
}
