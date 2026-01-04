package com.vanta.speech.core.audio

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AudioRecorder @Inject constructor(
    private val context: Context
) {
    companion object {
        private const val SAMPLE_RATE = 44100
        private const val BIT_RATE = 64000
        private const val CHANNELS = 1
        private const val MAX_AMPLITUDE = 32767f
    }

    private var mediaRecorder: MediaRecorder? = null
    private var currentFilePath: String? = null
    private var isPaused = false

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _audioLevel = MutableStateFlow(0f)
    val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    private val recordingsDir: File
        get() {
            val dir = File(context.filesDir, "recordings")
            if (!dir.exists()) dir.mkdirs()
            return dir
        }

    fun startRecording(): Result<String> = runCatching {
        if (_isRecording.value) {
            throw IllegalStateException("Already recording")
        }

        val fileName = generateFileName()
        val file = File(recordingsDir, fileName)
        currentFilePath = file.absolutePath

        mediaRecorder = createMediaRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(SAMPLE_RATE)
            setAudioEncodingBitRate(BIT_RATE)
            setAudioChannels(CHANNELS)
            setOutputFile(file.absolutePath)

            prepare()
            start()
        }

        _isRecording.value = true
        isPaused = false

        file.absolutePath
    }

    fun pauseRecording(): Result<Unit> = runCatching {
        if (!_isRecording.value || isPaused) {
            throw IllegalStateException("Not recording or already paused")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            mediaRecorder?.pause()
            isPaused = true
        }
    }

    fun resumeRecording(): Result<Unit> = runCatching {
        if (!_isRecording.value || !isPaused) {
            throw IllegalStateException("Not recording or not paused")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            mediaRecorder?.resume()
            isPaused = false
        }
    }

    fun stopRecording(): Result<String> = runCatching {
        if (!_isRecording.value) {
            throw IllegalStateException("Not recording")
        }

        val filePath = currentFilePath ?: throw IllegalStateException("No file path")

        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
        } catch (e: Exception) {
            // Recording might have been too short
        }

        mediaRecorder = null
        _isRecording.value = false
        isPaused = false
        _audioLevel.value = 0f

        filePath
    }

    fun cancelRecording() {
        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
        } catch (e: Exception) {
            // Ignore
        }

        currentFilePath?.let { path ->
            File(path).delete()
        }

        mediaRecorder = null
        currentFilePath = null
        _isRecording.value = false
        isPaused = false
        _audioLevel.value = 0f
    }

    fun updateAudioLevel() {
        if (!_isRecording.value || isPaused) {
            _audioLevel.value = 0f
            return
        }

        try {
            val amplitude = mediaRecorder?.maxAmplitude ?: 0
            // Normalize to 0-1 range with some smoothing
            val normalized = (amplitude / MAX_AMPLITUDE).coerceIn(0f, 1f)
            _audioLevel.value = normalized
        } catch (e: Exception) {
            _audioLevel.value = 0f
        }
    }

    fun getCurrentFilePath(): String? = currentFilePath

    fun isPaused(): Boolean = isPaused

    private fun createMediaRecorder(): MediaRecorder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
    }

    private fun generateFileName(): String {
        val timestamp = Instant.now()
            .atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"))
        return "recording_$timestamp.m4a"
    }
}
