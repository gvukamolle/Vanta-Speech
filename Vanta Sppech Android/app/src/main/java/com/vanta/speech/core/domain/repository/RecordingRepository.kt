package com.vanta.speech.core.domain.repository

import com.vanta.speech.core.domain.model.Recording
import kotlinx.coroutines.flow.Flow

interface RecordingRepository {
    fun getAllRecordings(): Flow<List<Recording>>
    fun getRecordingsForToday(): Flow<List<Recording>>
    fun searchRecordings(query: String): Flow<List<Recording>>
    suspend fun getRecordingById(id: String): Recording?
    suspend fun saveRecording(recording: Recording)
    suspend fun updateRecording(recording: Recording)
    suspend fun deleteRecording(id: String)
    suspend fun updateTranscriptionResult(
        id: String,
        transcription: String,
        summary: String,
        title: String
    )
}
