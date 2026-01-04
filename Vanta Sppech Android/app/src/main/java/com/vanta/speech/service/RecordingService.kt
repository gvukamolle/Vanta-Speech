package com.vanta.speech.service

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import com.vanta.speech.core.audio.AudioRecorder
import com.vanta.speech.core.domain.model.RecordingPreset
import com.vanta.speech.core.domain.model.RecordingState
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import javax.inject.Inject

@AndroidEntryPoint
class RecordingService : Service() {

    companion object {
        const val ACTION_START = "com.vanta.speech.action.START"
        const val ACTION_CONTINUE = "com.vanta.speech.action.CONTINUE"
        const val ACTION_PAUSE = "com.vanta.speech.action.PAUSE"
        const val ACTION_RESUME = "com.vanta.speech.action.RESUME"
        const val ACTION_STOP = "com.vanta.speech.action.STOP"
        const val EXTRA_PRESET_ID = "preset_id"
        const val EXTRA_ORIGINAL_RECORDING_ID = "original_recording_id"
        const val EXTRA_ORIGINAL_FILE_PATH = "original_file_path"
        const val EXTRA_ORIGINAL_DURATION = "original_duration"

        private const val UPDATE_INTERVAL_MS = 100L
    }

    @Inject
    lateinit var audioRecorder: AudioRecorder

    @Inject
    lateinit var notificationManager: RecordingNotificationManager

    private val binder = RecordingBinder()
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var metricsJob: Job? = null
    private var startTime: Instant? = null
    private var pausedTime: Instant? = null
    private var totalPausedDuration: Duration = Duration.ZERO
    private var currentPreset: RecordingPreset = RecordingPreset.PROJECT_MEETING
    private var currentRecordingId: String? = null

    // Continuation mode state
    private var isContinuationMode = false
    private var originalRecordingId: String? = null
    private var originalFilePath: String? = null
    private var originalDuration: Duration = Duration.ZERO

    private val _recordingState = MutableStateFlow<RecordingState>(RecordingState.Idle)
    val recordingState: StateFlow<RecordingState> = _recordingState.asStateFlow()

    private val _duration = MutableStateFlow(Duration.ZERO)
    val duration: StateFlow<Duration> = _duration.asStateFlow()

