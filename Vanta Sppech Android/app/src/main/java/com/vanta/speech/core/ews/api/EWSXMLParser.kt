package com.vanta.speech.core.ews.api

import android.text.Html
import com.vanta.speech.core.ews.model.EWSAttendee
import com.vanta.speech.core.ews.model.EWSContact
import com.vanta.speech.core.ews.model.EWSError
import com.vanta.speech.core.ews.model.EWSEvent
import com.vanta.speech.core.ews.model.EWSMailboxType
import com.vanta.speech.core.ews.model.EWSResponseType
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.regex.Pattern

/**
 * Parses EWS XML responses
 */
object EWSXMLParser {

    /**
     * Parse CalendarItem elements from FindItem/GetItem response
     */
    fun parseCalendarItems(data: ByteArray): List<EWSEvent> {
        val xmlString = String(data, Charsets.UTF_8)

        // Check for errors
        if (xmlString.contains("ResponseClass=\"Error\"")) {
            val errorMessage = extractElement("MessageText", xmlString)
            throw EWSError.ServerError(errorMessage ?: "Unknown error")
        }

        val events = mutableListOf<EWSEvent>()

        // Find all CalendarItem blocks
        val calendarItemPattern = Pattern.compile(
            "<t:CalendarItem[^>]*>.*?</t:CalendarItem>",
            Pattern.DOTALL or Pattern.CASE_INSENSITIVE
        )
        val matcher = calendarItemPattern.matcher(xmlString)

        while (matcher.find()) {
            val itemXml = matcher.group()
            parseCalendarItem(itemXml)?.let { events.add(it) }
        }

        return events
    }

    private fun parseCalendarItem(xml: String): EWSEvent? {
        val itemId = extractAttribute("Id", "ItemId", xml) ?: return null
        val changeKey = extractAttribute("ChangeKey", "ItemId", xml) ?: return null

        val subject = extractElement("Subject", xml) ?: "(Без темы)"
        val startString = extractElement("Start", xml) ?: ""
        val endString = extractElement("End", xml) ?: ""
        val location = extractElement("Location", xml)
        val bodyHtml = extractElement("Body", xml)
        val isAllDayString = extractElement("IsAllDayEvent", xml) ?: "false"

        // Parse organizer
        val organizerEmail = extractNestedElement("Organizer", "EmailAddress", xml)
        val organizerName = extractNestedElement("Organizer", "Name", xml)

        // Parse attendees
        val requiredAttendees = parseAttendees(xml, "RequiredAttendees", isRequired = true)
        val optionalAttendees = parseAttendees(xml, "OptionalAttendees", isRequired = false)

        val startDate = parseISO8601(startString) ?: Date()
        val endDate = parseISO8601(endString) ?: Date()

        return EWSEvent(
            itemId = itemId,
            changeKey = changeKey,
            subject = subject,
            startDate = startDate,
            endDate = endDate,
            location = location,
            bodyHtml = bodyHtml,
            bodyText = bodyHtml?.let { stripHtmlTags(it) },
            attendees = requiredAttendees + optionalAttendees,
            organizerEmail = organizerEmail,
            organizerName = organizerName,
            isAllDay = isAllDayString.lowercase() == "true"
        )
    }

    private fun parseAttendees(xml: String, type: String, isRequired: Boolean): List<EWSAttendee> {
        val attendeesBlock = extractElement(type, xml) ?: return emptyList()

        val attendees = mutableListOf<EWSAttendee>()

        val attendeePattern = Pattern.compile(
            "<t:Attendee>.*?</t:Attendee>",
            Pattern.DOTALL
        )
        val matcher = attendeePattern.matcher(attendeesBlock)

        while (matcher.find()) {
            val attendeeXml = matcher.group()

            val email = extractElement("EmailAddress", attendeeXml)
            if (email != null) {
                val name = extractElement("Name", attendeeXml)
                val responseString = extractElement("ResponseType", attendeeXml) ?: "Unknown"
                val responseType = EWSResponseType.fromString(responseString)

                attendees.add(
                    EWSAttendee(
                        email = email,
                        name = name,
                        responseType = responseType,
                        isRequired = isRequired
                    )
                )
            }
        }

        return attendees
    }

