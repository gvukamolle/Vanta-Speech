package com.vanta.speech.core.auth

import com.vanta.speech.core.auth.model.UserSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages authentication state across the app
 * Android equivalent of iOS AuthenticationManager
 */
@Singleton
class AuthenticationManager @Inject constructor(
    private val ldapAuthService: LDAPAuthService,
    private val securePrefs: SecurePreferencesManager
) {
    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    private val _currentSession = MutableStateFlow<UserSession?>(null)
    val currentSession: StateFlow<UserSession?> = _currentSession.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        loadStoredSession()
    }

    /**
     * Attempt to log in with username and password
     */
    suspend fun login(username: String, password: String) {
        if (username.isBlank() || password.isBlank()) {
            _error.value = "Введите логин и пароль"
            return
        }

        _isLoading.value = true
        _error.value = null

        val result = ldapAuthService.authenticate(username, password)

        result.fold(
            onSuccess = { session ->
                securePrefs.saveSession(session)
                _currentSession.value = session
                _isAuthenticated.value = true
                _isLoading.value = false
            },
            onFailure = { exception ->
                _error.value = when (exception) {
                    is LDAPAuthService.AuthError -> exception.message
                    else -> "Ошибка аутентификации: ${exception.message}"
                }
                _isLoading.value = false
            }
        )
    }

    /**
     * Log out the current user
     */
    fun logout() {
        securePrefs.deleteSession()
        _currentSession.value = null
        _isAuthenticated.value = false
        _error.value = null
    }

    /**
     * Skip authentication for testing (temporary)
     */
    fun skipAuthentication() {
        val testSession = UserSession(
            username = "test_user",
            displayName = "Тестовый пользователь",
            email = null
        )
        securePrefs.saveSession(testSession)
        _currentSession.value = testSession
        _isAuthenticated.value = true
    }

    /**
     * Clear current error
     */
    fun clearError() {
        _error.value = null
    }

    /**
     * Load stored session on app start
     */
    private fun loadStoredSession() {
        val session = securePrefs.loadSession()
        if (session != null) {
            _currentSession.value = session
            _isAuthenticated.value = true
        }
    }
}
