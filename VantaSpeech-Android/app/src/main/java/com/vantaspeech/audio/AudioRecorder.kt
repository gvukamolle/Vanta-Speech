package com.vantaspeech.audio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import androidx.core.content.ContextCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

enum class RecordingState {
    IDLE,
    RECORDING,
    PAUSED,
    STOPPED
}

@Singleton
class AudioRecorder @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var mediaRecorder: MediaRecorder? = null
    private var currentFilePath: String? = null
    private var startTime: Long = 0
    private var pausedDuration: Long = 0
    private var pauseStartTime: Long = 0

    private val _state = MutableStateFlow(RecordingState.IDLE)
    val state: StateFlow<RecordingState> = _state.asStateFlow()

    private val _duration = MutableStateFlow(0L)
    val duration: StateFlow<Long> = _duration.asStateFlow()

    private val _audioLevel = MutableStateFlow(0f)
    val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    val hasRecordPermission: Boolean
        get() = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

    fun startRecording(): String? {
        if (!hasRecordPermission) return null

        try {
            val recordingsDir = getRecordingsDirectory()
            val fileName = generateFileName()
            val filePath = File(recordingsDir, fileName).absolutePath
            currentFilePath = filePath

            mediaRecorder = createMediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128000)
                setAudioSamplingRate(44100)
                setAudioChannels(1)
                setOutputFile(filePath)
                prepare()
                start()
            }

            startTime = System.currentTimeMillis()
            pausedDuration = 0
            _state.value = RecordingState.RECORDING

            return filePath
        } catch (e: Exception) {
            e.printStackTrace()
            cleanup()
            return null
        }
    }

    fun pauseRecording() {
        if (_state.value != RecordingState.RECORDING) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                mediaRecorder?.pause()
                pauseStartTime = System.currentTimeMillis()
                _state.value = RecordingState.PAUSED
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun resumeRecording() {
        if (_state.value != RecordingState.PAUSED) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                mediaRecorder?.resume()
                pausedDuration += System.currentTimeMillis() - pauseStartTime
                _state.value = RecordingState.RECORDING
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stopRecording(): Pair<String, Long>? {
        if (_state.value == RecordingState.IDLE) return null

        val filePath = currentFilePath
        val duration = getCurrentDuration()

        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        cleanup()
        _state.value = RecordingState.IDLE

        return if (filePath != null) {
            Pair(filePath, duration)
        } else null
    }

    fun updateMetrics() {
        if (_state.value == RecordingState.RECORDING) {
            _duration.value = getCurrentDuration()

            // Get audio level (amplitude)
            try {
                val maxAmplitude = mediaRecorder?.maxAmplitude ?: 0
                val normalizedLevel = (maxAmplitude / 32767f).coerceIn(0f, 1f)
                _audioLevel.value = normalizedLevel
            } catch (e: Exception) {
                _audioLevel.value = 0f
            }
        }
    }

    private fun getCurrentDuration(): Long {
        return when (_state.value) {
            RecordingState.RECORDING -> {
                (System.currentTimeMillis() - startTime - pausedDuration) / 1000
            }
            RecordingState.PAUSED -> {
                (pauseStartTime - startTime - pausedDuration) / 1000
            }
            else -> 0L
        }
    }

    private fun cleanup() {
        mediaRecorder?.release()
        mediaRecorder = null
        currentFilePath = null
        startTime = 0
        pausedDuration = 0
        pauseStartTime = 0
        _duration.value = 0
        _audioLevel.value = 0f
    }

    private fun getRecordingsDirectory(): File {
        val dir = File(context.filesDir, "recordings")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    private fun generateFileName(): String {
        val dateFormat = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault())
        return "recording_${dateFormat.format(Date())}.m4a"
    }

    @Suppress("DEPRECATION")
    private fun createMediaRecorder(): MediaRecorder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            MediaRecorder()
        }
    }
}
