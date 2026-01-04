package com.vanta.speech.core.data.remote.dto

import com.google.gson.annotations.SerializedName

data class ChatRequest(
    val model: String,
    val messages: List<ChatMessage>,
    val temperature: Double = 0.3,
    @SerializedName("max_tokens")
    val maxTokens: Int = 2000
)

data class ChatMessage(
    val role: String,
    val content: String
)

data class ChatResponse(
    val choices: List<Choice>
) {
    data class Choice(
        val message: Message
    ) {
        data class Message(
            val content: String
        )
    }

    val text: String?
        get() = choices.firstOrNull()?.message?.content
}
