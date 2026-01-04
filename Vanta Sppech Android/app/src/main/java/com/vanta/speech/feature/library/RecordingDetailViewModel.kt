package com.vanta.speech.feature.library

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vanta.speech.core.audio.AudioMerger
import com.vanta.speech.core.audio.AudioPlayer
import com.vanta.speech.core.audio.PlaybackState
import com.vanta.speech.core.domain.model.Recording
import com.vanta.speech.core.domain.repository.RecordingRepository
import com.vanta.speech.core.domain.repository.TranscriptionRepository
import com.vanta.speech.service.RecordingService
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Duration
import javax.inject.Inject

sealed class TranscriptionState {
    data object Idle : TranscriptionState()
    data class Transcribing(val progress: Float) : TranscriptionState()
    data object GeneratingSummary : TranscriptionState()
    data object Completed : TranscriptionState()
    data class Error(val message: String) : TranscriptionState()
}

sealed class ContinuationState {
    data object Idle : ContinuationState()
    data object Recording : ContinuationState()
    data object Merging : ContinuationState()
    data class Error(val message: String) : ContinuationState()
}

@HiltViewModel
class RecordingDetailViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    savedStateHandle: SavedStateHandle,
    private val recordingRepository: RecordingRepository,
    private val transcriptionRepository: TranscriptionRepository,
    private val audioPlayer: AudioPlayer,
    private val audioMerger: AudioMerger
) : ViewModel() {

    private val recordingId: String = savedStateHandle["recordingId"] ?: ""

    private val _recording = MutableStateFlow<Recording?>(null)
    val recording: StateFlow<Recording?> = _recording.asStateFlow()

    private val _transcriptionState = MutableStateFlow<TranscriptionState>(TranscriptionState.Idle)
    val transcriptionState: StateFlow<TranscriptionState> = _transcriptionState.asStateFlow()

    private val _continuationState = MutableStateFlow<ContinuationState>(ContinuationState.Idle)
    val continuationState: StateFlow<ContinuationState> = _continuationState.asStateFlow()

    val playbackState: StateFlow<PlaybackState> = audioPlayer.playbackState
    val currentPosition: StateFlow<Duration> = audioPlayer.currentPosition
    val totalDuration: StateFlow<Duration> = audioPlayer.totalDuration
    val isPlaying: StateFlow<Boolean> = audioPlayer.isPlaying
    val playbackSpeed: StateFlow<Float> = audioPlayer.playbackSpeed

    private val continuationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.vanta.speech.CONTINUATION_COMPLETED") {
                val origRecordingId = intent.getStringExtra("original_recording_id") ?: return
                if (origRecordingId == recordingId) {
                    val newFilePath = intent.getStringExtra("file_path") ?: return
                    val origFilePath = intent.getStringExtra("original_file_path") ?: return
                    handleContinuationCompleted(origFilePath, newFilePath)
                }
            }
        }
    }

    init {
        loadRecording()
        registerContinuationReceiver()
    }

    private fun registerContinuationReceiver() {
        val filter = IntentFilter("com.vanta.speech.CONTINUATION_COMPLETED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(continuationReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(continuationReceiver, filter)
        }
    }

    private fun loadRecording() {
        viewModelScope.launch {
            val rec = recordingRepository.getRecordingById(recordingId)
            _recording.value = rec

            // Load audio for playback
            rec?.audioFilePath?.let { path ->
                audioPlayer.load(path)
            }
        }
    }

    fun togglePlayPause() {
        audioPlayer.togglePlayPause()
    }

    fun seekTo(position: Duration) {
        audioPlayer.seekTo(position)
    }

    fun seekForward() {
        audioPlayer.seekForward(10)
    }

    fun seekBackward() {
        audioPlayer.seekBackward(10)
    }

    fun setPlaybackSpeed(speed: Float) {
        audioPlayer.setPlaybackSpeed(speed)
    }

    fun transcribeRecording() {
        val rec = _recording.value ?: return
        if (rec.isTranscribed) return

        viewModelScope.launch {
            _transcriptionState.value = TranscriptionState.Transcribing(0f)

            try {
                // Update uploading status
                recordingRepository.updateRecording(rec.copy(isUploading = true))

                // Transcribe
                _transcriptionState.value = TranscriptionState.Transcribing(0.3f)
                val transcription = transcriptionRepository.transcribeAudio(rec.audioFilePath)

                // Generate summary
                _transcriptionState.value = TranscriptionState.GeneratingSummary
                val summary = transcriptionRepository.generateSummary(
                    transcription = transcription,
                    preset = rec.preset
                )

                // Generate title
                val title = transcriptionRepository.generateTitle(transcription)

                // Update recording
                recordingRepository.updateTranscriptionResult(
                    id = rec.id,
                    transcription = transcription,
                    summary = summary,
                    title = title
                )

                // Reload recording
                loadRecording()

                _transcriptionState.value = TranscriptionState.Completed

            } catch (e: Exception) {
                _transcriptionState.value = TranscriptionState.Error(e.message ?: "Ошибка транскрипции")

                // Reset uploading status
                recordingRepository.updateRecording(rec.copy(isUploading = false))
            }
        }
    }

    fun deleteRecording(onDeleted: () -> Unit) {
        viewModelScope.launch {
            audioPlayer.stop()
            recordingRepository.deleteRecording(recordingId)
            onDeleted()
        }
    }

    /**
     * Start continuation recording for this recording
     * This will clear transcription and summary, start a new recording,
     * and merge the audio files when stopped
     */
    fun startContinuationRecording() {
        val rec = _recording.value ?: return

        viewModelScope.launch {
            // Stop current playback
            audioPlayer.stop()

            // Clear transcription and summary from the recording
            recordingRepository.updateRecording(
                rec.copy(
                    transcriptionText = null,
                    summaryText = null,
                    isTranscribed = false
                )
            )

            // Reload to get updated recording
            val updatedRec = recordingRepository.getRecordingById(recordingId) ?: return@launch
            _recording.value = updatedRec

            // Set continuation state
            _continuationState.value = ContinuationState.Recording

            // Start the recording service in continuation mode
            val intent = Intent(context, RecordingService::class.java).apply {
                action = RecordingService.ACTION_CONTINUE
                putExtra(RecordingService.EXTRA_PRESET_ID, rec.preset?.id)
                putExtra(RecordingService.EXTRA_ORIGINAL_RECORDING_ID, rec.id)
                putExtra(RecordingService.EXTRA_ORIGINAL_FILE_PATH, rec.audioFilePath)
                putExtra(RecordingService.EXTRA_ORIGINAL_DURATION, rec.duration.seconds)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private fun handleContinuationCompleted(originalFilePath: String, newFilePath: String) {
        viewModelScope.launch {
            _continuationState.value = ContinuationState.Merging

            val mergeResult = audioMerger.mergeAudioFiles(
                firstFilePath = originalFilePath,
                secondFilePath = newFilePath,
                deleteSecondFile = true
            )

            mergeResult.onSuccess { result ->
                // Update the recording with new duration
                val rec = _recording.value ?: return@onSuccess
                recordingRepository.updateRecording(
                    rec.copy(
                        duration = result.duration,
                        audioFilePath = result.filePath
                    )
                )

                // Reload the recording
                loadRecording()
                _continuationState.value = ContinuationState.Idle

            }.onFailure { error ->
                _continuationState.value = ContinuationState.Error(
                    error.message ?: "Ошибка при склейке аудио"
                )
            }
        }
    }

    fun clearContinuationError() {
        _continuationState.value = ContinuationState.Idle
    }

    override fun onCleared() {
        super.onCleared()
        audioPlayer.stop()
        try {
            context.unregisterReceiver(continuationReceiver)
        } catch (e: Exception) {
            // Receiver may not have been registered
        }
    }
}
