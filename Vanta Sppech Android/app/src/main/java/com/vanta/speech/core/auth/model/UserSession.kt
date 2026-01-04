package com.vanta.speech.core.auth.model

import kotlinx.serialization.Serializable
import java.util.Date

/**
 * Represents an authenticated user session
 */
@Serializable
data class UserSession(
    val username: String,
    val displayName: String? = null,
    val email: String? = null,
    val authenticatedAt: Long = System.currentTimeMillis()
) {
    val formattedAuthDate: String
        get() = java.text.SimpleDateFormat("dd.MM.yyyy HH:mm", java.util.Locale.getDefault())
            .format(Date(authenticatedAt))
}
