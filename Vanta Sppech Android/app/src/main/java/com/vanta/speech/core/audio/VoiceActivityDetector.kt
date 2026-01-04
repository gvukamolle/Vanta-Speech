package com.vanta.speech.core.audio

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

sealed class VADEvent {
    data class SpeechStarted(val timestamp: Instant) : VADEvent()
    data class SpeechEnded(val timestamp: Instant, val duration: Duration) : VADEvent()
    data class ChunkReady(
        val startTime: Instant,
        val endTime: Instant,
        val duration: Duration,
        val reason: ChunkReason
    ) : VADEvent()
}

enum class ChunkReason {
    SILENCE_DETECTED,
    MAX_DURATION_REACHED,
    MANUAL_SPLIT
}

enum class VADState {
    IDLE,
    LISTENING,
    SPEECH_DETECTED,
    SILENCE_DETECTED
}

@Singleton
class VoiceActivityDetector @Inject constructor() {

    companion object {
        // Audio level threshold (0-1) below which is considered silence
        private const val SILENCE_THRESHOLD = 0.08f

        // How long silence must persist to trigger chunk split (ms)
        private const val SILENCE_DURATION_MS = 1500L

        // Minimum chunk duration before allowing split (seconds)
        private const val MIN_CHUNK_DURATION_S = 10L

        // Maximum chunk duration, force split (seconds)
        private const val MAX_CHUNK_DURATION_S = 60L

        // How often to sample audio level (ms)
        private const val SAMPLE_INTERVAL_MS = 50L

        // Number of samples to average for smoothing
        private const val SMOOTHING_SAMPLES = 5
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var monitoringJob: Job? = null

    private val _state = MutableStateFlow(VADState.IDLE)
    val state: StateFlow<VADState> = _state.asStateFlow()

    private val _events = MutableSharedFlow<VADEvent>(replay = 0)
    val events: SharedFlow<VADEvent> = _events.asSharedFlow()

    private val _isListening = MutableStateFlow(false)
    val isListening: StateFlow<Boolean> = _isListening.asStateFlow()

    private val _currentChunkDuration = MutableStateFlow(Duration.ZERO)
    val currentChunkDuration: StateFlow<Duration> = _currentChunkDuration.asStateFlow()

    // Audio level provider - set by the recording component
    private var audioLevelProvider: (() -> Float)? = null

    // State tracking
    private var speechStartTime: Instant? = null
    private var lastSpeechTime: Instant? = null
    private var chunkStartTime: Instant? = null
    private var silenceStartTime: Instant? = null

    // Smoothing buffer for audio levels
    private val levelBuffer = ArrayDeque<Float>(SMOOTHING_SAMPLES)

    fun setAudioLevelProvider(provider: () -> Float) {
        audioLevelProvider = provider
    }

    fun startListening() {
        if (_isListening.value) return

        _isListening.value = true
        _state.value = VADState.LISTENING
        chunkStartTime = Instant.now()
        speechStartTime = null
        lastSpeechTime = null
        silenceStartTime = null
        levelBuffer.clear()

        monitoringJob = scope.launch {
            while (isActive && _isListening.value) {
                processAudioLevel()
                delay(SAMPLE_INTERVAL_MS)
            }
        }
    }

    fun stopListening() {
        if (!_isListening.value) return

        monitoringJob?.cancel()
        monitoringJob = null

        // Emit final chunk if we have accumulated speech
        chunkStartTime?.let { start ->
            val now = Instant.now()
            val duration = Duration.between(start, now)

            if (duration.seconds >= MIN_CHUNK_DURATION_S) {
                scope.launch {
                    _events.emit(
                        VADEvent.ChunkReady(
                            startTime = start,
                            endTime = now,
                            duration = duration,
                            reason = ChunkReason.MANUAL_SPLIT
                        )
                    )
                }
            }
        }

        _isListening.value = false
        _state.value = VADState.IDLE
        _currentChunkDuration.value = Duration.ZERO
        chunkStartTime = null
        speechStartTime = null
        lastSpeechTime = null
        silenceStartTime = null
    }

    fun forceChunkSplit() {
        if (!_isListening.value) return

        chunkStartTime?.let { start ->
            val now = Instant.now()
            val duration = Duration.between(start, now)

            scope.launch {
                _events.emit(
                    VADEvent.ChunkReady(
                        startTime = start,
                        endTime = now,
                        duration = duration,
                        reason = ChunkReason.MANUAL_SPLIT
                    )
                )
            }

            // Start new chunk
            chunkStartTime = now
            _currentChunkDuration.value = Duration.ZERO
        }
    }

    private suspend fun processAudioLevel() {
        val rawLevel = audioLevelProvider?.invoke() ?: 0f
        val smoothedLevel = smoothLevel(rawLevel)
        val now = Instant.now()

        // Update chunk duration
        chunkStartTime?.let { start ->
            _currentChunkDuration.value = Duration.between(start, now)
        }

        val isSpeech = smoothedLevel > SILENCE_THRESHOLD

        when (_state.value) {
            VADState.IDLE -> {
                // Should not happen while listening
            }

            VADState.LISTENING -> {
                if (isSpeech) {
                    _state.value = VADState.SPEECH_DETECTED
                    speechStartTime = now
                    lastSpeechTime = now
                    silenceStartTime = null

                    _events.emit(VADEvent.SpeechStarted(now))
                }
            }

            VADState.SPEECH_DETECTED -> {
                if (isSpeech) {
                    lastSpeechTime = now
                    silenceStartTime = null
                } else {
                    // Potential silence detected
                    if (silenceStartTime == null) {
                        silenceStartTime = now
                    }

                    val silenceDuration = Duration.between(silenceStartTime!!, now)
                    val chunkDuration = chunkStartTime?.let { Duration.between(it, now) } ?: Duration.ZERO

                    // Check if we should split
                    if (silenceDuration.toMillis() >= SILENCE_DURATION_MS &&
                        chunkDuration.seconds >= MIN_CHUNK_DURATION_S
                    ) {
                        // Split chunk at silence
                        emitChunkReady(ChunkReason.SILENCE_DETECTED)
                        _state.value = VADState.LISTENING
                    } else {
                        _state.value = VADState.SILENCE_DETECTED
                    }
                }

                // Check max duration
                checkMaxDuration()
            }

            VADState.SILENCE_DETECTED -> {
                if (isSpeech) {
                    // Speech resumed
                    _state.value = VADState.SPEECH_DETECTED
                    lastSpeechTime = now
                    silenceStartTime = null
                } else {
                    val silenceDuration = silenceStartTime?.let { Duration.between(it, now) } ?: Duration.ZERO
                    val chunkDuration = chunkStartTime?.let { Duration.between(it, now) } ?: Duration.ZERO

                    // Check if silence is long enough
                    if (silenceDuration.toMillis() >= SILENCE_DURATION_MS &&
                        chunkDuration.seconds >= MIN_CHUNK_DURATION_S
                    ) {
                        emitChunkReady(ChunkReason.SILENCE_DETECTED)
                        _state.value = VADState.LISTENING
                    }
                }

                // Check max duration
                checkMaxDuration()
            }
        }
    }

    private suspend fun emitChunkReady(reason: ChunkReason) {
        chunkStartTime?.let { start ->
            val now = Instant.now()
            val duration = Duration.between(start, now)

            // Emit speech ended event
            speechStartTime?.let { speechStart ->
                _events.emit(
                    VADEvent.SpeechEnded(
                        timestamp = now,
                        duration = Duration.between(speechStart, lastSpeechTime ?: now)
                    )
                )
            }

            // Emit chunk ready
            _events.emit(
                VADEvent.ChunkReady(
                    startTime = start,
                    endTime = now,
                    duration = duration,
                    reason = reason
                )
            )

            // Reset for next chunk
            chunkStartTime = now
            speechStartTime = null
            lastSpeechTime = null
            silenceStartTime = null
            _currentChunkDuration.value = Duration.ZERO
        }
    }

    private suspend fun checkMaxDuration() {
        chunkStartTime?.let { start ->
            val duration = Duration.between(start, Instant.now())

            if (duration.seconds >= MAX_CHUNK_DURATION_S) {
                emitChunkReady(ChunkReason.MAX_DURATION_REACHED)
                _state.value = VADState.LISTENING
            }
        }
    }

    private fun smoothLevel(level: Float): Float {
        if (levelBuffer.size >= SMOOTHING_SAMPLES) {
            levelBuffer.removeFirst()
        }
        levelBuffer.addLast(level)

        return if (levelBuffer.isNotEmpty()) {
            levelBuffer.average().toFloat()
        } else {
            level
        }
    }

    fun release() {
        stopListening()
        scope.cancel()
    }
}
