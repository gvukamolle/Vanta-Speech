package com.vanta.speech.core.audio

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import dagger.hilt.android.qualifiers.ApplicationContext
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
import java.io.File
import java.time.Duration
import javax.inject.Inject
import javax.inject.Singleton

sealed class PlaybackState {
    data object Idle : PlaybackState()
    data object Loading : PlaybackState()
    data class Playing(val position: Duration, val duration: Duration) : PlaybackState()
    data class Paused(val position: Duration, val duration: Duration) : PlaybackState()
    data object Completed : PlaybackState()
    data class Error(val message: String) : PlaybackState()
}

@Singleton
class AudioPlayer @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val POSITION_UPDATE_INTERVAL_MS = 100L
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var positionUpdateJob: Job? = null

    private var exoPlayer: ExoPlayer? = null
    private var currentFilePath: String? = null

    private val _playbackState = MutableStateFlow<PlaybackState>(PlaybackState.Idle)
    val playbackState: StateFlow<PlaybackState> = _playbackState.asStateFlow()

    private val _currentPosition = MutableStateFlow(Duration.ZERO)
    val currentPosition: StateFlow<Duration> = _currentPosition.asStateFlow()

    private val _totalDuration = MutableStateFlow(Duration.ZERO)
    val totalDuration: StateFlow<Duration> = _totalDuration.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _playbackSpeed = MutableStateFlow(1.0f)
    val playbackSpeed: StateFlow<Float> = _playbackSpeed.asStateFlow()

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            when (state) {
                Player.STATE_IDLE -> {
                    _playbackState.value = PlaybackState.Idle
                }
                Player.STATE_BUFFERING -> {
                    _playbackState.value = PlaybackState.Loading
                }
                Player.STATE_READY -> {
                    updateDuration()
                    updatePlaybackState()
                }
                Player.STATE_ENDED -> {
                    _playbackState.value = PlaybackState.Completed
                    _isPlaying.value = false
                    stopPositionUpdates()
                }
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _isPlaying.value = isPlaying
            if (isPlaying) {
                startPositionUpdates()
            } else {
                stopPositionUpdates()
            }
            updatePlaybackState()
        }
    }

    private fun getOrCreatePlayer(): ExoPlayer {
        return exoPlayer ?: ExoPlayer.Builder(context)
            .build()
            .also {
                it.addListener(playerListener)
                exoPlayer = it
            }
    }

    fun load(filePath: String) {
        if (currentFilePath == filePath && exoPlayer != null) {
            return
        }

        val file = File(filePath)
        if (!file.exists()) {
            _playbackState.value = PlaybackState.Error("Файл не найден")
            return
        }

        _playbackState.value = PlaybackState.Loading
        currentFilePath = filePath

        val player = getOrCreatePlayer()
        player.stop()
        player.clearMediaItems()

        val mediaItem = MediaItem.fromUri(filePath)
        player.setMediaItem(mediaItem)
        player.prepare()
    }

    fun play() {
        val player = exoPlayer ?: return

        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(0)
        }

        player.play()
    }

    fun pause() {
        exoPlayer?.pause()
    }

    fun togglePlayPause() {
        if (_isPlaying.value) {
            pause()
        } else {
            play()
        }
    }

    fun seekTo(position: Duration) {
        exoPlayer?.seekTo(position.toMillis())
        _currentPosition.value = position
        updatePlaybackState()
    }

    fun seekForward(seconds: Long = 10) {
        val player = exoPlayer ?: return
        val newPosition = (player.currentPosition + seconds * 1000).coerceAtMost(player.duration)
        player.seekTo(newPosition)
    }

    fun seekBackward(seconds: Long = 10) {
        val player = exoPlayer ?: return
        val newPosition = (player.currentPosition - seconds * 1000).coerceAtLeast(0)
        player.seekTo(newPosition)
    }

    fun setPlaybackSpeed(speed: Float) {
        _playbackSpeed.value = speed
        exoPlayer?.setPlaybackSpeed(speed)
    }

    fun stop() {
        stopPositionUpdates()
        exoPlayer?.stop()
        exoPlayer?.clearMediaItems()
        currentFilePath = null
        _playbackState.value = PlaybackState.Idle
        _currentPosition.value = Duration.ZERO
        _totalDuration.value = Duration.ZERO
        _isPlaying.value = false
    }

    fun release() {
        stop()
        exoPlayer?.removeListener(playerListener)
        exoPlayer?.release()
        exoPlayer = null
        scope.cancel()
    }

    private fun updateDuration() {
        val duration = exoPlayer?.duration ?: 0L
        if (duration > 0) {
            _totalDuration.value = Duration.ofMillis(duration)
        }
    }

    private fun updatePlaybackState() {
        val player = exoPlayer ?: return
        val position = Duration.ofMillis(player.currentPosition)
        val duration = Duration.ofMillis(player.duration.coerceAtLeast(0))

        _currentPosition.value = position

        _playbackState.value = if (_isPlaying.value) {
            PlaybackState.Playing(position, duration)
        } else {
            PlaybackState.Paused(position, duration)
        }
    }

    private fun startPositionUpdates() {
        positionUpdateJob?.cancel()
        positionUpdateJob = scope.launch {
            while (isActive && _isPlaying.value) {
                updatePlaybackState()
                delay(POSITION_UPDATE_INTERVAL_MS)
            }
        }
    }

    private fun stopPositionUpdates() {
        positionUpdateJob?.cancel()
        positionUpdateJob = null
    }
}
