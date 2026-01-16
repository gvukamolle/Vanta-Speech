package com.vanta.speech.core.eas.model

import android.util.Base64
import kotlinx.serialization.Serializable
import java.util.UUID

/**
 * Credentials for Exchange ActiveSync authentication
 */
@Serializable
data class EASCredentials(
    /** Server URL (e.g., "https://mail.company.com") */
    val serverURL: String,

    /** Username in format "DOMAIN\\user" or "user@company.com" */
    val username: String,

    /** User's password */
    val password: String,

    /** Unique device identifier, persisted across sessions */
    val deviceId: String = "VantaSpeech_${UUID.randomUUID()}"
) {
    companion object {
        const val DEVICE_TYPE = "VantaSpeech"
        const val PROTOCOL_VERSION = "14.1"
    }

    /**
     * Base64-encoded Basic Auth header value
     */
    val basicAuthHeader: String
        get() {
            val credentials = "$username:$password"
            val encoded = Base64.encodeToString(
                credentials.toByteArray(Charsets.UTF_8),
                Base64.NO_WRAP
            )
            return "Basic $encoded"
        }

    /**
     * Full ActiveSync endpoint URL
     */
    val activeSyncURL: String
        get() = "${serverURL.trimEnd('/')}/Microsoft-Server-ActiveSync"

    /**
     * Username without domain prefix (for URL query parameter)
     */
    val usernameForQuery: String
        get() = if (username.contains("\\")) {
            username.substringAfter("\\")
        } else {
            username
        }

    /**
     * Build full URL for EAS command
     */
    fun buildURL(command: String): String {
        return "$activeSyncURL?Cmd=$command&User=$usernameForQuery&DeviceId=$deviceId&DeviceType=$DEVICE_TYPE"
    }
}
