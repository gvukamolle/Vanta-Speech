package com.vanta.speech.core.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.vanta.speech.core.auth.model.UserSession
import com.vanta.speech.core.eas.model.EASCredentials
import com.vanta.speech.core.eas.model.EASSyncState
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages secure storage of credentials using EncryptedSharedPreferences
 * Android equivalent of iOS KeychainManager
 */
@Singleton
class SecurePreferencesManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val PREFS_FILE_NAME = "vanta_secure_prefs"
        private const val KEY_USER_SESSION = "user_session"
        private const val KEY_EAS_CREDENTIALS = "eas_credentials"
        private const val KEY_EAS_DEVICE_ID = "eas_device_id"
        private const val KEY_EAS_SYNC_STATE = "eas_sync_state"
        private const val KEY_GOOGLE_REFRESH_TOKEN = "google_refresh_token"
        private const val KEY_GOOGLE_USER_INFO = "google_user_info"
    }

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val encryptedPrefs: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        EncryptedSharedPreferences.create(
            context,
            PREFS_FILE_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    // MARK: - Session Storage

    fun saveSession(session: UserSession): Boolean {
        return try {
            val sessionJson = json.encodeToString(session)
            encryptedPrefs.edit().putString(KEY_USER_SESSION, sessionJson).apply()
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun loadSession(): UserSession? {
        return try {
            val sessionJson = encryptedPrefs.getString(KEY_USER_SESSION, null) ?: return null
            json.decodeFromString<UserSession>(sessionJson)
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun deleteSession() {
        encryptedPrefs.edit().remove(KEY_USER_SESSION).apply()
    }

    fun hasSession(): Boolean = loadSession() != null

    // MARK: - EAS Credentials Storage

    fun saveEASCredentials(credentials: EASCredentials): Boolean {
        return try {
            val credentialsJson = json.encodeToString(credentials)
            encryptedPrefs.edit().putString(KEY_EAS_CREDENTIALS, credentialsJson).apply()
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun loadEASCredentials(): EASCredentials? {
        return try {
            val credentialsJson = encryptedPrefs.getString(KEY_EAS_CREDENTIALS, null) ?: return null
            json.decodeFromString<EASCredentials>(credentialsJson)
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun deleteEASCredentials() {
        encryptedPrefs.edit().remove(KEY_EAS_CREDENTIALS).apply()
    }

    fun hasEASCredentials(): Boolean = loadEASCredentials() != null

    // MARK: - EAS Device ID

    fun getOrCreateEASDeviceId(): String {
        val existing = encryptedPrefs.getString(KEY_EAS_DEVICE_ID, null)
        if (existing != null) {
            return existing
        }

        val deviceId = "VantaSpeech_${UUID.randomUUID()}"
        encryptedPrefs.edit().putString(KEY_EAS_DEVICE_ID, deviceId).apply()
        return deviceId
    }

    // MARK: - EAS Sync State

    fun saveEASSyncState(state: EASSyncState): Boolean {
        return try {
            val stateJson = json.encodeToString(state)
            encryptedPrefs.edit().putString(KEY_EAS_SYNC_STATE, stateJson).apply()
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun loadEASSyncState(): EASSyncState? {
        return try {
            val stateJson = encryptedPrefs.getString(KEY_EAS_SYNC_STATE, null) ?: return null
            json.decodeFromString<EASSyncState>(stateJson)
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun deleteEASSyncState() {
        encryptedPrefs.edit().remove(KEY_EAS_SYNC_STATE).apply()
    }

    fun clearAllEASData() {
        encryptedPrefs.edit()
            .remove(KEY_EAS_CREDENTIALS)
            .remove(KEY_EAS_DEVICE_ID)
            .remove(KEY_EAS_SYNC_STATE)
            .apply()
    }

    // MARK: - Google OAuth Storage (for future use)

    fun saveGoogleRefreshToken(token: String): Boolean {
        return try {
            encryptedPrefs.edit().putString(KEY_GOOGLE_REFRESH_TOKEN, token).apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    fun loadGoogleRefreshToken(): String? {
        return encryptedPrefs.getString(KEY_GOOGLE_REFRESH_TOKEN, null)
    }

    fun deleteGoogleRefreshToken() {
        encryptedPrefs.edit().remove(KEY_GOOGLE_REFRESH_TOKEN).apply()
    }

    fun saveGoogleUserInfo(email: String, displayName: String?, profileImageUrl: String?): Boolean {
        return try {
            val infoJson = json.encodeToString(
                mapOf(
                    "email" to email,
                    "displayName" to (displayName ?: ""),
                    "profileImageUrl" to (profileImageUrl ?: "")
                )
            )
            encryptedPrefs.edit().putString(KEY_GOOGLE_USER_INFO, infoJson).apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    fun loadGoogleUserInfo(): Triple<String, String?, String?>? {
        return try {
            val infoJson = encryptedPrefs.getString(KEY_GOOGLE_USER_INFO, null) ?: return null
            val map = json.decodeFromString<Map<String, String>>(infoJson)
            Triple(
                map["email"] ?: return null,
                map["displayName"]?.takeIf { it.isNotEmpty() },
                map["profileImageUrl"]?.takeIf { it.isNotEmpty() }
            )
        } catch (e: Exception) {
            null
        }
    }

    fun deleteGoogleCredentials() {
        encryptedPrefs.edit()
            .remove(KEY_GOOGLE_REFRESH_TOKEN)
            .remove(KEY_GOOGLE_USER_INFO)
            .apply()
    }

    fun hasGoogleCredentials(): Boolean = loadGoogleRefreshToken() != null

    // MARK: - Clear All

    fun clearAll() {
        encryptedPrefs.edit().clear().apply()
    }
}
