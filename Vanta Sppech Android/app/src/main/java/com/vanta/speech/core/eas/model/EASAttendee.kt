package com.vanta.speech.core.eas.model

import kotlinx.serialization.Serializable

/**
 * Meeting attendee from EAS calendar event
 */
@Serializable
data class EASAttendee(
    /** Email address */
    val email: String,

    /** Display name */
    val name: String,

    /** Attendee type (required, optional, resource) */
    val type: AttendeeType = AttendeeType.REQUIRED,

    /** Response status (accepted, declined, etc.) */
    val status: ResponseStatus? = null
)

/**
 * Attendee type values from EAS protocol
 */
enum class AttendeeType(val value: Int) {
    REQUIRED(1),
    OPTIONAL(2),
    RESOURCE(3);

    val displayName: String
        get() = when (this) {
            REQUIRED -> "Обязательный"
            OPTIONAL -> "Необязательный"
            RESOURCE -> "Ресурс"
        }

    companion object {
        fun fromValue(value: Int): AttendeeType {
            return entries.find { it.value == value } ?: REQUIRED
        }
    }
}

/**
 * Response status values from EAS protocol
 */
enum class ResponseStatus(val value: Int) {
    NONE(0),
    ORGANIZER(1),
    TENTATIVE(2),
    ACCEPTED(3),
    DECLINED(4),
    NOT_RESPONDED(5);

    val displayName: String
        get() = when (this) {
            NONE -> "Нет ответа"
            ORGANIZER -> "Организатор"
            TENTATIVE -> "Возможно"
            ACCEPTED -> "Принято"
            DECLINED -> "Отклонено"
            NOT_RESPONDED -> "Не ответил"
        }

    val iconName: String
        get() = when (this) {
            NONE, NOT_RESPONDED -> "help_outline"
            ORGANIZER -> "star"
            TENTATIVE -> "help"
            ACCEPTED -> "check_circle"
            DECLINED -> "cancel"
        }

    companion object {
        fun fromValue(value: Int): ResponseStatus? {
            return entries.find { it.value == value }
        }
    }
}
