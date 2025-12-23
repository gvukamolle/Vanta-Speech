package com.vantaspeech.data.repository

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.vantaspeech.data.model.Recording
import kotlinx.coroutines.flow.Flow

@Dao
interface RecordingDao {
    @Query("SELECT * FROM recordings ORDER BY createdAt DESC")
    fun getAllRecordings(): Flow<List<Recording>>

    @Query("SELECT * FROM recordings WHERE id = :id")
    suspend fun getRecordingById(id: String): Recording?

    @Query("SELECT * FROM recordings WHERE id = :id")
    fun getRecordingByIdFlow(id: String): Flow<Recording?>

    @Query("""
        SELECT * FROM recordings
        WHERE title LIKE '%' || :query || '%'
           OR transcriptionText LIKE '%' || :query || '%'
        ORDER BY createdAt DESC
    """)
    fun searchRecordings(query: String): Flow<List<Recording>>

    @Query("SELECT * FROM recordings ORDER BY createdAt DESC LIMIT 1")
    suspend fun getMostRecentRecording(): Recording?

    @Query("SELECT * FROM recordings ORDER BY createdAt DESC LIMIT 1")
    fun getMostRecentRecordingFlow(): Flow<Recording?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertRecording(recording: Recording)

    @Update
    suspend fun updateRecording(recording: Recording)

    @Delete
    suspend fun deleteRecording(recording: Recording)

    @Query("DELETE FROM recordings WHERE id = :id")
    suspend fun deleteRecordingById(id: String)

    @Query("DELETE FROM recordings")
    suspend fun deleteAllRecordings()

    @Query("UPDATE recordings SET isUploading = :isUploading WHERE id = :id")
    suspend fun updateUploadingStatus(id: String, isUploading: Boolean)

    @Query("""
        UPDATE recordings
        SET transcriptionText = :transcription,
            summaryText = :summary,
            isTranscribed = 1,
            isUploading = 0
        WHERE id = :id
    """)
    suspend fun updateTranscription(id: String, transcription: String, summary: String?)
}
