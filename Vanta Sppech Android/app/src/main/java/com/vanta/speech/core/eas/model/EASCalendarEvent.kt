package com.vanta.speech.core.eas.model

import kotlinx.serialization.Serializable
import java.text.SimpleDateFormat
import java.util.*

/**
 * Calendar event from EAS Sync response
 */
@Serializable
data class EASCalendarEvent(
    /** Server-assigned event ID */
    val id: String,

    /** Event subject/title */
    val subject: String,

    /** Start time (epoch millis) */
    val startTimeMillis: Long,

    /** End time (epoch millis) */
    val endTimeMillis: Long,

    /** Location (optional) */
    val location: String? = null,

    /** Body content (HTML) */
    val body: String? = null,

    /** Meeting organizer */
    val organizer: EASAttendee? = null,

    /** List of attendees */
    val attendees: List<EASAttendee> = emptyList(),

    /** Whether this is an all-day event */
    val isAllDay: Boolean = false,

    /** Exceptions (modified occurrences) for recurring events */
    val exceptions: List<EASException>? = null,

    /** Client-generated ID for new events */
    val clientId: String? = null
) {
    /** Start time as Date */
    val startTime: Date
        get() = Date(startTimeMillis)

    /** End time as Date */
    val endTime: Date
        get() = Date(endTimeMillis)

    /** Duration in minutes */
    val durationMinutes: Int
        get() = ((endTimeMillis - startTimeMillis) / 60000).toInt()

    /** Formatted duration string */
    val formattedDuration: String
        get() {
            val minutes = durationMinutes
            return when {
                minutes < 60 -> "$minutes мин"
                minutes % 60 == 0 -> "${minutes / 60} ч"
                else -> "${minutes / 60} ч ${minutes % 60} мин"
            }
        }

    /** Attendees excluding resources (rooms, equipment) */
    val humanAttendees: List<EASAttendee>
        get() = attendees.filter { it.type != AttendeeType.RESOURCE }

    /** Email list for all human attendees */
    val attendeeEmails: List<String>
        get() = humanAttendees.map { it.email }

    /**
     * Convert to EAS XML format for Sync Add command
     */
    fun toEASXml(): String {
        val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        val sb = StringBuilder()

        sb.append("<calendar:Subject>${subject.xmlEscape()}</calendar:Subject>")
        sb.append("<calendar:StartTime>${dateFormat.format(startTime)}</calendar:StartTime>")
        sb.append("<calendar:EndTime>${dateFormat.format(endTime)}</calendar:EndTime>")
        sb.append("<calendar:AllDayEvent>${if (isAllDay) "1" else "0"}</calendar:AllDayEvent>")

        location?.let {
            sb.append("<calendar:Location>${it.xmlEscape()}</calendar:Location>")
        }

        body?.let {
            sb.append("""
                <Body xmlns="AirSyncBase">
                    <Type>2</Type>
                    <Data>${it.xmlEscape()}</Data>
                </Body>
            """.trimIndent())
        }

        if (attendees.isNotEmpty()) {
            sb.append("<calendar:Attendees>")
            attendees.forEach { attendee ->
                sb.append("""
                    <calendar:Attendee>
                        <calendar:Email>${attendee.email.xmlEscape()}</calendar:Email>
                        <calendar:Name>${attendee.name.xmlEscape()}</calendar:Name>
                        <calendar:AttendeeType>${attendee.type.value}</calendar:AttendeeType>
                    </calendar:Attendee>
                """.trimIndent())
            }
            sb.append("</calendar:Attendees>")
        }

        return sb.toString()
    }

    companion object {
        /**
         * Create a new event for meeting summary
         */
        fun createMeetingSummary(
            originalEvent: EASCalendarEvent,
            summaryHtml: String,
            startTime: Date = Date(System.currentTimeMillis() + 3600000), // 1 hour from now
            durationMinutes: Int = 15
        ): EASCalendarEvent {
            return EASCalendarEvent(
                id = "",
                subject = "Meeting Summary: ${originalEvent.subject}",
                startTimeMillis = startTime.time,
                endTimeMillis = startTime.time + (durationMinutes * 60000L),
                location = null,
                body = summaryHtml,
                organizer = null,
                attendees = originalEvent.humanAttendees,
                isAllDay = false,
                clientId = UUID.randomUUID().toString()
            )
        }
    }
}

/**
 * Escape special XML characters
 */
private fun String.xmlEscape(): String {
    return this
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("'", "&apos;")
        .replace("\"", "&quot;")
}
