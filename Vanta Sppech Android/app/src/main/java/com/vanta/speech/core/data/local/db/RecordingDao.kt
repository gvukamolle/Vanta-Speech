package com.vanta.speech.core.data.local.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.vanta.speech.core.data.local.entity.RecordingEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface RecordingDao {

    @Query("SELECT * FROM recordings ORDER BY createdAt DESC")
    fun getAllRecordings(): Flow<List<RecordingEntity>>

    @Query("SELECT * FROM recordings WHERE id = :id")
    suspend fun getRecordingById(id: String): RecordingEntity?

    @Query("SELECT * FROM recordings WHERE createdAt >= :startOfDay AND createdAt < :endOfDay ORDER BY createdAt DESC")
    fun getRecordingsForDay(startOfDay: Long, endOfDay: Long): Flow<List<RecordingEntity>>

    @Query("SELECT * FROM recordings WHERE title LIKE :query OR transcriptionText LIKE :query OR summaryText LIKE :query ORDER BY createdAt DESC")
    fun searchRecordings(query: String): Flow<List<RecordingEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertRecording(recording: RecordingEntity)

    @Update
    suspend fun updateRecording(recording: RecordingEntity)

    @Delete
    suspend fun deleteRecording(recording: RecordingEntity)

    @Query("DELETE FROM recordings WHERE id = :id")
    suspend fun deleteRecordingById(id: String)

    @Query("UPDATE recordings SET isUploading = :isUploading WHERE id = :id")
    suspend fun updateUploadingStatus(id: String, isUploading: Boolean)

    @Query("UPDATE recordings SET transcriptionText = :transcription, summaryText = :summary, title = :title, isTranscribed = 1, isUploading = 0 WHERE id = :id")
    suspend fun updateTranscriptionResult(id: String, transcription: String, summary: String, title: String)
}
