package com.vanta.speech.core.data.repository

import com.vanta.speech.core.data.local.db.RecordingDao
import com.vanta.speech.core.data.local.entity.RecordingEntity
import com.vanta.speech.core.domain.model.Recording
import com.vanta.speech.core.domain.model.RecordingPreset
import com.vanta.speech.core.domain.repository.RecordingRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RecordingRepositoryImpl @Inject constructor(
    private val recordingDao: RecordingDao
) : RecordingRepository {

    override fun getAllRecordings(): Flow<List<Recording>> =
        recordingDao.getAllRecordings().map { entities ->
            entities.map { it.toDomain() }
        }

    override fun getRecordingsForToday(): Flow<List<Recording>> {
        val today = LocalDate.now()
        val startOfDay = today.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val endOfDay = today.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        return recordingDao.getRecordingsForDay(startOfDay, endOfDay).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override fun searchRecordings(query: String): Flow<List<Recording>> =
        recordingDao.searchRecordings("%$query%").map { entities ->
            entities.map { it.toDomain() }
        }

    override suspend fun getRecordingById(id: String): Recording? =
        recordingDao.getRecordingById(id)?.toDomain()

    override suspend fun saveRecording(recording: Recording) {
        recordingDao.insertRecording(recording.toEntity())
    }

    override suspend fun updateRecording(recording: Recording) {
        recordingDao.updateRecording(recording.toEntity())
    }

    override suspend fun deleteRecording(id: String) {
        recordingDao.deleteRecordingById(id)
    }

    override suspend fun updateTranscriptionResult(
        id: String,
        transcription: String,
        summary: String,
        title: String
    ) {
        recordingDao.updateTranscriptionResult(id, transcription, summary, title)
    }

    private fun RecordingEntity.toDomain(): Recording = Recording(
        id = id,
        title = title,
        createdAt = Instant.ofEpochMilli(createdAt),
        duration = Duration.ofSeconds(duration),
        audioFilePath = audioFilePath,
        transcriptionText = transcriptionText,
        summaryText = summaryText,
        isTranscribed = isTranscribed,
        isUploading = isUploading,
        preset = RecordingPreset.fromId(presetId)
    )

    private fun Recording.toEntity(): RecordingEntity = RecordingEntity(
        id = id,
        title = title,
        createdAt = createdAt.toEpochMilli(),
        duration = duration.seconds,
        audioFilePath = audioFilePath,
        transcriptionText = transcriptionText,
        summaryText = summaryText,
        isTranscribed = isTranscribed,
        isUploading = isUploading,
        presetId = preset?.id
    )
}
