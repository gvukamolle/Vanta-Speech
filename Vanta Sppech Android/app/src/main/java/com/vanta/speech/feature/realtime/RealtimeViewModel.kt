package com.vanta.speech.feature.realtime

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vanta.speech.core.audio.RealtimeEvent
import com.vanta.speech.core.audio.RealtimeState
import com.vanta.speech.core.audio.RealtimeTranscriptionManager
import com.vanta.speech.core.audio.VADState
import com.vanta.speech.core.audio.VoiceActivityDetector
import com.vanta.speech.core.domain.model.Recording
import com.vanta.speech.core.domain.model.RecordingPreset
import com.vanta.speech.core.domain.repository.RecordingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Duration
import java.util.UUID
import javax.inject.Inject

sealed class RealtimeUiEvent {
    data object RecordingStarted : RealtimeUiEvent()
    data object RecordingStopped : RealtimeUiEvent()
    data class ChunkTranscribed(val chunkId: Int) : RealtimeUiEvent()
    data class Error(val message: String) : RealtimeUiEvent()
    data class RecordingCompleted(val recordingId: String) : RealtimeUiEvent()
}

@HiltViewModel
class RealtimeViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val realtimeTranscriptionManager: RealtimeTranscriptionManager,
    private val voiceActivityDetector: VoiceActivityDetector,
    private val recordingRepository: RecordingRepository
) : ViewModel() {

    private val _selectedPreset = MutableStateFlow<RecordingPreset?>(null)
    val selectedPreset: StateFlow<RecordingPreset?> = _selectedPreset.asStateFlow()

    private val _uiEvents = MutableSharedFlow<RealtimeUiEvent>()
    val uiEvents: SharedFlow<RealtimeUiEvent> = _uiEvents.asSharedFlow()

    val realtimeState: StateFlow<RealtimeState> = realtimeTranscriptionManager.state

    val currentTranscription: StateFlow<String> = realtimeTranscriptionManager.currentTranscription

    val audioLevel: StateFlow<Float> = realtimeTranscriptionManager.audioLevel

    val totalDuration: StateFlow<Duration> = realtimeTranscriptionManager.totalDuration

    val vadState: StateFlow<VADState> = voiceActivityDetector.state

    val currentChunkDuration: StateFlow<Duration> = voiceActivityDetector.currentChunkDuration

    val todayRecordings: StateFlow<List<Recording>> = recordingRepository
        .getRecordingsForToday()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )

    init {
        observeRealtimeEvents()
    }

    private fun observeRealtimeEvents() {
        viewModelScope.launch {
            realtimeTranscriptionManager.events.collect { event ->
                when (event) {
                    is RealtimeEvent.ChunkTranscribed -> {
                        _uiEvents.emit(RealtimeUiEvent.ChunkTranscribed(event.chunkId))
                    }
                    is RealtimeEvent.ChunkFailed -> {
                        _uiEvents.emit(RealtimeUiEvent.Error("Ошибка транскрипции: ${event.error}"))
                    }
                    else -> { /* Ignore */ }
                }
            }
        }

        viewModelScope.launch {
            realtimeTranscriptionManager.state.collect { state ->
                when (state) {
                    is RealtimeState.Completed -> {
                        handleRecordingCompleted(state)
                    }
                    is RealtimeState.Error -> {
                        _uiEvents.emit(RealtimeUiEvent.Error(state.message))
                    }
                    else -> { /* Ignore */ }
                }
            }
        }
    }

    fun selectPreset(preset: RecordingPreset) {
        _selectedPreset.value = preset
    }

    fun startRecording() {
        val preset = _selectedPreset.value
        if (preset == null) {
            viewModelScope.launch {
                _uiEvents.emit(RealtimeUiEvent.Error("Выберите пресет"))
            }
            return
        }

        if (!hasAudioPermission()) {
            viewModelScope.launch {
                _uiEvents.emit(RealtimeUiEvent.Error("Нет разрешения на запись"))
            }
            return
        }

        realtimeTranscriptionManager.startRecording()

        viewModelScope.launch {
            _uiEvents.emit(RealtimeUiEvent.RecordingStarted)
        }
    }

    fun stopRecording() {
        realtimeTranscriptionManager.stopRecording()

        viewModelScope.launch {
            _uiEvents.emit(RealtimeUiEvent.RecordingStopped)
        }
    }

    fun cancelRecording() {
        realtimeTranscriptionManager.cancelRecording()
    }

    fun forceChunkSplit() {
        voiceActivityDetector.forceChunkSplit()
    }

    private suspend fun handleRecordingCompleted(state: RealtimeState.Completed) {
        val preset = _selectedPreset.value ?: RecordingPreset.PROJECT_MEETING

        val recording = Recording(
            id = UUID.randomUUID().toString(),
            title = "Real-time запись",
            duration = totalDuration.value,
            audioFilePath = state.filePath,
            preset = preset,
            transcriptionText = state.fullTranscription,
            isTranscribed = true
        )

        recordingRepository.saveRecording(recording)

        _uiEvents.emit(RealtimeUiEvent.RecordingCompleted(recording.id))
    }

    private fun hasAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    override fun onCleared() {
        super.onCleared()
        // Cancel any ongoing recording
        if (realtimeState.value is RealtimeState.Recording) {
            realtimeTranscriptionManager.cancelRecording()
        }
    }
}
