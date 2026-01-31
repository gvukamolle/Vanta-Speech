package com.vanta.speech.core.eas.api

import com.vanta.speech.core.eas.model.*
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory
import java.io.StringReader
import java.text.SimpleDateFormat
import java.util.*

/**
 * Parser for EAS XML responses
 */
class EASXMLParser {

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    private val dateFormatAlt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    /**
     * Parse FolderSync response
     */
    fun parseFolderSync(xml: String): FolderSyncResponse {
        val parser = createParser(xml)
        var syncKey = ""
        var status = 0
        val folders = mutableListOf<EASFolder>()

        var currentFolder: FolderBuilder? = null
        var inAdd = false

        while (parser.eventType != XmlPullParser.END_DOCUMENT) {
            when (parser.eventType) {
                XmlPullParser.START_TAG -> {
                    when (parser.name) {
                        "Add", "Update" -> {
                            currentFolder = FolderBuilder()
                            inAdd = true
                        }
                    }
                }
                XmlPullParser.TEXT -> {
                    val text = parser.text?.trim() ?: ""
                    if (text.isNotEmpty()) {
                        when (parser.name) {
                            "SyncKey" -> if (syncKey.isEmpty()) syncKey = text
                            "Status" -> if (status == 0) status = text.toIntOrNull() ?: 0
                        }
                        if (inAdd && currentFolder != null) {
                            when (parser.name) {
                                "ServerId" -> currentFolder.serverId = text
                                "ParentId" -> currentFolder.parentId = text
                                "DisplayName" -> currentFolder.displayName = text
                                "Type" -> currentFolder.type = text.toIntOrNull() ?: 0
                            }
                        }
                    }
                }
                XmlPullParser.END_TAG -> {
                    when (parser.name) {
                        "Add", "Update" -> {
                            currentFolder?.build()?.let { folders.add(it) }
                            currentFolder = null
                            inAdd = false
                        }
                    }
                }
            }
            parser.next()
        }

        return FolderSyncResponse(syncKey, folders, status)
    }

    /**
     * Parse Sync response
     */
    fun parseSync(xml: String): SyncResponse {
        val parser = createParser(xml)
        var syncKey = ""
        var status = 0
        val events = mutableListOf<EASCalendarEvent>()
        var moreAvailable = false

        var currentEvent: EventBuilder? = null
        var currentAttendee: AttendeeBuilder? = null
        var currentException: ExceptionBuilder? = null
        var inAdd = false
        var inAttendee = false
        var inBody = false
        var inExceptions = false
        var inException = false
        var currentTag = ""

        while (parser.eventType != XmlPullParser.END_DOCUMENT) {
            when (parser.eventType) {
                XmlPullParser.START_TAG -> {
                    currentTag = parser.name
                    when (parser.name) {
                        "Add", "Change" -> {
                            currentEvent = EventBuilder()
                            inAdd = true
                        }
                        "Attendee" -> {
                            currentAttendee = AttendeeBuilder()
                            inAttendee = true
                        }
                        "Body" -> inBody = true
                        "Exceptions" -> inExceptions = true
                        "Exception" -> {
                            if (inExceptions) {
                                currentException = ExceptionBuilder()
                                inException = true
                            }
                        }
                        "MoreAvailable" -> moreAvailable = true
                    }
                }
                XmlPullParser.TEXT -> {
                    val text = parser.text?.trim() ?: ""
                    if (text.isNotEmpty()) {
                        when (currentTag) {
                            "SyncKey" -> if (syncKey.isEmpty()) syncKey = text
                            "Status" -> if (status == 0) status = text.toIntOrNull() ?: 0
                        }

                        if (inAdd && currentEvent != null) {
                            when (currentTag) {
                                "ServerId" -> currentEvent.id = text
                                "Subject" -> currentEvent.subject = text
                                "StartTime" -> currentEvent.startTime = parseDate(text)
                                "EndTime" -> currentEvent.endTime = parseDate(text)
                                "Location" -> currentEvent.location = text
                                "AllDayEvent" -> currentEvent.isAllDay = text == "1"
                                "Data" -> if (inBody) currentEvent.body = text
                            }
                        }

                        if (inAttendee && currentAttendee != null) {
                            when (currentTag) {
                                "Email" -> currentAttendee.email = text
                                "Name" -> currentAttendee.name = text
                                "AttendeeType" -> currentAttendee.type = text.toIntOrNull() ?: 1
                                "AttendeeStatus" -> currentAttendee.status = text.toIntOrNull()
                            }
                        }

                        if (inException && currentException != null) {
                            when (currentTag) {
                                "ExceptionStartTime" -> currentException.originalStartTime = parseDate(text)
                                "StartTime" -> currentException.startTime = parseDate(text)
                                "EndTime" -> currentException.endTime = parseDate(text)
                                "Subject" -> currentException.subject = text
                                "Location" -> currentException.location = text
                                "Deleted" -> currentException.isDeleted = text == "1"
                            }
                        }
                    }
                }
                XmlPullParser.END_TAG -> {
                    when (parser.name) {
                        "Add", "Change" -> {
                            currentEvent?.build()?.let { events.add(it) }
                            currentEvent = null
                            inAdd = false
                        }
                        "Attendee" -> {
                            currentAttendee?.build()?.let { currentEvent?.attendees?.add(it) }
                            currentAttendee = null
                            inAttendee = false
                        }
                        "Exception" -> {
                            currentException?.build()?.let { currentEvent?.exceptions?.add(it) }
                            currentException = null
                            inException = false
                        }
                        "Exceptions" -> inExceptions = false
                        "Body" -> inBody = false
                    }
                    currentTag = ""
                }
            }
            parser.next()
        }

        return SyncResponse(syncKey, events, status, moreAvailable)
    }

