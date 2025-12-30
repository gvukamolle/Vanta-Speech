import Foundation
import UIKit

/// Service layer for EWS calendar operations
actor EWSCalendarService {
    private let client: EWSClient

    init(client: EWSClient) {
        self.client = client
    }

    // MARK: - Find Events

    /// Fetch calendar events for a date range
    func findEvents(
        from startDate: Date,
        to endDate: Date,
        maxEntries: Int = 100
    ) async throws -> [EWSEvent] {
        let request = EWSXMLBuilder.buildFindItemRequest(
            startDate: startDate,
            endDate: endDate,
            maxEntries: maxEntries
        )

        let response = try await client.sendRequest(
            soapAction: EWSXMLBuilder.SOAPAction.findItem,
            body: request
        )

        return try EWSXMLParser.parseCalendarItems(from: response)
    }

    /// Fetch events for today
    func findTodayEvents() async throws -> [EWSEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await findEvents(from: startOfDay, to: endOfDay)
    }

    // MARK: - Get Event Details

    /// Get detailed event info including all attendees
    func getEventDetails(itemId: String, changeKey: String) async throws -> EWSEvent {
        let request = EWSXMLBuilder.buildGetItemRequest(
            itemId: itemId,
            changeKey: changeKey
        )

        let response = try await client.sendRequest(
            soapAction: EWSXMLBuilder.SOAPAction.getItem,
            body: request
        )

        let events = try EWSXMLParser.parseCalendarItems(from: response)
        guard let event = events.first else {
            throw EWSError.itemNotFound
        }
        return event
    }

    // MARK: - Update Event

    /// Update event body (add/replace summary)
    func updateEventBody(
        itemId: String,
        changeKey: String,
        bodyHtml: String,
        notifyAttendees: Bool = false
    ) async throws -> String {
        let request = EWSXMLBuilder.buildUpdateItemBodyRequest(
            itemId: itemId,
            changeKey: changeKey,
            bodyHtml: bodyHtml,
            notifyAttendees: notifyAttendees
        )

        let response = try await client.sendRequest(
            soapAction: EWSXMLBuilder.SOAPAction.updateItem,
            body: request
        )

        // Parse new ChangeKey from response
        return try EWSXMLParser.parseUpdateItemResponse(from: response)
    }

    /// Update event subject
    func updateEventSubject(
        itemId: String,
        changeKey: String,
        subject: String,
        notifyAttendees: Bool = false
    ) async throws -> String {
        let request = EWSXMLBuilder.buildUpdateItemSubjectRequest(
            itemId: itemId,
            changeKey: changeKey,
            subject: subject,
            notifyAttendees: notifyAttendees
        )

        let response = try await client.sendRequest(
            soapAction: EWSXMLBuilder.SOAPAction.updateItem,
            body: request
        )

        return try EWSXMLParser.parseUpdateItemResponse(from: response)
    }

    // MARK: - Create Event

    /// Create a new calendar event
    func createEvent(_ event: EWSNewEvent) async throws -> String {
        let request = EWSXMLBuilder.buildCreateCalendarItemRequest(event)

        let response = try await client.sendRequest(
            soapAction: EWSXMLBuilder.SOAPAction.createItem,
            body: request
        )

        return try EWSXMLParser.parseCreateItemResponse(from: response)
    }

    // MARK: - Send Email

    /// Send an email to recipients
    func sendEmail(_ email: EWSNewEmail) async throws {
        let request = EWSXMLBuilder.buildCreateMessageRequest(email)

        _ = try await client.sendRequest(
            soapAction: EWSXMLBuilder.SOAPAction.createItem,
            body: request
        )
    }

    // MARK: - Resolve Names (Contact Search)

    /// Search for contacts by name or email
    func resolveNames(query: String) async throws -> [EWSContact] {
        let request = EWSXMLBuilder.buildResolveNamesRequest(query: query)

        let response = try await client.sendRequest(
            soapAction: EWSXMLBuilder.SOAPAction.resolveNames,
            body: request
        )

        return try EWSXMLParser.parseResolveNamesResponse(from: response)
    }
}

// MARK: - XML Parser

/// Parses EWS XML responses
enum EWSXMLParser {