    /**
     * Parse UpdateItem response to get new ChangeKey
     */
    fun parseUpdateItemResponse(data: ByteArray): String {
        val xmlString = String(data, Charsets.UTF_8)

        if (xmlString.contains("ResponseClass=\"Error\"")) {
            val errorCode = extractElement("ResponseCode", xmlString)
            when (errorCode) {
                "ErrorChangeKeyRequiredForWriteOperations",
                "ErrorIrresolvableConflict" -> throw EWSError.ChangeKeyMismatch
                "ErrorItemNotFound" -> throw EWSError.ItemNotFound
            }
            val message = extractElement("MessageText", xmlString) ?: "Unknown error"
            throw EWSError.ServerError(message)
        }

        return extractAttribute("ChangeKey", "ItemId", xmlString)
            ?: throw EWSError.ParseError("Could not find new ChangeKey in response")
    }

    /**
     * Parse CreateItem response to get new ItemId
     */
    fun parseCreateItemResponse(data: ByteArray): String {
        val xmlString = String(data, Charsets.UTF_8)

        if (xmlString.contains("ResponseClass=\"Error\"")) {
            val message = extractElement("MessageText", xmlString) ?: "Unknown error"
            throw EWSError.ServerError(message)
        }

        return extractAttribute("Id", "ItemId", xmlString)
            ?: throw EWSError.ParseError("Could not find ItemId in response")
    }

    /**
     * Parse ResolveNames response
     */
    fun parseResolveNamesResponse(data: ByteArray): List<EWSContact> {
        val xmlString = String(data, Charsets.UTF_8)

        val contacts = mutableListOf<EWSContact>()

        val resolutionPattern = Pattern.compile(
            "<t:Resolution>.*?</t:Resolution>",
            Pattern.DOTALL
        )
        val matcher = resolutionPattern.matcher(xmlString)

        while (matcher.find()) {
            val resolutionXml = matcher.group()

            val email = extractNestedElement("Mailbox", "EmailAddress", resolutionXml)
            if (email != null) {
                val name = extractNestedElement("Mailbox", "Name", resolutionXml)
                    ?: extractElement("DisplayName", resolutionXml)
                    ?: email
                val mailboxTypeString = extractNestedElement("Mailbox", "MailboxType", resolutionXml) ?: "Mailbox"
                val mailboxType = EWSMailboxType.fromString(mailboxTypeString)
                val department = extractElement("Department", resolutionXml)
                val jobTitle = extractElement("JobTitle", resolutionXml)

                contacts.add(
                    EWSContact(
                        email = email,
                        displayName = name,
                        mailboxType = mailboxType,
                        department = department,
                        jobTitle = jobTitle
                    )
                )
            }
        }

        return contacts
    }

    // MARK: - XML Helpers

    private fun extractElement(name: String, xml: String): String? {
        // Match both t: and m: prefixed elements, or no prefix
        val patterns = listOf(
            "<t:$name[^>]*>(.*?)</t:$name>",
            "<m:$name[^>]*>(.*?)</m:$name>",
            "<$name[^>]*>(.*?)</$name>"
        )

        for (patternStr in patterns) {
            val pattern = Pattern.compile(patternStr, Pattern.DOTALL)
            val matcher = pattern.matcher(xml)
            if (matcher.find()) {
                return matcher.group(1)?.trim()
            }
        }
        return null
    }

    private fun extractNestedElement(outer: String, inner: String, xml: String): String? {
        val outerContent = extractElement(outer, xml) ?: return null
        return extractElement(inner, outerContent)
    }

    private fun extractAttribute(attr: String, element: String, xml: String): String? {
        val patterns = listOf(
            "<t:$element[^>]*$attr=\"([^\"]+)\"",
            "<m:$element[^>]*$attr=\"([^\"]+)\"",
            "<$element[^>]*$attr=\"([^\"]+)\""
        )

        for (patternStr in patterns) {
            val pattern = Pattern.compile(patternStr)
            val matcher = pattern.matcher(xml)
            if (matcher.find()) {
                return matcher.group(1)
            }
        }
        return null
    }

    private fun parseISO8601(dateString: String): Date? {
        if (dateString.isBlank()) return null

        // Try different ISO 8601 formats
        val formats = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd'T'HH:mm:ss"
        )

        for (format in formats) {
            try {
                val formatter = SimpleDateFormat(format, Locale.US)
                formatter.timeZone = TimeZone.getTimeZone("UTC")
                return formatter.parse(dateString)
            } catch (_: Exception) {
                // Try next format
            }
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun stripHtmlTags(html: String): String {
        return try {
            Html.fromHtml(html, Html.FROM_HTML_MODE_LEGACY).toString()
        } catch (_: Exception) {
            // Fallback: simple tag removal
            html.replace(Regex("<[^>]+>"), "")
        }
    }
}
