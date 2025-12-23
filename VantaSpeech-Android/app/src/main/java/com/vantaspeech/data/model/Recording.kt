package com.vantaspeech.data.model

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

@Entity(tableName = "recordings")
data class Recording(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val createdAt: Long = System.currentTimeMillis(),
    val duration: Long = 0, // Duration in seconds
    val audioFilePath: String,
    val transcriptionText: String? = null,
    val summaryText: String? = null,
    val isTranscribed: Boolean = false,
    val isUploading: Boolean = false
) {
    val formattedDuration: String
        get() {
            val durationSeconds = duration.seconds
            val hours = durationSeconds.inWholeHours
            val minutes = (durationSeconds.inWholeMinutes % 60)
            val seconds = (durationSeconds.inWholeSeconds % 60)

            return if (hours > 0) {
                String.format("%d:%02d:%02d", hours, minutes, seconds)
            } else {
                String.format("%d:%02d", minutes, seconds)
            }
        }

    val formattedDate: String
        get() {
            val instant = Instant.ofEpochMilli(createdAt)
            val localDateTime = LocalDateTime.ofInstant(instant, ZoneId.systemDefault())
            val now = LocalDateTime.now()

            return when {
                localDateTime.toLocalDate() == now.toLocalDate() -> {
                    "Today, ${localDateTime.format(DateTimeFormatter.ofPattern("HH:mm"))}"
                }
                localDateTime.toLocalDate() == now.minusDays(1).toLocalDate() -> {
                    "Yesterday, ${localDateTime.format(DateTimeFormatter.ofPattern("HH:mm"))}"
                }
                else -> {
                    localDateTime.format(DateTimeFormatter.ofPattern("MMM d, yyyy"))
                }
            }
        }

    val transcriptionPreview: String?
        get() = transcriptionText?.take(150)?.let {
            if (transcriptionText.length > 150) "$it..." else it
        }
}

enum class AudioQuality(val bitrate: Int, val label: String) {
    LOW(64, "Low (64 kbps)"),
    MEDIUM(96, "Medium (96 kbps)"),
    HIGH(128, "High (128 kbps)")
}
