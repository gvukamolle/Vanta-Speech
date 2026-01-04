package com.vanta.speech.core.data.remote.api

import com.vanta.speech.core.data.remote.dto.ChatRequest
import com.vanta.speech.core.data.remote.dto.ChatResponse
import retrofit2.http.Body
import retrofit2.http.POST

interface ChatCompletionApi {

    @POST("chat/completions")
    suspend fun createCompletion(
        @Body request: ChatRequest
    ): ChatResponse
}
