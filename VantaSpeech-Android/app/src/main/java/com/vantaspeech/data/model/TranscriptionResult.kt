package com.vantaspeech.data.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class TranscriptionResult(
    @Json(name = "transcription")
    val transcription: String,

    @Json(name = "summary")
    val summary: String? = null,

    @Json(name = "language")
    val language: String? = null,

    @Json(name = "duration")
    val duration: Double? = null
)

@JsonClass(generateAdapter = true)
data class TranscriptionError(
    @Json(name = "error")
    val error: String,

    @Json(name = "code")
    val code: String? = null
)

sealed class TranscriptionState {
    data object Idle : TranscriptionState()
    data object Uploading : TranscriptionState()
    data object Processing : TranscriptionState()
    data class Success(val result: TranscriptionResult) : TranscriptionState()
    data class Error(val message: String) : TranscriptionState()
}