    private fun createParser(xml: String): XmlPullParser {
        val factory = XmlPullParserFactory.newInstance()
        factory.isNamespaceAware = true
        val parser = factory.newPullParser()
        parser.setInput(StringReader(xml))
        return parser
    }

    private fun parseDate(text: String): Date? {
        return try {
            dateFormat.parse(text)
        } catch (e: Exception) {
            try {
                dateFormatAlt.parse(text)
            } catch (e: Exception) {
                null
            }
        }
    }

    // Builder classes
    private class FolderBuilder {
        var serverId = ""
        var parentId = "0"
        var displayName = ""
        var type = 0

        fun build(): EASFolder? {
            if (serverId.isEmpty()) return null
            return EASFolder(serverId, parentId, displayName, type)
        }
    }

    private class EventBuilder {
        var id = ""
        var subject = ""
        var startTime: Date? = null
        var endTime: Date? = null
        var location: String? = null
        var body: String? = null
        var isAllDay = false
        var attendees = mutableListOf<EASAttendee>()
        var exceptions = mutableListOf<EASException>()

        fun build(): EASCalendarEvent? {
            val start = startTime ?: return null
            val end = endTime ?: return null
            if (id.isEmpty()) return null

            return EASCalendarEvent(
                id = id,
                subject = subject.ifEmpty { "Untitled" },
                startTimeMillis = start.time,
                endTimeMillis = end.time,
                location = location,
                body = body,
                organizer = null,
                attendees = attendees.toList(),
                isAllDay = isAllDay,
                exceptions = exceptions.toList().ifEmpty { null }
            )
        }
    }

    private class ExceptionBuilder {
        var originalStartTime: Date? = null
        var startTime: Date? = null
        var endTime: Date? = null
        var subject: String? = null
        var location: String? = null
        var isDeleted = false

        fun build(): EASException? {
            val originalStart = originalStartTime ?: return null
            return EASException(
                originalStartTimeMillis = originalStart.time,
                startTimeMillis = if (isDeleted) null else startTime?.time,
                endTimeMillis = if (isDeleted) null else endTime?.time,
                subject = subject,
                location = location,
                isDeleted = isDeleted
            )
        }
    }

    private class AttendeeBuilder {
        var email = ""
        var name = ""
        var type = 1
        var status: Int? = null

        fun build(): EASAttendee? {
            if (email.isEmpty()) return null
            return EASAttendee(
                email = email,
                name = name.ifEmpty { email },
                type = AttendeeType.fromValue(type),
                status = status?.let { ResponseStatus.fromValue(it) }
            )
        }
    }
}
