package com.vantaspeech.data.repository

import com.vantaspeech.data.model.Recording
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RecordingRepository @Inject constructor(
    private val recordingDao: RecordingDao
) {
    fun getAllRecordings(): Flow<List<Recording>> = recordingDao.getAllRecordings()

    suspend fun getRecordingById(id: String): Recording? = recordingDao.getRecordingById(id)

    fun getRecordingByIdFlow(id: String): Flow<Recording?> = recordingDao.getRecordingByIdFlow(id)

    fun searchRecordings(query: String): Flow<List<Recording>> = recordingDao.searchRecordings(query)

    suspend fun getMostRecentRecording(): Recording? = recordingDao.getMostRecentRecording()

    fun getMostRecentRecordingFlow(): Flow<Recording?> = recordingDao.getMostRecentRecordingFlow()

    suspend fun insertRecording(recording: Recording) = recordingDao.insertRecording(recording)

    suspend fun updateRecording(recording: Recording) = recordingDao.updateRecording(recording)

    suspend fun deleteRecording(recording: Recording) = recordingDao.deleteRecording(recording)

    suspend fun deleteRecordingById(id: String) = recordingDao.deleteRecordingById(id)

    suspend fun deleteAllRecordings() = recordingDao.deleteAllRecordings()

    suspend fun updateUploadingStatus(id: String, isUploading: Boolean) =
        recordingDao.updateUploadingStatus(id, isUploading)

    suspend fun updateTranscription(id: String, transcription: String, summary: String?) =
        recordingDao.updateTranscription(id, transcription, summary)
}
