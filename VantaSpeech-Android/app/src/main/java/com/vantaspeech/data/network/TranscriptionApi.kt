package com.vantaspeech.data.network

import com.vantaspeech.data.model.TranscriptionResult
import okhttp3.MultipartBody
import retrofit2.Response
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part

interface TranscriptionApi {
    @Multipart
    @POST("transcribe")
    suspend fun transcribe(
        @Part file: MultipartBody.Part
    ): Response<TranscriptionResult>
}
