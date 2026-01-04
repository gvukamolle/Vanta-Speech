package com.vanta.speech.core.domain.repository

import com.vanta.speech.core.domain.model.RecordingPreset

interface TranscriptionRepository {
    suspend fun transcribeAudio(audioFilePath: String): String
    suspend fun generateSummary(transcription: String, preset: RecordingPreset?): String
    suspend fun generateTitle(summary: String): String
}
