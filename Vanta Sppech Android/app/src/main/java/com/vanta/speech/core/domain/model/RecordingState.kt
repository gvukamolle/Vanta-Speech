package com.vanta.speech.core.domain.model

import java.time.Duration

sealed class RecordingState {
    data object Idle : RecordingState()

    data class Recording(
        val duration: Duration,
        val audioLevel: Float,
        val preset: RecordingPreset,
        val isPaused: Boolean = false
    ) : RecordingState()

    data object Converting : RecordingState()

    data class Transcribing(val progress: Float) : RecordingState()

    data object Completed : RecordingState()

    data class Error(val message: String) : RecordingState()
}
