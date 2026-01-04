package com.vanta.speech.core.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "recordings")
data class RecordingEntity(
    @PrimaryKey
    val id: String,
    val title: String,
    val createdAt: Long,  // Epoch millis
    val duration: Long,   // Duration in seconds
    val audioFilePath: String,
    val transcriptionText: String? = null,
    val summaryText: String? = null,
    val isTranscribed: Boolean = false,
    val isUploading: Boolean = false,
    val presetId: String? = null
)
