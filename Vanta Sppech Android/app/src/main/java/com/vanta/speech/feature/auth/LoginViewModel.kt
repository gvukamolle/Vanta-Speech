package com.vanta.speech.feature.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vanta.speech.core.auth.AuthenticationManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authManager: AuthenticationManager
) : ViewModel() {

    private val _username = MutableStateFlow("")
    val username: StateFlow<String> = _username.asStateFlow()

    private val _password = MutableStateFlow("")
    val password: StateFlow<String> = _password.asStateFlow()

    val isLoading = authManager.isLoading
    val error = authManager.error
    val isAuthenticated = authManager.isAuthenticated

    fun onUsernameChange(value: String) {
        _username.value = value
        authManager.clearError()
    }

    fun onPasswordChange(value: String) {
        _password.value = value
        authManager.clearError()
    }

    fun login() {
        viewModelScope.launch {
            authManager.login(_username.value, _password.value)
        }
    }

    fun skipAuthentication() {
        authManager.skipAuthentication()
    }
}
