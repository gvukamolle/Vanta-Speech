package com.vanta.speech.core.calendar.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Graph API response wrapper for events list
 */
@Serializable
data class GraphEventsResponse(
    val value: List<GraphEvent>,
    @SerialName("@odata.nextLink")
    val nextLink: String? = null,
    @SerialName("@odata.deltaLink")
    val deltaLink: String? = null
)

/**
 * Calendar event from Microsoft Graph API
 */
@Serializable
data class GraphEvent(
    val id: String,
    val subject: String? = null,
    val bodyPreview: String? = null,
    val start: GraphDateTime? = null,
    val end: GraphDateTime? = null,
    val location: GraphLocation? = null,
    val organizer: GraphAttendee? = null,
    val attendees: List<GraphAttendee>? = null,
    val isOrganizer: Boolean? = null,
    val iCalUId: String? = null,
    val webLink: String? = null
) {
    val startDate: Date?
        get() = start?.toDate()

    val endDate: Date?
        get() = end?.toDate()

    val formattedTimeRange: String
        get() {
            val formatter = SimpleDateFormat("HH:mm", Locale.getDefault())
            val startStr = startDate?.let { formatter.format(it) } ?: "--:--"
            val endStr = endDate?.let { formatter.format(it) } ?: "--:--"
            return "$startStr - $endStr"
        }

    val formattedDate: String
        get() {
            val formatter = SimpleDateFormat("dd MMMM yyyy", Locale("ru"))
            return startDate?.let { formatter.format(it) } ?: ""
        }
}

/**
 * Date-time with timezone from Graph API
 */
@Serializable
data class GraphDateTime(
    val dateTime: String,
    val timeZone: String
) {
    fun toDate(): Date? {
        return try {
            val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSSSSS", Locale.US)
            formatter.timeZone = TimeZone.getTimeZone(timeZone)
            formatter.parse(dateTime)
        } catch (e: Exception) {
            try {
                // Fallback for shorter format
                val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
                formatter.timeZone = TimeZone.getTimeZone(timeZone)
                formatter.parse(dateTime)
            } catch (e: Exception) {
                null
            }
        }
    }

    companion object {
        fun fromDate(date: Date, timeZone: String = "UTC"): GraphDateTime {
            val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            formatter.timeZone = TimeZone.getTimeZone(timeZone)
            return GraphDateTime(
                dateTime = formatter.format(date),
                timeZone = timeZone
            )
        }
    }
}

/**
 * Location from Graph API
 */
@Serializable
data class GraphLocation(
    val displayName: String? = null,
    val address: GraphAddress? = null
)

@Serializable
data class GraphAddress(
    val street: String? = null,
    val city: String? = null,
    val state: String? = null,
    val countryOrRegion: String? = null,
    val postalCode: String? = null
)

/**
 * Attendee/Organizer from Graph API
 */
@Serializable
data class GraphAttendee(
    val emailAddress: GraphEmailAddress,
    val type: String? = null, // "required", "optional", "resource"
    val status: GraphResponseStatus? = null
)

@Serializable
data class GraphEmailAddress(
    val name: String? = null,
    val address: String
)

@Serializable
data class GraphResponseStatus(
    val response: String? = null, // "none", "accepted", "declined", "tentativelyAccepted"
    val time: String? = null
)

/**
 * Create event request
 */
@Serializable
data class CreateEventRequest(
    val subject: String,
    val start: GraphDateTime,
    val end: GraphDateTime,
    val body: GraphEventBody? = null,
    val location: GraphLocation? = null,
    val attendees: List<GraphAttendee>? = null
) {
    constructor(
        subject: String,
        start: Date,
        end: Date,
        location: String? = null
    ) : this(
        subject = subject,
        start = GraphDateTime.fromDate(start),
        end = GraphDateTime.fromDate(end),
        location = location?.let { GraphLocation(displayName = it) }
    )
}

@Serializable
data class GraphEventBody(
    val contentType: String = "text", // "text" or "html"
    val content: String
)

/**
 * Update event request (partial update)
 */
@Serializable
data class UpdateEventRequest(
    var subject: String? = null,
    var start: GraphDateTime? = null,
    var end: GraphDateTime? = null,
    var body: GraphEventBody? = null,
    var location: GraphLocation? = null
)

/**
 * Meeting participant model for UI
 */
data class MeetingParticipant(
    val email: String,
    val name: String?,
    val role: ParticipantRole,
    val responseStatus: ParticipantResponseStatus
)

enum class ParticipantRole {
    ORGANIZER,
    REQUIRED,
    OPTIONAL
}

enum class ParticipantResponseStatus {
    ACCEPTED,
    DECLINED,
    TENTATIVE,
    NOT_RESPONDED
}

/**
 * User profile from Graph API
 */
@Serializable
data class UserProfile(
    val id: String,
    val displayName: String? = null,
    val mail: String? = null,
    val userPrincipalName: String? = null
) {
    val email: String
        get() = mail ?: userPrincipalName ?: "unknown"
}
