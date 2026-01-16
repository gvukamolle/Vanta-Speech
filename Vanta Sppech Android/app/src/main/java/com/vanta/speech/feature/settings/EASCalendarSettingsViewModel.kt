package com.vanta.speech.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vanta.speech.core.eas.EASCalendarManager
import com.vanta.speech.core.eas.model.EASCalendarEvent
import com.vanta.speech.core.eas.model.EASError
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * ViewModel for EAS Calendar Settings screen
 */
@HiltViewModel
class EASCalendarSettingsViewModel @Inject constructor(
    private val manager: EASCalendarManager
) : ViewModel() {

    // Expose manager state
    val isConnected: StateFlow<Boolean> = manager.isConnected
    val isSyncing: StateFlow<Boolean> = manager.isSyncing
    val cachedEvents: StateFlow<List<EASCalendarEvent>> = manager.cachedEvents
    val lastError: StateFlow<EASError?> = manager.lastError
    val lastSyncDate: StateFlow<Long?> = manager.lastSyncDate

    // Form state
    private val _serverURL = MutableStateFlow("")
    val serverURL: StateFlow<String> = _serverURL.asStateFlow()

    private val _username = MutableStateFlow("")
    val username: StateFlow<String> = _username.asStateFlow()

    private val _password = MutableStateFlow("")
    val password: StateFlow<String> = _password.asStateFlow()

    private val _isConnecting = MutableStateFlow(false)
    val isConnecting: StateFlow<Boolean> = _isConnecting.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    // Computed
    val canConnect: Boolean
        get() = serverURL.value.isNotBlank() &&
                username.value.isNotBlank() &&
                password.value.isNotBlank()

    val upcomingEvents: List<EASCalendarEvent>
        get() = manager.upcomingEvents

    // Actions
    fun updateServerURL(value: String) {
        _serverURL.value = value
    }

    fun updateUsername(value: String) {
        _username.value = value
    }

    fun updatePassword(value: String) {
        _password.value = value
    }

    fun clearError() {
        _errorMessage.value = null
    }

    fun connect() {
        if (!canConnect || _isConnecting.value) return

        viewModelScope.launch {
            _isConnecting.value = true
            _errorMessage.value = null

            // Normalize server URL
            var normalizedURL = serverURL.value.trim()
            if (!normalizedURL.startsWith("http://") && !normalizedURL.startsWith("https://")) {
                normalizedURL = "https://$normalizedURL"
            }

            val success = manager.connect(
                serverURL = normalizedURL,
                username = username.value,
                password = password.value
            )

            _isConnecting.value = false

            if (success) {
                // Clear form
                _serverURL.value = ""
                _username.value = ""
                _password.value = ""

                // Start initial sync
                syncEvents()
            } else {
                _errorMessage.value = lastError.value?.errorDescription ?: "Ошибка подключения"
            }
        }
    }

    fun disconnect() {
        manager.disconnect()
    }

    fun syncEvents() {
        viewModelScope.launch {
            manager.syncEvents()
        }
    }
}
