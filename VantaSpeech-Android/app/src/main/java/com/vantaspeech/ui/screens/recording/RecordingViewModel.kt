package com.vantaspeech.ui.screens.recording

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.vantaspeech.audio.AudioRecorder
import com.vantaspeech.audio.RecordingService
import com.vantaspeech.audio.RecordingState
import com.vantaspeech.data.model.Recording
import com.vantaspeech.data.repository.RecordingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class RecordingViewModel @Inject constructor(
    private val application: Application,
    private val audioRecorder: AudioRecorder,
    private val recordingRepository: RecordingRepository
) : AndroidViewModel(application) {

    val recordingState: StateFlow<RecordingState> = audioRecorder.state
    val duration: StateFlow<Long> = audioRecorder.duration
    val audioLevel: StateFlow<Float> = audioRecorder.audioLevel

    private val _hasPermission = MutableStateFlow(audioRecorder.hasRecordPermission)
    val hasPermission: StateFlow<Boolean> = _hasPermission.asStateFlow()

    private var currentRecordingPath: String? = null

    fun updatePermissionStatus() {
        _hasPermission.value = audioRecorder.hasRecordPermission
    }

    fun toggleRecording() {
        when (recordingState.value) {
            RecordingState.IDLE -> startRecording()
            RecordingState.RECORDING, RecordingState.PAUSED -> stopRecording()
            RecordingState.STOPPED -> startRecording()
        }
    }

    private fun startRecording() {
        val intent = Intent(application, RecordingService::class.java).apply {
            action = RecordingService.ACTION_START_RECORDING
        }
        application.startForegroundService(intent)

        currentRecordingPath = audioRecorder.startRecording()
    }

    fun stopRecording() {
        val result = audioRecorder.stopRecording()

        val intent = Intent(application, RecordingService::class.java).apply {
            action = RecordingService.ACTION_STOP_RECORDING
        }
        application.startService(intent)

        result?.let { (filePath, duration) ->
            saveRecording(filePath, duration)
        }
    }

    fun togglePause() {
        when (recordingState.value) {
            RecordingState.RECORDING -> {
                audioRecorder.pauseRecording()
                val intent = Intent(application, RecordingService::class.java).apply {
                    action = RecordingService.ACTION_PAUSE_RECORDING
                }
                application.startService(intent)
            }
            RecordingState.PAUSED -> {
                audioRecorder.resumeRecording()
                val intent = Intent(application, RecordingService::class.java).apply {
                    action = RecordingService.ACTION_RESUME_RECORDING
                }
                application.startService(intent)
            }
            else -> {}
        }
    }

    private fun saveRecording(filePath: String, duration: Long) {
        viewModelScope.launch {
            val dateFormat = SimpleDateFormat("MMM d, yyyy HH:mm", Locale.getDefault())
            val title = "Recording ${dateFormat.format(Date())}"

            val recording = Recording(
                title = title,
                duration = duration,
                audioFilePath = filePath
            )

            recordingRepository.insertRecording(recording)
        }
    }
}
