package com.vanta.speech.core.calendar

import android.util.Log
import com.vanta.speech.core.calendar.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Service for working with Microsoft Graph Calendar API
 * Android equivalent of iOS GraphCalendarService
 */
@Singleton
class GraphCalendarService @Inject constructor(
    private val authManager: MSALAuthManager
) {
    companion object {
        private const val TAG = "GraphCalendarService"
        private const val BASE_URL = "https://graph.microsoft.com/v1.0"
    }

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        isLenient = true
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    /**
     * Fetch calendar events for a date range
     */
    suspend fun fetchEvents(
        from: Date,
        to: Date,
        maxResults: Int = 50
    ): List<GraphEvent> = withContext(Dispatchers.IO) {
        val token = authManager.acquireTokenSilently()

        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")

        val startString = formatter.format(from)
        val endString = formatter.format(to)

        val url = buildString {
            append("$BASE_URL/me/calendarView")
            append("?startDateTime=$startString")
            append("&endDateTime=$endString")
            append("&\$select=id,subject,start,end,attendees,organizer,isOrganizer,iCalUId,bodyPreview,webLink,location")
            append("&\$orderby=start/dateTime")
            append("&\$top=$maxResults")
        }

        val request = Request.Builder()
            .url(url)
            .addHeader("Authorization", "Bearer $token")
            .addHeader("Content-Type", "application/json")
            .get()
            .build()

        val response = client.newCall(request).execute()

        if (!response.isSuccessful) {
            handleHttpError(response.code, response.body?.string())
        }

        val responseBody = response.body?.string() ?: throw GraphError.InvalidResponse
        val eventsResponse = json.decodeFromString<GraphEventsResponse>(responseBody)

        Log.d(TAG, "Fetched ${eventsResponse.value.size} events")
        eventsResponse.value
    }

    /**
     * Fetch today's events
     */
    suspend fun fetchTodayEvents(): List<GraphEvent> {
        val calendar = Calendar.getInstance()
        val startOfDay = calendar.apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.time

        val endOfDay = calendar.apply {
            add(Calendar.DAY_OF_MONTH, 1)
        }.time

        return fetchEvents(startOfDay, endOfDay)
    }

    /**
     * Fetch a specific event by ID
     */
    suspend fun fetchEvent(id: String): GraphEvent = withContext(Dispatchers.IO) {
        val token = authManager.acquireTokenSilently()

        val request = Request.Builder()
            .url("$BASE_URL/me/events/$id")
            .addHeader("Authorization", "Bearer $token")
            .addHeader("Content-Type", "application/json")
            .get()
            .build()

        val response = client.newCall(request).execute()

        if (!response.isSuccessful) {
            handleHttpError(response.code, response.body?.string())
        }

        val responseBody = response.body?.string() ?: throw GraphError.InvalidResponse
        json.decodeFromString<GraphEvent>(responseBody)
    }

    /**
     * Create a new event
     */
    suspend fun createEvent(event: CreateEventRequest): GraphEvent = withContext(Dispatchers.IO) {
        val token = authManager.acquireTokenSilently()

        val eventJson = json.encodeToString(event)

        val request = Request.Builder()
            .url("$BASE_URL/me/events")
            .addHeader("Authorization", "Bearer $token")
            .addHeader("Content-Type", "application/json")
            .post(eventJson.toRequestBody("application/json".toMediaType()))
            .build()

        val response = client.newCall(request).execute()

        if (!response.isSuccessful) {
            handleHttpError(response.code, response.body?.string())
        }

        val responseBody = response.body?.string() ?: throw GraphError.InvalidResponse
        json.decodeFromString<GraphEvent>(responseBody)
    }

    /**
     * Update an existing event
     */
    suspend fun updateEvent(id: String, changes: UpdateEventRequest): GraphEvent = withContext(Dispatchers.IO) {
        val token = authManager.acquireTokenSilently()

        val changesJson = json.encodeToString(changes)

        val request = Request.Builder()
            .url("$BASE_URL/me/events/$id")
            .addHeader("Authorization", "Bearer $token")
            .addHeader("Content-Type", "application/json")
            .patch(changesJson.toRequestBody("application/json".toMediaType()))
            .build()

        val response = client.newCall(request).execute()

        if (!response.isSuccessful) {
            handleHttpError(response.code, response.body?.string())
        }

        val responseBody = response.body?.string() ?: throw GraphError.InvalidResponse
        json.decodeFromString<GraphEvent>(responseBody)
    }

    /**
     * Delete an event
     */
    suspend fun deleteEvent(id: String): Unit = withContext(Dispatchers.IO) {
        val token = authManager.acquireTokenSilently()

        val request = Request.Builder()
            .url("$BASE_URL/me/events/$id")
            .addHeader("Authorization", "Bearer $token")
            .delete()
            .build()

        val response = client.newCall(request).execute()

        if (response.code != 204) {
            handleHttpError(response.code, response.body?.string())
        }
    }

    /**
     * Fetch user profile
     */
    suspend fun fetchUserProfile(): UserProfile = withContext(Dispatchers.IO) {
        val token = authManager.acquireTokenSilently()

        val request = Request.Builder()
            .url("$BASE_URL/me")
            .addHeader("Authorization", "Bearer $token")
            .addHeader("Content-Type", "application/json")
            .get()
            .build()

        val response = client.newCall(request).execute()

        if (!response.isSuccessful) {
            handleHttpError(response.code, response.body?.string())
        }

        val responseBody = response.body?.string() ?: throw GraphError.InvalidResponse
        json.decodeFromString<UserProfile>(responseBody)
    }

    /**
     * Get attendees for an event
     */
    suspend fun getAttendees(eventId: String): List<MeetingParticipant> {
        val event = fetchEvent(eventId)

        val participants = mutableListOf<MeetingParticipant>()

        // Add organizer
        event.organizer?.let { organizer ->
            participants.add(
                MeetingParticipant(
                    email = organizer.emailAddress.address,
                    name = organizer.emailAddress.name,
                    role = ParticipantRole.ORGANIZER,
                    responseStatus = ParticipantResponseStatus.ACCEPTED
                )
            )
        }

        // Add attendees
        event.attendees?.forEach { attendee ->
            val role = when (attendee.type) {
                "required" -> ParticipantRole.REQUIRED
                else -> ParticipantRole.OPTIONAL
            }

            val status = when (attendee.status?.response) {
                "accepted" -> ParticipantResponseStatus.ACCEPTED
                "declined" -> ParticipantResponseStatus.DECLINED
                "tentativelyAccepted" -> ParticipantResponseStatus.TENTATIVE
                else -> ParticipantResponseStatus.NOT_RESPONDED
            }

            participants.add(
                MeetingParticipant(
                    email = attendee.emailAddress.address,
                    name = attendee.emailAddress.name,
                    role = role,
                    responseStatus = status
                )
            )
        }

        return participants
    }

    private fun handleHttpError(statusCode: Int, body: String?): Nothing {
        Log.e(TAG, "HTTP Error $statusCode: $body")
        throw when (statusCode) {
            401 -> GraphError.Unauthorized
            403 -> GraphError.Forbidden
            404 -> GraphError.NotFound
            429 -> GraphError.RateLimited(60)
            else -> GraphError.HttpError(statusCode, body)
        }
    }
}

/**
 * Graph API Errors
 */
sealed class GraphError : Exception() {
    data object InvalidResponse : GraphError() {
        private fun readResolve(): Any = InvalidResponse
        override val message = "Неверный ответ сервера"
    }

    data object Unauthorized : GraphError() {
        private fun readResolve(): Any = Unauthorized
        override val message = "Не авторизован"
    }

    data object Forbidden : GraphError() {
        private fun readResolve(): Any = Forbidden
        override val message = "Доступ запрещён"
    }

    data object NotFound : GraphError() {
        private fun readResolve(): Any = NotFound
        override val message = "Не найдено"
    }

    data object DeleteFailed : GraphError() {
        private fun readResolve(): Any = DeleteFailed
        override val message = "Ошибка удаления"
    }

    data class RateLimited(val retryAfterSeconds: Int) : GraphError() {
        override val message = "Превышен лимит запросов. Повторите через $retryAfterSeconds сек."
    }

    data class HttpError(val statusCode: Int, val body: String?) : GraphError() {
        override val message = "HTTP ошибка $statusCode: $body"
    }
}
