package com.vanta.speech.core.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.vanta.speech.core.auth.model.UserSession
import com.vanta.speech.core.ews.model.EWSCredentials
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
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
        private const val KEY_EWS_CREDENTIALS = "ews_credentials"
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

    // MARK: - EWS Credentials Storage

    fun saveEWSCredentials(credentials: EWSCredentials): Boolean {
        return try {
            val credentialsJson = json.encodeToString(credentials)
            encryptedPrefs.edit().putString(KEY_EWS_CREDENTIALS, credentialsJson).apply()
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun loadEWSCredentials(): EWSCredentials? {
        return try {
            val credentialsJson = encryptedPrefs.getString(KEY_EWS_CREDENTIALS, null) ?: return null
            json.decodeFromString<EWSCredentials>(credentialsJson)
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun deleteEWSCredentials() {
        encryptedPrefs.edit().remove(KEY_EWS_CREDENTIALS).apply()
    }

    fun hasEWSCredentials(): Boolean = loadEWSCredentials() != null

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
