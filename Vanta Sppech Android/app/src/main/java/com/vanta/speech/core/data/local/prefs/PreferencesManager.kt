package com.vanta.speech.core.data.local.prefs

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "vanta_settings")

class PreferencesManager(private val context: Context) {

    companion object {
        private val KEY_DARK_THEME = booleanPreferencesKey("dark_theme")
        private val KEY_DEFAULT_PRESET = stringPreferencesKey("default_preset")
        private val KEY_AUDIO_QUALITY = intPreferencesKey("audio_quality")
        private val KEY_REALTIME_PAUSE_THRESHOLD = floatPreferencesKey("realtime_pause_threshold")
        private val KEY_VAD_SILENCE_THRESHOLD = floatPreferencesKey("vad_silence_threshold")
    }

    val darkTheme: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[KEY_DARK_THEME] ?: true
    }

    val defaultPreset: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[KEY_DEFAULT_PRESET]
    }

    val audioQuality: Flow<Int> = context.dataStore.data.map { prefs ->
        prefs[KEY_AUDIO_QUALITY] ?: 64000 // Default 64kbps
    }

    val realtimePauseThreshold: Flow<Float> = context.dataStore.data.map { prefs ->
        prefs[KEY_REALTIME_PAUSE_THRESHOLD] ?: 3.0f // Default 3 seconds
    }

    val vadSilenceThreshold: Flow<Float> = context.dataStore.data.map { prefs ->
        prefs[KEY_VAD_SILENCE_THRESHOLD] ?: 0.08f // Default 0.08
    }

    suspend fun setDarkTheme(enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[KEY_DARK_THEME] = enabled
        }
    }

    suspend fun setDefaultPreset(presetId: String) {
        context.dataStore.edit { prefs ->
            prefs[KEY_DEFAULT_PRESET] = presetId
        }
    }

    suspend fun setAudioQuality(bitrate: Int) {
        context.dataStore.edit { prefs ->
            prefs[KEY_AUDIO_QUALITY] = bitrate
        }
    }

    suspend fun setRealtimePauseThreshold(seconds: Float) {
        context.dataStore.edit { prefs ->
            prefs[KEY_REALTIME_PAUSE_THRESHOLD] = seconds
        }
    }

    suspend fun setVadSilenceThreshold(threshold: Float) {
        context.dataStore.edit { prefs ->
            prefs[KEY_VAD_SILENCE_THRESHOLD] = threshold
        }
    }
}
