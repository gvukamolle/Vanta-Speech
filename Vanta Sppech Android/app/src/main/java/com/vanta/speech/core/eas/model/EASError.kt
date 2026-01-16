package com.vanta.speech.core.eas.model

/**
 * Errors that can occur during EAS operations
 */
sealed class EASError : Exception() {

    /** No network connection available */
    data object Offline : EASError()

    /** No credentials stored */
    data object NoCredentials : EASError()

    /** Invalid or expired credentials (HTTP 401) */
    data object AuthenticationFailed : EASError()

    /** Access denied by server (HTTP 403) */
    data object AccessDenied : EASError()

    /** Server temporarily unavailable (HTTP 503) */
    data object ServerUnavailable : EASError()

    /** Calendar folder not found in FolderSync response */
    data object CalendarFolderNotFound : EASError()

    /** Failed to parse server response */
    data class ParseError(val details: String) : EASError()

    /** Network error during request */
    data class NetworkError(val details: String) : EASError()

    /** HTTP error with status code */
    data class ServerError(val statusCode: Int, val serverMessage: String?) : EASError()

    /** WBXML encoding/decoding error */
    data class WBXMLError(val details: String) : EASError()

    /** Invalid server URL */
    data object InvalidServerURL : EASError()

    /** Unknown error */
    data class Unknown(val details: String) : EASError()

    /**
     * User-friendly error description in Russian
     */
    val errorDescription: String
        get() = when (this) {
            is Offline -> "Нет подключения к сети. Проверьте интернет-соединение."
            is NoCredentials -> "Требуется вход в аккаунт"
            is AuthenticationFailed -> "Неверный логин или пароль"
            is AccessDenied -> "Доступ запрещён. Обратитесь к администратору."
            is ServerUnavailable -> "Сервер временно недоступен. Попробуйте позже."
            is CalendarFolderNotFound -> "Календарь не найден. Обратитесь к администратору."
            is ParseError -> "Ошибка обработки данных: $details"
            is NetworkError -> "Ошибка сети: $details"
            is ServerError -> if (serverMessage != null) {
                "Ошибка сервера ($statusCode): $serverMessage"
            } else {
                "Ошибка сервера: $statusCode"
            }
            is WBXMLError -> "Ошибка формата данных: $details"
            is InvalidServerURL -> "Неверный адрес сервера"
            is Unknown -> "Произошла ошибка: $details"
        }

    /**
     * Suggested action to recover from error
     */
    val recoverySuggestion: RecoveryAction
        get() = when (this) {
            is Offline, is NetworkError, is ServerUnavailable, is ParseError, is WBXMLError ->
                RecoveryAction.RETRY
            is NoCredentials, is AuthenticationFailed ->
                RecoveryAction.LOGIN
            is AccessDenied, is CalendarFolderNotFound ->
                RecoveryAction.CONTACT_ADMIN
            is ServerError -> when (statusCode) {
                401 -> RecoveryAction.LOGIN
                in 500..599 -> RecoveryAction.RETRY
                else -> RecoveryAction.CONTACT_ADMIN
            }
            is InvalidServerURL -> RecoveryAction.LOGIN
            is Unknown -> RecoveryAction.RETRY
        }

    /**
     * Whether credentials should be cleared for this error
     */
    val shouldClearCredentials: Boolean
        get() = when (this) {
            is AuthenticationFailed -> true
            is ServerError -> statusCode == 401
            else -> false
        }
}

/**
 * Suggested recovery action for errors
 */
enum class RecoveryAction {
    /** User should retry the operation */
    RETRY,

    /** User should re-authenticate */
    LOGIN,

    /** User should contact system administrator */
    CONTACT_ADMIN
}
