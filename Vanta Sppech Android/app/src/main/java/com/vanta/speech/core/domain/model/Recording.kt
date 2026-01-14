package com.vanta.speech.core.domain.model

import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

data class Recording(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val createdAt: Instant = Instant.now(),
    val duration: Duration = Duration.ZERO,
    val audioFilePath: String,
    val transcriptionText: String? = null,
    val summaryText: String? = null,
    val isTranscribed: Boolean = false,
    val isUploading: Boolean = false,
    val isSummaryGenerating: Boolean = false,
    val preset: RecordingPreset? = null
) {
    val formattedDuration: String
        get() {
            val hours = duration.toHours()
            val minutes = duration.toMinutes() % 60
            val seconds = duration.seconds % 60
            return if (hours > 0) {
                String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds)
            } else {
                String.format(Locale.US, "%02d:%02d", minutes, seconds)
            }
        }

    val formattedDate: String
        get() {
            val formatter = DateTimeFormatter.ofPattern("d MMMM, HH:mm", Locale("ru"))
            return createdAt.atZone(ZoneId.systemDefault()).format(formatter)
        }

    val formattedShortDate: String
        get() {
            val formatter = DateTimeFormatter.ofPattern("d MMM", Locale("ru"))
            return createdAt.atZone(ZoneId.systemDefault()).format(formatter)
        }
}
