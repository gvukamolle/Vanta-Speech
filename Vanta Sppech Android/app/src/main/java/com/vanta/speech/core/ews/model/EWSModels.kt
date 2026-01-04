package com.vanta.speech.core.ews.model

import kotlinx.serialization.Serializable
import java.util.Date

/**
 * Credentials for Exchange Web Services authentication
 */
@Serializable
data class EWSCredentials(
    val serverURL: String,      // e.g., "https://exchange.company.ru"
    val domain: String,         // e.g., "COMPANY"
    val username: String,       // e.g., "user" (without domain prefix)
    val password: String,       // stored encrypted
    val email: String? = null   // discovered or user-entered
) {
    /**
     * Full username in DOMAIN\user format for NTLM
     */
    val ntlmUsername: String
        get() = "$domain\\$username"

    /**
     * Full EWS endpoint URL
     */
    val ewsEndpoint: String
        get() {
            val baseURL = serverURL.trimEnd('/')
            return "$baseURL${EWSConfig.ENDPOINT_PATH}"
        }
}

/**
 * Represents a calendar event from Exchange
 */
data class EWSEvent(
    val itemId: String,
    val changeKey: String,       // Required for UpdateItem operations
    val subject: String,
    val startDate: Date,
    val endDate: Date,
    val location: String? = null,
    val bodyHtml: String? = null,
    val bodyText: String? = null,
    val attendees: List<EWSAttendee> = emptyList(),
    val organizerEmail: String? = null,
    val organizerName: String? = null,
    val isAllDay: Boolean = false
) {
    /**
     * Duration in minutes
     */
    val durationMinutes: Int
        get() = ((endDate.time - startDate.time) / 60000).toInt()
}

/**
 * Represents a meeting attendee
 */
data class EWSAttendee(
    val email: String,
    val name: String? = null,
    val responseType: EWSResponseType = EWSResponseType.UNKNOWN,
    val isRequired: Boolean = true
) {
    val displayName: String
        get() = name ?: email
}

/**
 * Attendee response status
 */
enum class EWSResponseType(val value: String) {
    UNKNOWN("Unknown"),
    ORGANIZER("Organizer"),
    TENTATIVE("Tentative"),
    ACCEPT("Accept"),
    DECLINE("Decline"),
    NO_RESPONSE_RECEIVED("NoResponseReceived");

    val displayText: String
        get() = when (this) {
            UNKNOWN -> "Неизвестно"
            ORGANIZER -> "Организатор"
            TENTATIVE -> "Под вопросом"
            ACCEPT -> "Принял"
            DECLINE -> "Отклонил"
            NO_RESPONSE_RECEIVED -> "Нет ответа"
        }

    companion object {
        fun fromString(value: String): EWSResponseType =
            entries.find { it.value.equals(value, ignoreCase = true) } ?: UNKNOWN
    }
}

/**
 * Contact from ResolveNames operation (for autocomplete)
 */
data class EWSContact(
    val email: String,
    val displayName: String,
    val mailboxType: EWSMailboxType = EWSMailboxType.MAILBOX,
    val department: String? = null,
    val jobTitle: String? = null
)

/**
 * Mailbox type from Exchange
 */
enum class EWSMailboxType(val value: String) {
    MAILBOX("Mailbox"),
    PUBLIC_DL("PublicDL"),
    PRIVATE_DL("PrivateDL"),
    CONTACT("Contact"),
    PUBLIC_FOLDER("PublicFolder"),
    UNKNOWN("Unknown");

    val isDistributionList: Boolean
        get() = this == PUBLIC_DL || this == PRIVATE_DL

    companion object {
        fun fromString(value: String): EWSMailboxType =
            entries.find { it.value.equals(value, ignoreCase = true) } ?: UNKNOWN
    }
}

/**
 * Data for creating a new calendar event
 */
data class EWSNewEvent(
    val subject: String,
    val bodyHtml: String? = null,
    val startDate: Date,
    val endDate: Date,
    val location: String? = null,
    val requiredAttendees: List<String> = emptyList(), // emails
    val optionalAttendees: List<String> = emptyList(), // emails
    val isAllDay: Boolean = false
)

/**
 * Data for sending an email
 */
data class EWSNewEmail(
    val toRecipients: List<String>,  // emails
    val ccRecipients: List<String> = emptyList(),  // emails
    val subject: String,
    val bodyHtml: String,
    val saveToSentItems: Boolean = true
)

/**
 * EWS Configuration
 */
object EWSConfig {
    // Exchange Server version for SOAP RequestServerVersion
    const val EXCHANGE_VERSION = "Exchange2019"

    // Default EWS endpoint path (appended to server URL)
    const val ENDPOINT_PATH = "/EWS/Exchange.asmx"

    // Request timeout in milliseconds
    const val REQUEST_TIMEOUT_MS = 30000L

    // SOAP namespaces
    object Namespace {
        const val SOAP = "http://schemas.xmlsoap.org/soap/envelope/"
        const val TYPES = "http://schemas.microsoft.com/exchange/services/2006/types"
        const val MESSAGES = "http://schemas.microsoft.com/exchange/services/2006/messages"
    }

    // SOAP Actions
    object SOAPAction {
        const val FIND_ITEM = "http://schemas.microsoft.com/exchange/services/2006/messages/FindItem"
        const val GET_ITEM = "http://schemas.microsoft.com/exchange/services/2006/messages/GetItem"
        const val UPDATE_ITEM = "http://schemas.microsoft.com/exchange/services/2006/messages/UpdateItem"
        const val CREATE_ITEM = "http://schemas.microsoft.com/exchange/services/2006/messages/CreateItem"
        const val RESOLVE_NAMES = "http://schemas.microsoft.com/exchange/services/2006/messages/ResolveNames"
    }
}

/**
 * Errors that can occur during EWS operations
 */
sealed class EWSError : Exception() {
    data object NotConfigured : EWSError() {
        private fun readResolve(): Any = NotConfigured
        override val message = "Exchange сервер не настроен"
    }

    data object InvalidServerURL : EWSError() {
        private fun readResolve(): Any = InvalidServerURL
        override val message = "Неверный URL сервера Exchange"
    }

    data object AuthenticationFailed : EWSError() {
        private fun readResolve(): Any = AuthenticationFailed
        override val message = "Ошибка аутентификации. Проверьте логин и пароль."
    }

    data class ServerError(val errorMessage: String) : EWSError() {
        override val message = "Ошибка сервера: $errorMessage"
    }

    data class ParseError(val detail: String) : EWSError() {
        override val message = "Ошибка разбора ответа: $detail"
    }

    data class NetworkError(override val cause: Throwable) : EWSError() {
        override val message = "Сетевая ошибка: ${cause.message}"
    }

    data object ItemNotFound : EWSError() {
        private fun readResolve(): Any = ItemNotFound
        override val message = "Элемент не найден"
    }

    data object ChangeKeyMismatch : EWSError() {
        private fun readResolve(): Any = ChangeKeyMismatch
        override val message = "Элемент был изменён. Обновите данные и попробуйте снова."
    }

    data object AccessDenied : EWSError() {
        private fun readResolve(): Any = AccessDenied
        override val message = "Доступ запрещён"
    }

    data object Throttled : EWSError() {
        private fun readResolve(): Any = Throttled
        override val message = "Превышен лимит запросов. Попробуйте позже."
    }

    data class SOAPFault(val fault: String) : EWSError() {
        override val message = "Ошибка Exchange: $fault"
    }
}
