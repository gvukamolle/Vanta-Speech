package com.vanta.speech.feature.settings

import androidx.lifecycle.ViewModel
import com.vanta.speech.core.auth.AuthenticationManager
import com.vanta.speech.core.auth.model.UserSession
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val authManager: AuthenticationManager
) : ViewModel() {

    val currentSession: StateFlow<UserSession?> = authManager.currentSession

    fun logout() {
        authManager.logout()
    }
}