    private val _audioLevel = MutableStateFlow(0f)
    val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    inner class RecordingBinder : Binder() {
        fun getService(): RecordingService = this@RecordingService
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val presetId = intent.getStringExtra(EXTRA_PRESET_ID)
                val preset = RecordingPreset.fromId(presetId) ?: RecordingPreset.PROJECT_MEETING
                startRecording(preset)
            }
            ACTION_CONTINUE -> {
                val presetId = intent.getStringExtra(EXTRA_PRESET_ID)
                val preset = RecordingPreset.fromId(presetId) ?: RecordingPreset.PROJECT_MEETING
                val origRecordingId = intent.getStringExtra(EXTRA_ORIGINAL_RECORDING_ID) ?: ""
                val origFilePath = intent.getStringExtra(EXTRA_ORIGINAL_FILE_PATH) ?: ""
                val origDurationSec = intent.getLongExtra(EXTRA_ORIGINAL_DURATION, 0L)
                startContinuationRecording(preset, origRecordingId, origFilePath, Duration.ofSeconds(origDurationSec))
            }
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_STOP -> stopRecording()
        }
        return START_STICKY
    }

    private fun startRecording(preset: RecordingPreset) {
        if (_recordingState.value is RecordingState.Recording) return

        currentPreset = preset
        isContinuationMode = false
        originalRecordingId = null
        originalFilePath = null
        originalDuration = Duration.ZERO

        audioRecorder.startRecording()
            .onSuccess { filePath ->
                currentRecordingId = filePath
                startTime = Instant.now()
                totalPausedDuration = Duration.ZERO

                val notification = notificationManager.createRecordingNotification(
                    presetName = preset.displayName,
                    duration = Duration.ZERO,
                    isPaused = false
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        RecordingNotificationManager.NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    )
                } else {
                    startForeground(RecordingNotificationManager.NOTIFICATION_ID, notification)
                }

                _recordingState.value = RecordingState.Recording(
                    duration = Duration.ZERO,
                    audioLevel = 0f,
                    preset = preset,
                    isPaused = false
                )

                startMetricsCollection()
            }
            .onFailure { error ->
                _recordingState.value = RecordingState.Error(error.message ?: "Failed to start recording")
                stopSelf()
            }
    }

    private fun startContinuationRecording(
        preset: RecordingPreset,
        origRecordingId: String,
        origFilePath: String,
        origDuration: Duration
    ) {
        if (_recordingState.value is RecordingState.Recording) return

        currentPreset = preset
        isContinuationMode = true
        originalRecordingId = origRecordingId
        originalFilePath = origFilePath
        originalDuration = origDuration

        audioRecorder.startRecording()
            .onSuccess { filePath ->
                currentRecordingId = filePath
                startTime = Instant.now()
                totalPausedDuration = Duration.ZERO

                val notification = notificationManager.createRecordingNotification(
                    presetName = "${preset.displayName} (продолжение)",
                    duration = origDuration,
                    isPaused = false
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        RecordingNotificationManager.NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    )
                } else {
                    startForeground(RecordingNotificationManager.NOTIFICATION_ID, notification)
                }

                _recordingState.value = RecordingState.Recording(
                    duration = origDuration,
                    audioLevel = 0f,
                    preset = preset,
                    isPaused = false
                )

                startMetricsCollection()
            }
            .onFailure { error ->
                _recordingState.value = RecordingState.Error(error.message ?: "Failed to start continuation recording")
                stopSelf()
            }
    }

    private fun pauseRecording() {
        val state = _recordingState.value as? RecordingState.Recording ?: return

        audioRecorder.pauseRecording()
            .onSuccess {
                pausedTime = Instant.now()
                _recordingState.value = state.copy(isPaused = true)

                notificationManager.updateNotification(
                    presetName = currentPreset.displayName,
                    duration = _duration.value,
                    isPaused = true
                )
            }
    }

    private fun resumeRecording() {
        val state = _recordingState.value as? RecordingState.Recording ?: return
        if (!state.isPaused) return

        audioRecorder.resumeRecording()
            .onSuccess {
                pausedTime?.let { paused ->
                    totalPausedDuration = totalPausedDuration.plus(
                        Duration.between(paused, Instant.now())
                    )
                }
                pausedTime = null

                _recordingState.value = state.copy(isPaused = false)

                notificationManager.updateNotification(
                    presetName = currentPreset.displayName,
                    duration = _duration.value,
                    isPaused = false
                )
            }
    }

    private fun stopRecording() {
        metricsJob?.cancel()

        audioRecorder.stopRecording()
            .onSuccess { filePath ->
                val finalDuration = _duration.value

                _recordingState.value = RecordingState.Idle
                _duration.value = Duration.ZERO
                _audioLevel.value = 0f

                if (isContinuationMode) {
                    // Broadcast continuation completed
                    sendBroadcast(Intent("com.vanta.speech.CONTINUATION_COMPLETED").apply {
                        putExtra("file_path", filePath)
                        putExtra("original_recording_id", originalRecordingId)
                        putExtra("original_file_path", originalFilePath)
                        putExtra("duration_seconds", finalDuration.seconds)
                        putExtra("preset_id", currentPreset.id)
                        setPackage(packageName)
                    })
                } else {
                    // Broadcast recording completed
                    sendBroadcast(Intent("com.vanta.speech.RECORDING_COMPLETED").apply {
                        putExtra("file_path", filePath)
                        putExtra("duration_seconds", finalDuration.seconds)
                        putExtra("preset_id", currentPreset.id)
                        setPackage(packageName)
                    })
                }

                // Reset continuation state
                isContinuationMode = false
                originalRecordingId = null
                originalFilePath = null
                originalDuration = Duration.ZERO
            }

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startMetricsCollection() {
        metricsJob?.cancel()
        metricsJob = serviceScope.launch {
            while (isActive) {
                val state = _recordingState.value as? RecordingState.Recording ?: break

                // Update duration
                startTime?.let { start ->
                    var elapsed = Duration.between(start, Instant.now())
                    elapsed = elapsed.minus(totalPausedDuration)

                    // Account for current pause
                    if (state.isPaused) {
                        pausedTime?.let { paused ->
                            elapsed = elapsed.minus(Duration.between(paused, Instant.now()))
                        }
                    }

                    // Add original duration for continuation mode
                    val totalElapsed = if (isContinuationMode) {
                        originalDuration.plus(elapsed)
                    } else {
                        elapsed
                    }

                    _duration.value = totalElapsed

                    // Update audio level
                    if (!state.isPaused) {
                        audioRecorder.updateAudioLevel()
                        _audioLevel.value = audioRecorder.audioLevel.value
                    } else {
                        _audioLevel.value = 0f
                    }

                    // Update state
                    _recordingState.value = state.copy(
                        duration = totalElapsed,
                        audioLevel = _audioLevel.value
                    )

                    // Update notification every second
                    if (totalElapsed.toMillis() % 1000 < UPDATE_INTERVAL_MS) {
                        val presetLabel = if (isContinuationMode) {
                            "${currentPreset.displayName} (продолжение)"
                        } else {
                            currentPreset.displayName
                        }
                        notificationManager.updateNotification(
                            presetName = presetLabel,
                            duration = totalElapsed,
                            isPaused = state.isPaused
                        )
                    }
                }

                delay(UPDATE_INTERVAL_MS)
            }
        }
    }

    fun getCurrentPreset(): RecordingPreset = currentPreset

    fun getRecordingFilePath(): String? = currentRecordingId

    override fun onDestroy() {
        metricsJob?.cancel()
        serviceScope.cancel()

        if (audioRecorder.isRecording.value) {
            audioRecorder.cancelRecording()
        }

        super.onDestroy()
    }
}
