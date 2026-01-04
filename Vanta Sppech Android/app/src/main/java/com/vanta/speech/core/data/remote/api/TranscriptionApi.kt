package com.vanta.speech.core.data.remote.api

import com.vanta.speech.core.data.remote.dto.WhisperResponse
import okhttp3.MultipartBody
import okhttp3.RequestBody
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part

interface TranscriptionApi {

    @Multipart
    @POST("audio/transcriptions")
    suspend fun transcribe(
        @Part file: MultipartBody.Part,
        @Part("model") model: RequestBody,
        @Part("language") language: RequestBody
    ): WhisperResponse
}
