package com.vanta.speech.core.ews

import com.vanta.speech.core.ews.api.EWSClient
import com.vanta.speech.core.ews.api.EWSXMLBuilder
import com.vanta.speech.core.ews.api.EWSXMLParser
import com.vanta.speech.core.ews.model.EWSConfig
import com.vanta.speech.core.ews.model.EWSContact
import com.vanta.speech.core.ews.model.EWSError
import com.vanta.speech.core.ews.model.EWSEvent
import com.vanta.speech.core.ews.model.EWSNewEmail
import com.vanta.speech.core.ews.model.EWSNewEvent
import java.util.Calendar
import java.util.Date

/**
 * Service layer for EWS calendar operations
 */
class EWSCalendarService(
    private val client: EWSClient
) {

    // MARK: - Find Events

    /**
     * Fetch calendar events for a date range
     */
    suspend fun findEvents(
        from: Date,
        to: Date,
        maxEntries: Int = 100
    ): List<EWSEvent> {
        val request = EWSXMLBuilder.buildFindItemRequest(
            startDate = from,
            endDate = to,
            maxEntries = maxEntries
        )

        val response = client.sendRequest(
            soapAction = EWSConfig.SOAPAction.FIND_ITEM,
            body = request
        )

        return EWSXMLParser.parseCalendarItems(response)
    }

    /**
     * Fetch events for today
     */
    suspend fun findTodayEvents(): List<EWSEvent> {
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startOfDay = calendar.time

        calendar.add(Calendar.DAY_OF_MONTH, 1)
        val endOfDay = calendar.time

        return findEvents(from = startOfDay, to = endOfDay)
    }

    // MARK: - Get Event Details

    /**
     * Get detailed event info including all attendees
     */
    suspend fun getEventDetails(itemId: String, changeKey: String): EWSEvent {
        val request = EWSXMLBuilder.buildGetItemRequest(
            itemId = itemId,
            changeKey = changeKey
        )

        val response = client.sendRequest(
            soapAction = EWSConfig.SOAPAction.GET_ITEM,
            body = request
        )

        val events = EWSXMLParser.parseCalendarItems(response)
        return events.firstOrNull() ?: throw EWSError.ItemNotFound
    }

    // MARK: - Update Event

    /**
     * Update event body (add/replace summary)
     */
    suspend fun updateEventBody(
        itemId: String,
        changeKey: String,
        bodyHtml: String,
        notifyAttendees: Boolean = false
    ): String {
        val request = EWSXMLBuilder.buildUpdateItemBodyRequest(
            itemId = itemId,
            changeKey = changeKey,
            bodyHtml = bodyHtml,
            notifyAttendees = notifyAttendees
        )

        val response = client.sendRequest(
            soapAction = EWSConfig.SOAPAction.UPDATE_ITEM,
            body = request
        )

        // Parse new ChangeKey from response
        return EWSXMLParser.parseUpdateItemResponse(response)
    }

    /**
     * Update event subject
     */
    suspend fun updateEventSubject(
        itemId: String,
        changeKey: String,
        subject: String,
        notifyAttendees: Boolean = false
    ): String {
        val request = EWSXMLBuilder.buildUpdateItemSubjectRequest(
            itemId = itemId,
            changeKey = changeKey,
            subject = subject,
            notifyAttendees = notifyAttendees
        )

        val response = client.sendRequest(
            soapAction = EWSConfig.SOAPAction.UPDATE_ITEM,
            body = request
        )

        return EWSXMLParser.parseUpdateItemResponse(response)
    }

    // MARK: - Create Event

    /**
     * Create a new calendar event
     */
    suspend fun createEvent(event: EWSNewEvent): String {
        val request = EWSXMLBuilder.buildCreateCalendarItemRequest(event)

        val response = client.sendRequest(
            soapAction = EWSConfig.SOAPAction.CREATE_ITEM,
            body = request
        )

        return EWSXMLParser.parseCreateItemResponse(response)
    }

    // MARK: - Send Email

    /**
     * Send an email to recipients
     */
    suspend fun sendEmail(email: EWSNewEmail) {
        val request = EWSXMLBuilder.buildCreateMessageRequest(email)

        client.sendRequest(
            soapAction = EWSConfig.SOAPAction.CREATE_ITEM,
            body = request
        )
    }

    // MARK: - Resolve Names (Contact Search)

    /**
     * Search for contacts by name or email
     */
    suspend fun resolveNames(query: String): List<EWSContact> {
        val request = EWSXMLBuilder.buildResolveNamesRequest(query = query)

        val response = client.sendRequest(
            soapAction = EWSConfig.SOAPAction.RESOLVE_NAMES,
            body = request
        )

        return EWSXMLParser.parseResolveNamesResponse(response)
    }
}
