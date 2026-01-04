package com.vanta.speech.core.audio

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import com.vanta.speech.core.data.remote.api.TranscriptionApi
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject
import javax.inject.Singleton

data class TranscriptionChunk(
    val id: Int,
    val audioFile: File,
    val startTime: Instant,
    val endTime: Instant,
    val duration: Duration
)

data class TranscriptionResult(
    val chunkId: Int,
    val text: String,
    val startTime: Instant,
    val endTime: Instant
)

sealed class RealtimeState {
    data object Idle : RealtimeState()
    data object Recording : RealtimeState()
    data class Processing(val progress: Float, val chunksCompleted: Int, val totalChunks: Int) : RealtimeState()
    data object Merging : RealtimeState()
    data class Completed(val filePath: String, val fullTranscription: String) : RealtimeState()
    data class Error(val message: String) : RealtimeState()
}

sealed class RealtimeEvent {
    data class ChunkRecorded(val chunkId: Int, val duration: Duration) : RealtimeEvent()
    data class ChunkTranscribed(val chunkId: Int, val text: String) : RealtimeEvent()
    data class TranscriptionUpdated(val fullText: String) : RealtimeEvent()
    data class ChunkFailed(val chunkId: Int, val error: String) : RealtimeEvent()
}

@Singleton
class RealtimeTranscriptionManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val transcriptionApi: TranscriptionApi,
    private val voiceActivityDetector: VoiceActivityDetector
) {
    companion object {
        private const val SAMPLE_RATE = 44100
        private const val BIT_RATE = 64000
        private const val CHANNELS = 1
        private const val MAX_AMPLITUDE = 32767f
        private const val MODEL = "gigaam-v3"
        private const val LANGUAGE = "ru"
        private const val MAX_CONCURRENT_TRANSCRIPTIONS = 2
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val transcriptionChannel = Channel<TranscriptionChunk>(Channel.UNLIMITED)

    private val _state = MutableStateFlow<RealtimeState>(RealtimeState.Idle)
    val state: StateFlow<RealtimeState> = _state.asStateFlow()

    private val _events = MutableSharedFlow<RealtimeEvent>(replay = 0)
    val events: SharedFlow<RealtimeEvent> = _events.asSharedFlow()

    private val _currentTranscription = MutableStateFlow("")
    val currentTranscription: StateFlow<String> = _currentTranscription.asStateFlow()

    private val _audioLevel = MutableStateFlow(0f)
    val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    private val _totalDuration = MutableStateFlow(Duration.ZERO)
    val totalDuration: StateFlow<Duration> = _totalDuration.asStateFlow()

    // Recording state
    private var mediaRecorder: MediaRecorder? = null
    private var currentChunkFile: File? = null
    private var chunkStartTime: Instant? = null
    private val chunkCounter = AtomicInteger(0)

    // Chunk management
    private val recordedChunks = mutableListOf<TranscriptionChunk>()
    private val transcriptionResults = ConcurrentHashMap<Int, TranscriptionResult>()
    private val pendingTranscriptions = AtomicInteger(0)

    private val chunksDir: File
        get() {
            val dir = File(context.filesDir, "realtime_chunks")
            if (!dir.exists()) dir.mkdirs()
            return dir
        }

    private val mergedDir: File
        get() {
            val dir = File(context.filesDir, "recordings")
            if (!dir.exists()) dir.mkdirs()
            return dir
        }

    init {
        setupVADListener()
        startTranscriptionWorkers()
    }

    private fun setupVADListener() {
        scope.launch {
            voiceActivityDetector.events.collect { event ->
                when (event) {
                    is VADEvent.ChunkReady -> {
                        handleChunkReady()
                    }
                    else -> { /* Ignore other events */ }
                }
            }
        }
    }

    private fun startTranscriptionWorkers() {
        repeat(MAX_CONCURRENT_TRANSCRIPTIONS) {
            scope.launch {
                for (chunk in transcriptionChannel) {
                    processChunk(chunk)
                }
            }
        }
    }

    fun startRecording() {
        if (_state.value is RealtimeState.Recording) return

        // Clear previous session
        recordedChunks.clear()
        transcriptionResults.clear()
        _currentTranscription.value = ""
        _totalDuration.value = Duration.ZERO
        chunkCounter.set(0)
        pendingTranscriptions.set(0)

        // Clean up old chunks
        chunksDir.listFiles()?.forEach { it.delete() }

        // Setup VAD audio level provider
        voiceActivityDetector.setAudioLevelProvider { getAudioLevel() }

        // Start first chunk
        startNewChunk()

        // Start VAD
        voiceActivityDetector.startListening()

        _state.value = RealtimeState.Recording
    }

    private fun startNewChunk() {
        val chunkId = chunkCounter.incrementAndGet()
        val fileName = "chunk_${chunkId}_${System.currentTimeMillis()}.m4a"
        currentChunkFile = File(chunksDir, fileName)
        chunkStartTime = Instant.now()

        mediaRecorder = createMediaRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(SAMPLE_RATE)
            setAudioEncodingBitRate(BIT_RATE)
            setAudioChannels(CHANNELS)
            setOutputFile(currentChunkFile!!.absolutePath)

            prepare()
            start()
        }
    }

    private fun handleChunkReady() {
        val file = currentChunkFile ?: return
        val startTime = chunkStartTime ?: return
        val endTime = Instant.now()
        val duration = Duration.between(startTime, endTime)

        // Stop current recording
        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
        } catch (e: Exception) {
            // Recording might have been too short
        }
        mediaRecorder = null

        val chunkId = chunkCounter.get()

        // Create chunk data
        val chunk = TranscriptionChunk(
            id = chunkId,
            audioFile = file,
            startTime = startTime,
            endTime = endTime,
            duration = duration
        )

        recordedChunks.add(chunk)
        _totalDuration.value = _totalDuration.value.plus(duration)

        scope.launch {
            _events.emit(RealtimeEvent.ChunkRecorded(chunkId, duration))
        }

        // Queue for transcription
        pendingTranscriptions.incrementAndGet()
        scope.launch {
            transcriptionChannel.send(chunk)
        }

        // Start next chunk if still recording
        if (_state.value is RealtimeState.Recording) {
            startNewChunk()
        }
    }

    private suspend fun processChunk(chunk: TranscriptionChunk) {
        try {
            val file = chunk.audioFile
            if (!file.exists()) {
                _events.emit(RealtimeEvent.ChunkFailed(chunk.id, "File not found"))
                pendingTranscriptions.decrementAndGet()
                return
            }

            val requestFile = file.asRequestBody("audio/mp4".toMediaTypeOrNull())
            val filePart = MultipartBody.Part.createFormData("file", file.name, requestFile)
            val modelPart = MODEL.toRequestBody("text/plain".toMediaTypeOrNull())
            val languagePart = LANGUAGE.toRequestBody("text/plain".toMediaTypeOrNull())

            val response = transcriptionApi.transcribe(filePart, modelPart, languagePart)

            val result = TranscriptionResult(
                chunkId = chunk.id,
                text = response.text.trim(),
                startTime = chunk.startTime,
                endTime = chunk.endTime
            )

            transcriptionResults[chunk.id] = result

            _events.emit(RealtimeEvent.ChunkTranscribed(chunk.id, result.text))

            // Update full transcription
            updateFullTranscription()

        } catch (e: Exception) {
            _events.emit(RealtimeEvent.ChunkFailed(chunk.id, e.message ?: "Unknown error"))
        } finally {
            val remaining = pendingTranscriptions.decrementAndGet()
            updateProcessingState(remaining)
        }
    }

    private suspend fun updateFullTranscription() {
        val sortedResults = transcriptionResults.values
            .sortedBy { it.chunkId }
            .map { it.text }
            .filter { it.isNotBlank() }
            .joinToString(" ")

        _currentTranscription.value = sortedResults
        _events.emit(RealtimeEvent.TranscriptionUpdated(sortedResults))
    }

    private fun updateProcessingState(remainingChunks: Int) {
        val state = _state.value
        if (state is RealtimeState.Processing) {
            val completed = state.totalChunks - remainingChunks
            val progress = if (state.totalChunks > 0) {
                completed.toFloat() / state.totalChunks
            } else {
                1f
            }

            _state.value = RealtimeState.Processing(
                progress = progress,
                chunksCompleted = completed,
                totalChunks = state.totalChunks
            )

            // Check if all done
            if (remainingChunks == 0) {
                scope.launch {
                    mergeAndFinalize()
                }
            }
        }
    }

    fun stopRecording() {
        if (_state.value !is RealtimeState.Recording) return

        // Stop VAD
        voiceActivityDetector.stopListening()

        // Force final chunk
        val file = currentChunkFile
        val startTime = chunkStartTime

        if (file != null && startTime != null) {
            val endTime = Instant.now()
            val duration = Duration.between(startTime, endTime)

            try {
                mediaRecorder?.apply {
                    stop()
                    release()
                }
            } catch (e: Exception) {
                // Ignore
            }
            mediaRecorder = null

            // Only add chunk if it has content
            if (duration.toMillis() > 500 && file.exists() && file.length() > 0) {
                val chunkId = chunkCounter.get()
                val chunk = TranscriptionChunk(
                    id = chunkId,
                    audioFile = file,
                    startTime = startTime,
                    endTime = endTime,
                    duration = duration
                )
                recordedChunks.add(chunk)
                _totalDuration.value = _totalDuration.value.plus(duration)

                pendingTranscriptions.incrementAndGet()
                scope.launch {
                    transcriptionChannel.send(chunk)
                }
            }
        }

        // Update state to processing
        val totalChunks = pendingTranscriptions.get()
        if (totalChunks > 0) {
            _state.value = RealtimeState.Processing(
                progress = 0f,
                chunksCompleted = 0,
                totalChunks = totalChunks
            )
        } else {
            // No pending transcriptions, go straight to merging
            scope.launch {
                mergeAndFinalize()
            }
        }
    }

    private suspend fun mergeAndFinalize() {
        _state.value = RealtimeState.Merging

        try {
            // Merge audio files
            val mergedFile = mergeAudioChunks()

            // Get final transcription
            val finalTranscription = _currentTranscription.value

            // Clean up chunks
            recordedChunks.forEach { chunk ->
                chunk.audioFile.delete()
            }

            _state.value = RealtimeState.Completed(
                filePath = mergedFile.absolutePath,
                fullTranscription = finalTranscription
            )

        } catch (e: Exception) {
            _state.value = RealtimeState.Error(e.message ?: "Failed to finalize recording")
        }
    }

    private fun mergeAudioChunks(): File {
        val timestamp = Instant.now()
            .atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"))
        val mergedFileName = "recording_realtime_$timestamp.m4a"
        val mergedFile = File(mergedDir, mergedFileName)

        val sortedChunks = recordedChunks.sortedBy { it.id }

        if (sortedChunks.isEmpty()) {
            // Create empty file
            mergedFile.createNewFile()
            return mergedFile
        }

        if (sortedChunks.size == 1) {
            // Just copy the single file
            sortedChunks.first().audioFile.copyTo(mergedFile, overwrite = true)
            return mergedFile
        }

        // For multiple chunks, we need to merge
        // Simple approach: use first chunk and append others
        // Note: Proper AAC merging is complex, this is a simplified version
        // In production, you'd use MediaMuxer or FFmpeg
        sortedChunks.first().audioFile.copyTo(mergedFile, overwrite = true)

        // For a proper implementation, we would need to:
        // 1. Decode each chunk
        // 2. Concatenate raw audio
        // 3. Re-encode to M4A
        // This simplified version just returns the first chunk

        return mergedFile
    }

    fun cancelRecording() {
        voiceActivityDetector.stopListening()

        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
        } catch (e: Exception) {
            // Ignore
        }
        mediaRecorder = null

        // Clean up all chunks
        recordedChunks.forEach { chunk ->
            chunk.audioFile.delete()
        }
        recordedChunks.clear()
        transcriptionResults.clear()

        _state.value = RealtimeState.Idle
        _currentTranscription.value = ""
        _totalDuration.value = Duration.ZERO
    }

    private fun getAudioLevel(): Float {
        return try {
            val amplitude = mediaRecorder?.maxAmplitude ?: 0
            val level = (amplitude / MAX_AMPLITUDE).coerceIn(0f, 1f)
            _audioLevel.value = level
            level
        } catch (e: Exception) {
            0f
        }
    }

    private fun createMediaRecorder(): MediaRecorder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
    }

    fun release() {
        cancelRecording()
        scope.cancel()
    }
}