    /// Parse CalendarItem elements from FindItem/GetItem response
    static func parseCalendarItems(from data: Data) throws -> [EWSEvent] {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw EWSError.parseError("Invalid UTF-8 data")
        }

        // Check for errors
        if xmlString.contains("ResponseClass=\"Error\"") {
            if let errorMessage = extractElement("MessageText", from: xmlString) {
                throw EWSError.serverError(errorMessage)
            }
            throw EWSError.serverError("Unknown error")
        }

        var events: [EWSEvent] = []

        // Find all CalendarItem blocks
        let calendarItemPattern = "<t:CalendarItem[^>]*>.*?</t:CalendarItem>"
        guard let regex = try? NSRegularExpression(
            pattern: calendarItemPattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return events
        }

        let matches = regex.matches(
            in: xmlString,
            range: NSRange(xmlString.startIndex..., in: xmlString)
        )

        for match in matches {
            guard let range = Range(match.range, in: xmlString) else { continue }
            let itemXml = String(xmlString[range])

            if let event = parseCalendarItem(itemXml) {
                events.append(event)
            }
        }

        return events
    }

    private static func parseCalendarItem(_ xml: String) -> EWSEvent? {
        guard let itemId = extractAttribute("Id", from: "ItemId", in: xml),
              let changeKey = extractAttribute("ChangeKey", from: "ItemId", in: xml) else {
            return nil
        }

        let subject = extractElement("Subject", from: xml) ?? "(Без темы)"
        let startString = extractElement("Start", from: xml) ?? ""
        let endString = extractElement("End", from: xml) ?? ""
        let location = extractElement("Location", from: xml)
        let bodyHtml = extractElement("Body", from: xml)
        let isAllDayString = extractElement("IsAllDayEvent", from: xml) ?? "false"

        // Parse organizer
        let organizerEmail = extractNestedElement(outer: "Organizer", inner: "EmailAddress", from: xml)
        let organizerName = extractNestedElement(outer: "Organizer", inner: "Name", from: xml)

        // Parse attendees
        let requiredAttendees = parseAttendees(from: xml, type: "RequiredAttendees", isRequired: true)
        let optionalAttendees = parseAttendees(from: xml, type: "OptionalAttendees", isRequired: false)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let startDate = dateFormatter.date(from: startString) ??
            ISO8601DateFormatter().date(from: startString) ?? Date()
        let endDate = dateFormatter.date(from: endString) ??
            ISO8601DateFormatter().date(from: endString) ?? Date()

        return EWSEvent(
            itemId: itemId,
            changeKey: changeKey,
            subject: subject,
            startDate: startDate,
            endDate: endDate,
            location: location,
            bodyHtml: bodyHtml,
            bodyText: bodyHtml?.strippingHTMLTags(),
            attendees: requiredAttendees + optionalAttendees,
            organizerEmail: organizerEmail,
            organizerName: organizerName,
            isAllDay: isAllDayString.lowercased() == "true"
        )
    }

    private static func parseAttendees(from xml: String, type: String, isRequired: Bool) -> [EWSAttendee] {
        guard let attendeesBlock = extractElement(type, from: xml) else { return [] }

        var attendees: [EWSAttendee] = []

        let attendeePattern = "<t:Attendee>.*?</t:Attendee>"
        guard let regex = try? NSRegularExpression(
            pattern: attendeePattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return attendees
        }

        let matches = regex.matches(
            in: attendeesBlock,
            range: NSRange(attendeesBlock.startIndex..., in: attendeesBlock)
        )

        for match in matches {
            guard let range = Range(match.range, in: attendeesBlock) else { continue }
            let attendeeXml = String(attendeesBlock[range])

            if let email = extractElement("EmailAddress", from: attendeeXml) {
                let name = extractElement("Name", from: attendeeXml)
                let responseString = extractElement("ResponseType", from: attendeeXml) ?? "Unknown"
                let responseType = EWSResponseType(rawValue: responseString) ?? .unknown

                attendees.append(EWSAttendee(
                    email: email,
                    name: name,
                    responseType: responseType,
                    isRequired: isRequired
                ))
            }
        }

        return attendees
    }

    /// Parse UpdateItem response to get new ChangeKey
    static func parseUpdateItemResponse(from data: Data) throws -> String {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw EWSError.parseError("Invalid UTF-8 data")
        }

        if xmlString.contains("ResponseClass=\"Error\"") {
            if let errorCode = extractElement("ResponseCode", from: xmlString) {
                if errorCode == "ErrorChangeKeyRequiredForWriteOperations" ||
                   errorCode == "ErrorIrresolvableConflict" {
                    throw EWSError.changeKeyMismatch
                }
                if errorCode == "ErrorItemNotFound" {
                    throw EWSError.itemNotFound
                }
            }
            let message = extractElement("MessageText", from: xmlString) ?? "Unknown error"
            throw EWSError.serverError(message)
        }

        guard let newChangeKey = extractAttribute("ChangeKey", from: "ItemId", in: xmlString) else {
            throw EWSError.parseError("Could not find new ChangeKey in response")
        }

        return newChangeKey
    }

    /// Parse CreateItem response to get new ItemId
    static func parseCreateItemResponse(from data: Data) throws -> String {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw EWSError.parseError("Invalid UTF-8 data")
        }

        if xmlString.contains("ResponseClass=\"Error\"") {
            let message = extractElement("MessageText", from: xmlString) ?? "Unknown error"
            throw EWSError.serverError(message)
        }

        guard let itemId = extractAttribute("Id", from: "ItemId", in: xmlString) else {
            throw EWSError.parseError("Could not find ItemId in response")
        }

        return itemId
    }

    /// Parse ResolveNames response
    static func parseResolveNamesResponse(from data: Data) throws -> [EWSContact] {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw EWSError.parseError("Invalid UTF-8 data")
        }

        var contacts: [EWSContact] = []

        let resolutionPattern = "<t:Resolution>.*?</t:Resolution>"
        guard let regex = try? NSRegularExpression(
            pattern: resolutionPattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return contacts
        }

        let matches = regex.matches(
            in: xmlString,
            range: NSRange(xmlString.startIndex..., in: xmlString)
        )

        for match in matches {
            guard let range = Range(match.range, in: xmlString) else { continue }
            let resolutionXml = String(xmlString[range])

            if let email = extractNestedElement(outer: "Mailbox", inner: "EmailAddress", from: resolutionXml) {
                let name = extractNestedElement(outer: "Mailbox", inner: "Name", from: resolutionXml) ??
                           extractElement("DisplayName", from: resolutionXml) ?? email
                let mailboxTypeString = extractNestedElement(outer: "Mailbox", inner: "MailboxType", from: resolutionXml) ?? "Mailbox"
                let mailboxType = EWSMailboxType(rawValue: mailboxTypeString) ?? .unknown
                let department = extractElement("Department", from: resolutionXml)
                let jobTitle = extractElement("JobTitle", from: resolutionXml)

                contacts.append(EWSContact(
                    email: email,
                    displayName: name,
                    mailboxType: mailboxType,
                    department: department,
                    jobTitle: jobTitle
                ))
            }
        }

        return contacts
    }

    // MARK: - XML Helpers

    private static func extractElement(_ name: String, from xml: String) -> String? {
        // Match both t: and m: prefixed elements, or no prefix
        let patterns = [
            "<t:\(name)[^>]*>(.*?)</t:\(name)>",
            "<m:\(name)[^>]*>(.*?)</m:\(name)>",
            "<\(name)[^>]*>(.*?)</\(name)>"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
               let range = Range(match.range(at: 1), in: xml) {
                return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func extractNestedElement(outer: String, inner: String, from xml: String) -> String? {
        guard let outerContent = extractElement(outer, from: xml) else { return nil }
        return extractElement(inner, from: outerContent)
    }

    private static func extractAttribute(_ attr: String, from element: String, in xml: String) -> String? {
        let patterns = [
            "<t:\(element)[^>]*\(attr)=\"([^\"]+)\"",
            "<m:\(element)[^>]*\(attr)=\"([^\"]+)\"",
            "<\(element)[^>]*\(attr)=\"([^\"]+)\""
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
               let range = Range(match.range(at: 1), in: xml) {
                return String(xml[range])
            }
        }
        return nil
    }
}

// MARK: - String Extension

private extension String {
    func strippingHTMLTags() -> String {
        guard let data = self.data(using: .utf8) else { return self }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }

        // Fallback: simple tag removal
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
