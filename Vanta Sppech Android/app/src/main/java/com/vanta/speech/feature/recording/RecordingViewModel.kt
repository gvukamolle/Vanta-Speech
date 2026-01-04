package com.vanta.speech.feature.recording

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.IBinder
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vanta.speech.core.audio.AudioImporter
import com.vanta.speech.core.domain.model.Recording
import com.vanta.speech.core.domain.model.RecordingPreset
import com.vanta.speech.core.domain.model.RecordingState
import com.vanta.speech.core.domain.repository.RecordingRepository
import com.vanta.speech.service.RecordingService
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Duration
import java.util.UUID
import javax.inject.Inject

@HiltViewModel
class RecordingViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val recordingRepository: RecordingRepository,
    private val audioImporter: AudioImporter
) : ViewModel() {

    private var recordingService: RecordingService? = null
    private var isBound = false

    private val _recordingState = MutableStateFlow<RecordingState>(RecordingState.Idle)
    val recordingState: StateFlow<RecordingState> = _recordingState.asStateFlow()

    private val _selectedPreset = MutableStateFlow<RecordingPreset?>(null)
    val selectedPreset: StateFlow<RecordingPreset?> = _selectedPreset.asStateFlow()

    private val _duration = MutableStateFlow(Duration.ZERO)
    val duration: StateFlow<Duration> = _duration.asStateFlow()

    private val _audioLevel = MutableStateFlow(0f)
    val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    // Import state
    private val _isImporting = MutableStateFlow(false)
    val isImporting: StateFlow<Boolean> = _isImporting.asStateFlow()

    private val _importError = MutableStateFlow<String?>(null)
    val importError: StateFlow<String?> = _importError.asStateFlow()

    private val _importedAudioData = MutableStateFlow<AudioImporter.ImportedAudio?>(null)
    val importedAudioData: StateFlow<AudioImporter.ImportedAudio?> = _importedAudioData.asStateFlow()

    val todayRecordings: StateFlow<List<Recording>> = recordingRepository
        .getRecordingsForToday()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as? RecordingService.RecordingBinder
            recordingService = binder?.getService()
            isBound = true

            // Observe service state
            recordingService?.let { svc ->
                viewModelScope.launch {
                    svc.recordingState.collect { state ->
                        _recordingState.value = state
                        if (state is RecordingState.Recording) {
                            _selectedPreset.value = state.preset
                        }
                    }
                }
                viewModelScope.launch {
                    svc.duration.collect { _duration.value = it }
                }
                viewModelScope.launch {
                    svc.audioLevel.collect { _audioLevel.value = it }
                }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            recordingService = null
            isBound = false
        }
    }

    init {
        bindToService()
    }

    private fun bindToService() {
        val intent = Intent(context, RecordingService::class.java)
        context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
    }

    fun selectPreset(preset: RecordingPreset) {
        _selectedPreset.value = preset
    }

    fun startRecording() {
        val preset = _selectedPreset.value ?: return

        val intent = Intent(context, RecordingService::class.java).apply {
            action = RecordingService.ACTION_START
            putExtra(RecordingService.EXTRA_PRESET_ID, preset.id)
        }
        context.startForegroundService(intent)

        // Bind to get updates
        if (!isBound) {
            bindToService()
        }
    }

    fun pauseRecording() {
        val intent = Intent(context, RecordingService::class.java).apply {
            action = RecordingService.ACTION_PAUSE
        }
        context.startService(intent)
    }

    fun resumeRecording() {
        val intent = Intent(context, RecordingService::class.java).apply {
            action = RecordingService.ACTION_RESUME
        }
        context.startService(intent)
    }

    fun stopRecording() {
        viewModelScope.launch {
            val filePath = recordingService?.getRecordingFilePath()
            val preset = recordingService?.getCurrentPreset()
            val currentDuration = _duration.value

            // Stop the service
            val intent = Intent(context, RecordingService::class.java).apply {
                action = RecordingService.ACTION_STOP
            }
            context.startService(intent)

            // Save recording to database
            if (filePath != null && preset != null) {
                val recording = Recording(
                    id = UUID.randomUUID().toString(),
                    title = "Новая запись",
                    duration = currentDuration,
                    audioFilePath = filePath,
                    preset = preset
                )
                recordingRepository.saveRecording(recording)
            }

            _recordingState.value = RecordingState.Idle
            _duration.value = Duration.ZERO
            _audioLevel.value = 0f
        }
    }

    fun toggleRecording() {
        when (val state = _recordingState.value) {
            is RecordingState.Recording -> {
                if (state.isPaused) {
                    resumeRecording()
                } else {
                    pauseRecording()
                }
            }
            is RecordingState.Idle -> {
                if (_selectedPreset.value != null) {
                    startRecording()
                }
            }
            else -> { /* Ignore during other states */ }
        }
    }

    override fun onCleared() {
        super.onCleared()
        if (isBound) {
            context.unbindService(serviceConnection)
            isBound = false
        }
    }

    // MARK: - Import Functions

    /**
     * Import audio file from URI
     */
    fun importAudio(uri: Uri) {
        _isImporting.value = true
        _importError.value = null

        viewModelScope.launch {
            try {
                val importedAudio = audioImporter.importAudio(uri)
                _importedAudioData.value = importedAudio
            } catch (e: AudioImporter.ImportError) {
                _importError.value = e.message
            } catch (e: Exception) {
                _importError.value = e.message ?: "Ошибка импорта"
            } finally {
                _isImporting.value = false
            }
        }
    }

    /**
     * Complete import by creating a recording with selected preset
     */
    fun finalizeImport(preset: RecordingPreset) {
        val audioData = _importedAudioData.value ?: return

        viewModelScope.launch {
            val recording = Recording(
                id = UUID.randomUUID().toString(),
                title = "${preset.displayName} - ${audioData.originalFileName}",
                duration = audioData.duration,
                audioFilePath = audioData.filePath,
                preset = preset
            )
            recordingRepository.saveRecording(recording)
            _importedAudioData.value = null
        }
    }

    /**
     * Cancel import and cleanup
     */
    fun cancelImport() {
        _importedAudioData.value?.let { audioData ->
            audioImporter.deleteImportedFile(audioData.filePath)
        }
        _importedAudioData.value = null
    }

    /**
     * Clear import error
     */
    fun clearImportError() {
        _importError.value = null
    }
}
