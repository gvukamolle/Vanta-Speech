package com.vantaspeech.ui.screens.settings

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.vantaspeech.data.model.AudioQuality
import com.vantaspeech.data.network.TranscriptionService
import com.vantaspeech.data.repository.RecordingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val application: Application,
    private val recordingRepository: RecordingRepository,
    private val transcriptionService: TranscriptionService
) : AndroidViewModel(application) {

    private val prefs = application.getSharedPreferences("vanta_settings", Context.MODE_PRIVATE)

    private val _serverUrl = MutableStateFlow(
        prefs.getString("server_url", "") ?: ""
    )
    val serverUrl: StateFlow<String> = _serverUrl.asStateFlow()

    private val _autoTranscribe = MutableStateFlow(
        prefs.getBoolean("auto_transcribe", false)
    )
    val autoTranscribe: StateFlow<Boolean> = _autoTranscribe.asStateFlow()

    private val _audioQuality = MutableStateFlow(
        AudioQuality.entries.find {
            it.name == prefs.getString("audio_quality", AudioQuality.LOW.name)
        } ?: AudioQuality.LOW
    )
    val audioQuality: StateFlow<AudioQuality> = _audioQuality.asStateFlow()

    fun updateServerUrl(url: String) {
        _serverUrl.value = url
        prefs.edit().putString("server_url", url).apply()
        transcriptionService.updateServerUrl(url)
    }

    fun updateAutoTranscribe(enabled: Boolean) {
        _autoTranscribe.value = enabled
        prefs.edit().putBoolean("auto_transcribe", enabled).apply()
    }

    fun updateAudioQuality(quality: AudioQuality) {
        _audioQuality.value = quality
        prefs.edit().putString("audio_quality", quality.name).apply()
    }

    fun clearAllRecordings() {
        viewModelScope.launch {
            // Delete all audio files
            val recordingsDir = File(application.filesDir, "recordings")
            recordingsDir.listFiles()?.forEach { file ->
                file.delete()
            }

            // Clear database
            recordingRepository.deleteAllRecordings()
        }
    }
}
