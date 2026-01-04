package com.vanta.speech.core.ews

import android.util.Log
import com.vanta.speech.core.auth.SecurePreferencesManager
import com.vanta.speech.core.ews.api.EWSClient
import com.vanta.speech.core.ews.api.EWSXMLBuilder
import com.vanta.speech.core.ews.model.EWSConfig
import com.vanta.speech.core.ews.model.EWSCredentials
import com.vanta.speech.core.ews.model.EWSError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Calendar
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages EWS authentication and credential storage
 */
@Singleton
class EWSAuthManager @Inject constructor(
    private val securePrefs: SecurePreferencesManager
) {
    companion object {
        private const val TAG = "EWSAuthManager"
    }

    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    private val _credentials = MutableStateFlow<EWSCredentials?>(null)
    val credentials: StateFlow<EWSCredentials?> = _credentials.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    init {
        loadStoredCredentials()
    }

    /**
     * Authenticate with EWS server
     * @param serverURL Exchange server base URL (e.g., https://exchange.company.ru)
     * @param domain Windows domain (e.g., COMPANY)
     * @param username Username without domain (e.g., user)
     * @param password User password
     * @return True if authentication successful
     */
    suspend fun authenticate(
        serverURL: String,
        domain: String,
        username: String,
        password: String
    ): Boolean {
        val creds = EWSCredentials(
            serverURL = serverURL,
            domain = domain,
            username = username,
            password = password,
            email = null
        )

        return authenticate(creds)
    }

    /**
     * Authenticate with pre-built credentials
     */
    suspend fun authenticate(credentials: EWSCredentials): Boolean {
        _lastError.value = null

        return try {
            // Create client and test connection
            val client = EWSClient.fromCredentials(credentials)

            // Test with a simple FindItem request for today
            val calendar = Calendar.getInstance()
            val today = calendar.time
            calendar.add(Calendar.DAY_OF_MONTH, 1)
            val tomorrow = calendar.time

            val request = EWSXMLBuilder.buildFindItemRequest(
                startDate = today,
                endDate = tomorrow,
                maxEntries = 1
            )

            val response = client.sendRequest(
                soapAction = EWSConfig.SOAPAction.FIND_ITEM,
                body = request
            )

            // Check if response is valid (contains success indicator)
            val responseString = String(response, Charsets.UTF_8)
            if (!responseString.contains("ResponseClass=\"Success\"") &&
                !responseString.contains("NoError")) {
                throw EWSError.AuthenticationFailed
            }

            // Success - save credentials
            securePrefs.saveEWSCredentials(credentials)
            _credentials.value = credentials
            _isAuthenticated.value = true

            Log.d(TAG, "Authentication successful")
            true

        } catch (e: EWSError) {
            _lastError.value = e.message
            _isAuthenticated.value = false
            Log.e(TAG, "Authentication failed: ${e.message}")
            false
        } catch (e: Exception) {
            _lastError.value = e.message
            _isAuthenticated.value = false
            Log.e(TAG, "Authentication failed: ${e.message}")
            false
        }
    }

    /**
     * Sign out and clear credentials
     */
    fun signOut() {
        securePrefs.deleteEWSCredentials()
        _credentials.value = null
        _isAuthenticated.value = false
        _lastError.value = null
        Log.d(TAG, "Signed out")
    }

    /**
     * Get current credentials or throw if not authenticated
     */
    fun getCredentials(): EWSCredentials {
        return _credentials.value ?: throw EWSError.NotConfigured
    }

    /**
     * Create EWSClient with current credentials
     */
    fun createClient(): EWSClient {
        val creds = getCredentials()
        return EWSClient.fromCredentials(creds)
    }

    /**
     * Clear any errors
     */
    fun clearError() {
        _lastError.value = null
    }

    private fun loadStoredCredentials() {
        val stored = securePrefs.loadEWSCredentials()
        if (stored != null) {
            _credentials.value = stored
            _isAuthenticated.value = true
            Log.d(TAG, "Loaded stored credentials for ${stored.username}")
        }
    }
}
