package com.vanta.speech.core.ews.api

import com.vanta.speech.core.ews.model.EWSConfig
import com.vanta.speech.core.ews.model.EWSNewEmail
import com.vanta.speech.core.ews.model.EWSNewEvent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Builds SOAP XML envelopes for Exchange Web Services requests
 */
object EWSXMLBuilder {

    // MARK: - SOAP Envelope Wrapper

    /**
     * Wraps body content in a SOAP envelope with EWS namespaces
     */
    private fun wrapInEnvelope(body: String): String = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="${EWSConfig.Namespace.SOAP}"
                       xmlns:t="${EWSConfig.Namespace.TYPES}"
                       xmlns:m="${EWSConfig.Namespace.MESSAGES}">
          <soap:Header>
            <t:RequestServerVersion Version="${EWSConfig.EXCHANGE_VERSION}"/>
          </soap:Header>
          <soap:Body>
            $body
          </soap:Body>
        </soap:Envelope>
    """.trimIndent()

    // MARK: - FindItem (Calendar Events)

    /**
     * Build FindItem request for calendar events in a date range
     */
    fun buildFindItemRequest(
        startDate: Date,
        endDate: Date,
        maxEntries: Int = 100
    ): String {
        val start = formatISO8601(startDate)
        val end = formatISO8601(endDate)

        val body = """
            <m:FindItem Traversal="Shallow">
              <m:ItemShape>
                <t:BaseShape>Default</t:BaseShape>
                <t:AdditionalProperties>
                  <t:FieldURI FieldURI="calendar:Start"/>
                  <t:FieldURI FieldURI="calendar:End"/>
                  <t:FieldURI FieldURI="calendar:Location"/>
                  <t:FieldURI FieldURI="calendar:Organizer"/>
                  <t:FieldURI FieldURI="calendar:RequiredAttendees"/>
                  <t:FieldURI FieldURI="calendar:OptionalAttendees"/>
                  <t:FieldURI FieldURI="calendar:IsAllDayEvent"/>
                  <t:FieldURI FieldURI="item:Subject"/>
                  <t:FieldURI FieldURI="item:Body"/>
                </t:AdditionalProperties>
              </m:ItemShape>
              <m:CalendarView MaxEntriesReturned="$maxEntries" StartDate="$start" EndDate="$end"/>
              <m:ParentFolderIds>
                <t:DistinguishedFolderId Id="calendar"/>
              </m:ParentFolderIds>
            </m:FindItem>
        """.trimIndent()
        return wrapInEnvelope(body)
    }

    // MARK: - GetItem (Event Details)

    /**
     * Build GetItem request for detailed event info including attendees
     */
    fun buildGetItemRequest(itemId: String, changeKey: String): String {
        val body = """
            <m:GetItem>
              <m:ItemShape>
                <t:BaseShape>AllProperties</t:BaseShape>
                <t:AdditionalProperties>
                  <t:FieldURI FieldURI="calendar:RequiredAttendees"/>
                  <t:FieldURI FieldURI="calendar:OptionalAttendees"/>
                  <t:FieldURI FieldURI="calendar:Resources"/>
                  <t:FieldURI FieldURI="item:Body"/>
                </t:AdditionalProperties>
              </m:ItemShape>
              <m:ItemIds>
                <t:ItemId Id="${escapeXML(itemId)}" ChangeKey="${escapeXML(changeKey)}"/>
              </m:ItemIds>
            </m:GetItem>
        """.trimIndent()
        return wrapInEnvelope(body)
    }

    // MARK: - UpdateItem (Update Event Body)

    /**
     * Build UpdateItem request to update event body (append summary)
     */
    fun buildUpdateItemBodyRequest(
        itemId: String,
        changeKey: String,
        bodyHtml: String,
        notifyAttendees: Boolean = false
    ): String {
        val sendInvites = if (notifyAttendees) "SendToAllAndSaveCopy" else "SendToNone"
        val escapedBody = escapeXML(bodyHtml)

        val body = """
            <m:UpdateItem ConflictResolution="AlwaysOverwrite" SendMeetingInvitationsOrCancellations="$sendInvites">
              <m:ItemChanges>
                <t:ItemChange>
                  <t:ItemId Id="${escapeXML(itemId)}" ChangeKey="${escapeXML(changeKey)}"/>
                  <t:Updates>
                    <t:SetItemField>
                      <t:FieldURI FieldURI="item:Body"/>
                      <t:CalendarItem>
                        <t:Body BodyType="HTML">$escapedBody</t:Body>
                      </t:CalendarItem>
                    </t:SetItemField>
                  </t:Updates>
                </t:ItemChange>
              </m:ItemChanges>
            </m:UpdateItem>
        """.trimIndent()
        return wrapInEnvelope(body)
    }

    /**
     * Build UpdateItem request to update event subject
     */
    fun buildUpdateItemSubjectRequest(
        itemId: String,
        changeKey: String,
        subject: String,
        notifyAttendees: Boolean = false
    ): String {
        val sendInvites = if (notifyAttendees) "SendToAllAndSaveCopy" else "SendToNone"

        val body = """
            <m:UpdateItem ConflictResolution="AlwaysOverwrite" SendMeetingInvitationsOrCancellations="$sendInvites">
              <m:ItemChanges>
                <t:ItemChange>
                  <t:ItemId Id="${escapeXML(itemId)}" ChangeKey="${escapeXML(changeKey)}"/>
                  <t:Updates>
                    <t:SetItemField>
                      <t:FieldURI FieldURI="item:Subject"/>
                      <t:CalendarItem>
                        <t:Subject>${escapeXML(subject)}</t:Subject>
                      </t:CalendarItem>
                    </t:SetItemField>
                  </t:Updates>
                </t:ItemChange>
              </m:ItemChanges>
            </m:UpdateItem>
        """.trimIndent()
        return wrapInEnvelope(body)
    }

    // MARK: - CreateItem (New Calendar Event)

    /**
     * Build CreateItem request for a new calendar event
     */
    fun buildCreateCalendarItemRequest(event: EWSNewEvent): String {
        val start = formatISO8601(event.startDate)
        val end = formatISO8601(event.endDate)

        val attendeesXml = buildString {
            if (event.requiredAttendees.isNotEmpty()) {
                append("<t:RequiredAttendees>\n")
                for (email in event.requiredAttendees) {
                    append("""
                      <t:Attendee>
                        <t:Mailbox>
                          <t:EmailAddress>${escapeXML(email)}</t:EmailAddress>
                        </t:Mailbox>
                      </t:Attendee>
                    """.trimIndent())
                    append("\n")
                }
                append("</t:RequiredAttendees>\n")
            }

            if (event.optionalAttendees.isNotEmpty()) {
                append("<t:OptionalAttendees>\n")
                for (email in event.optionalAttendees) {
                    append("""
                      <t:Attendee>
                        <t:Mailbox>
                          <t:EmailAddress>${escapeXML(email)}</t:EmailAddress>
                        </t:Mailbox>
                      </t:Attendee>
                    """.trimIndent())
                    append("\n")
                }
                append("</t:OptionalAttendees>\n")
            }
        }

        val locationXml = event.location?.let { "<t:Location>${escapeXML(it)}</t:Location>" } ?: ""
        val bodyXml = event.bodyHtml?.let { "<t:Body BodyType=\"HTML\">${escapeXML(it)}</t:Body>" } ?: ""

        val body = """
            <m:CreateItem SendMeetingInvitations="SendToAllAndSaveCopy">
              <m:SavedItemFolderId>
                <t:DistinguishedFolderId Id="calendar"/>
              </m:SavedItemFolderId>
              <m:Items>
                <t:CalendarItem>
                  <t:Subject>${escapeXML(event.subject)}</t:Subject>
                  $bodyXml
                  <t:Start>$start</t:Start>
                  <t:End>$end</t:End>
                  $locationXml
                  <t:IsAllDayEvent>${if (event.isAllDay) "true" else "false"}</t:IsAllDayEvent>
                  $attendeesXml
                </t:CalendarItem>
              </m:Items>
            </m:CreateItem>
        """.trimIndent()
        return wrapInEnvelope(body)
    }

    // MARK: - CreateItem (Send Email)

    /**
     * Build CreateItem request to send an email
     */
    fun buildCreateMessageRequest(email: EWSNewEmail): String {
        val disposition = if (email.saveToSentItems) "SendAndSaveCopy" else "SendOnly"

        val toRecipientsXml = buildString {
            append("<t:ToRecipients>\n")
            for (recipient in email.toRecipients) {
                append("""
                  <t:Mailbox>
                    <t:EmailAddress>${escapeXML(recipient)}</t:EmailAddress>
                  </t:Mailbox>
                """.trimIndent())
                append("\n")
            }
            append("</t:ToRecipients>\n")
        }

        val ccRecipientsXml = if (email.ccRecipients.isNotEmpty()) {
            buildString {
                append("<t:CcRecipients>\n")
                for (recipient in email.ccRecipients) {
                    append("""
                      <t:Mailbox>
                        <t:EmailAddress>${escapeXML(recipient)}</t:EmailAddress>
                      </t:Mailbox>
                    """.trimIndent())
                    append("\n")
                }
                append("</t:CcRecipients>\n")
            }
        } else ""

        val body = """
            <m:CreateItem MessageDisposition="$disposition">
              <m:SavedItemFolderId>
                <t:DistinguishedFolderId Id="sentitems"/>
              </m:SavedItemFolderId>
              <m:Items>
                <t:Message>
                  <t:Subject>${escapeXML(email.subject)}</t:Subject>
                  <t:Body BodyType="HTML">${escapeXML(email.bodyHtml)}</t:Body>
                  $toRecipientsXml
                  $ccRecipientsXml
                </t:Message>
              </m:Items>
            </m:CreateItem>
        """.trimIndent()
        return wrapInEnvelope(body)
    }

    // MARK: - ResolveNames (Contact Search)

    /**
     * Build ResolveNames request for contact autocomplete
     */
    fun buildResolveNamesRequest(
        query: String,
        searchScope: String = "ContactsActiveDirectory"
    ): String {
        val body = """
            <m:ResolveNames ReturnFullContactData="true" SearchScope="$searchScope">
              <m:UnresolvedEntry>${escapeXML(query)}</m:UnresolvedEntry>
            </m:ResolveNames>
        """.trimIndent()
        return wrapInEnvelope(body)
    }

    // MARK: - Helpers

    /**
     * Format date to ISO 8601 for EWS
     */
    private fun formatISO8601(date: Date): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")
        return formatter.format(date)
    }

    /**
     * Escape special XML characters
     */
    private fun escapeXML(string: String): String {
        return string
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }
}
