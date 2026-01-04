package com.vanta.speech.core.data.repository

import com.vanta.speech.core.data.remote.api.ChatCompletionApi
import com.vanta.speech.core.data.remote.api.TranscriptionApi
import com.vanta.speech.core.data.remote.dto.ChatMessage
import com.vanta.speech.core.data.remote.dto.ChatRequest
import com.vanta.speech.core.domain.model.RecordingPreset
import com.vanta.speech.core.domain.repository.TranscriptionRepository
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TranscriptionRepositoryImpl @Inject constructor(
    private val transcriptionApi: TranscriptionApi,
    private val chatCompletionApi: ChatCompletionApi
) : TranscriptionRepository {

    companion object {
        private const val MODEL_TRANSCRIPTION = "gigaam-v3"
        private const val MODEL_SUMMARY = "cod/gpt-oss:120b"
        private const val LANGUAGE = "ru"
        private const val DEFAULT_SUMMARY_PROMPT = """
            Обработай транскрипцию:
            - Очисти от слов-паразитов
            - Структурируй информацию
            - Выдели ключевые моменты
            - Извлеки задачи (если есть)

            Формат: краткий структурированный markdown.
        """
    }

    override suspend fun transcribeAudio(audioFilePath: String): String {
        val file = File(audioFilePath)
        val requestFile = file.asRequestBody("audio/m4a".toMediaTypeOrNull())
        val filePart = MultipartBody.Part.createFormData("file", file.name, requestFile)
        val modelPart = MODEL_TRANSCRIPTION.toRequestBody("text/plain".toMediaTypeOrNull())
        val languagePart = LANGUAGE.toRequestBody("text/plain".toMediaTypeOrNull())

        val response = transcriptionApi.transcribe(filePart, modelPart, languagePart)
        return response.text
    }

    override suspend fun generateSummary(transcription: String, preset: RecordingPreset?): String {
        val systemPrompt = preset?.systemPrompt ?: DEFAULT_SUMMARY_PROMPT.trimIndent()
        val request = ChatRequest(
            model = MODEL_SUMMARY,
            messages = listOf(
                ChatMessage(role = "system", content = systemPrompt),
                ChatMessage(role = "user", content = transcription)
            ),
            temperature = 0.3,
            maxTokens = 2000
        )

        val response = chatCompletionApi.createCompletion(request)
        return response.text ?: ""
    }

    override suspend fun generateTitle(summary: String): String {
        val request = ChatRequest(
            model = MODEL_SUMMARY,
            messages = listOf(
                ChatMessage(
                    role = "system",
                    content = "Сгенерируй короткий заголовок (5-7 слов) для следующего саммари. Отвечай только заголовком, без кавычек."
                ),
                ChatMessage(role = "user", content = summary)
            ),
            temperature = 0.3,
            maxTokens = 50
        )

        val response = chatCompletionApi.createCompletion(request)
        return response.text?.trim() ?: "Запись"
    }
}
