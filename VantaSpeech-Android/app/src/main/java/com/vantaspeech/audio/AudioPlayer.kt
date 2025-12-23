package com.vantaspeech.audio

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

enum class PlaybackState {
    IDLE,
    PLAYING,
    PAUSED,
    ENDED
}

@Singleton
class AudioPlayer @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var exoPlayer: ExoPlayer? = null
    private var currentFilePath: String? = null

    private val _playbackState = MutableStateFlow(PlaybackState.IDLE)
    val playbackState: StateFlow<PlaybackState> = _playbackState.asStateFlow()

    private val _currentPosition = MutableStateFlow(0L)
    val currentPosition: StateFlow<Long> = _currentPosition.asStateFlow()

    private val _duration = MutableStateFlow(0L)
    val duration: StateFlow<Long> = _duration.asStateFlow()

    private val _progress = MutableStateFlow(0f)
    val progress: StateFlow<Float> = _progress.asStateFlow()

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_IDLE -> _playbackState.value = PlaybackState.IDLE
                Player.STATE_BUFFERING -> {} // Keep current state
                Player.STATE_READY -> {
                    _duration.value = exoPlayer?.duration ?: 0
                }
                Player.STATE_ENDED -> {
                    _playbackState.value = PlaybackState.ENDED
                    _currentPosition.value = 0
                    _progress.value = 0f
                }
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _playbackState.value = if (isPlaying) PlaybackState.PLAYING else PlaybackState.PAUSED
        }
    }

    fun load(filePath: String) {
        if (currentFilePath == filePath && exoPlayer != null) return

        release()
        currentFilePath = filePath

        exoPlayer = ExoPlayer.Builder(context).build().apply {
            addListener(playerListener)
            setMediaItem(MediaItem.fromUri(filePath))
            prepare()
        }

        _playbackState.value = PlaybackState.IDLE
        _currentPosition.value = 0
        _progress.value = 0f
    }

    fun play() {
        exoPlayer?.play()
    }

    fun pause() {
        exoPlayer?.pause()
    }

    fun stop() {
        exoPlayer?.stop()
        _playbackState.value = PlaybackState.IDLE
        _currentPosition.value = 0
        _progress.value = 0f
    }

    fun seekTo(positionMs: Long) {
        exoPlayer?.seekTo(positionMs)
        _currentPosition.value = positionMs
        updateProgress()
    }

    fun seekToProgress(progress: Float) {
        val duration = exoPlayer?.duration ?: 0
        val position = (duration * progress).toLong()
        seekTo(position)
    }

    fun skipForward(seconds: Int = 15) {
        val currentPos = exoPlayer?.currentPosition ?: 0
        val duration = exoPlayer?.duration ?: 0
        val newPos = (currentPos + seconds * 1000).coerceAtMost(duration)
        seekTo(newPos)
    }

    fun skipBackward(seconds: Int = 15) {
        val currentPos = exoPlayer?.currentPosition ?: 0
        val newPos = (currentPos - seconds * 1000).coerceAtLeast(0)
        seekTo(newPos)
    }

    fun updateProgress() {
        exoPlayer?.let { player ->
            _currentPosition.value = player.currentPosition
            val duration = player.duration
            if (duration > 0) {
                _progress.value = player.currentPosition.toFloat() / duration
            }
        }
    }

    fun release() {
        exoPlayer?.apply {
            removeListener(playerListener)
            release()
        }
        exoPlayer = null
        currentFilePath = null
        _playbackState.value = PlaybackState.IDLE
        _currentPosition.value = 0
        _duration.value = 0
        _progress.value = 0f
    }

    fun formatTime(millis: Long): String {
        val totalSeconds = millis / 1000
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60

        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%d:%02d", minutes, seconds)
        }
    }
}
