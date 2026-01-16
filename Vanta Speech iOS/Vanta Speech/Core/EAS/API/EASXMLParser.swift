import Foundation

/// Parser for EAS XML responses
final class EASXMLParser: NSObject {

    private let xml: String
    private var parser: XMLParser?

    // Parsing state
    private var currentElement = ""
    private var currentText = ""

    // FolderSync parsing
    private var folderSyncKey = ""
    private var folderSyncStatus = 0
    private var folders: [EASFolder] = []
    private var currentFolder: FolderBuilder?

    // Sync parsing
    private var syncKey = ""
    private var syncStatus = 0
    private var events: [EASCalendarEvent] = []
    private var currentEvent: EventBuilder?
    private var currentAttendee: AttendeeBuilder?
    private var moreAvailable = false

    // Namespace tracking
    private var inFolder = false
    private var inEvent = false
    private var inAttendee = false
    private var inBody = false
    private var inRecurrence = false
    private var currentRecurrence: RecurrenceBuilder?

    // Response type tracking
    private var isFolderSyncResponse = false
    private var isSyncResponse = false

    init(xml: String) {
        self.xml = xml
        super.init()
    }

    // MARK: - Public API

    func parseFolderSync() throws -> FolderSyncResponse {
        guard let data = xml.data(using: .utf8) else {
            throw EASError.parseError("Invalid XML encoding")
        }

        // Mark that we're parsing a FolderSync response
        isFolderSyncResponse = true
        isSyncResponse = false

        parser = XMLParser(data: data)
        parser?.delegate = self
        parser?.parse()

        if let error = parser?.parserError {
            throw EASError.parseError(error.localizedDescription)
        }

        return FolderSyncResponse(
            syncKey: folderSyncKey,
            folders: folders,
            status: folderSyncStatus
        )
    }

    func parseSync() throws -> SyncResponse {
        guard let data = xml.data(using: .utf8) else {
            throw EASError.parseError("Invalid XML encoding")
        }

        // Mark that we're parsing a Sync response
        isFolderSyncResponse = false
        isSyncResponse = true

        parser = XMLParser(data: data)
        parser?.delegate = self
        parser?.parse()

        if let error = parser?.parserError {
            throw EASError.parseError(error.localizedDescription)
        }

        return SyncResponse(
            syncKey: syncKey,
            events: events,
            status: syncStatus,
            moreAvailable: moreAvailable
        )
    }
}

// MARK: - XMLParserDelegate

extension EASXMLParser: XMLParserDelegate {

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        // Debug: log element names related to attendees
        if elementName.lowercased().contains("attend") || elementName == "Email" || elementName == "Name" {
            print("[EAS Parser] START element: \(elementName), inEvent=\(inEvent), inAttendee=\(inAttendee)")
        }

        switch elementName {
        case "Add", "Update":
            if currentFolder == nil && currentEvent == nil {
                // Determine type based on response type, not folder count
                if isFolderSyncResponse {
                    // In FolderSync response, Add means folder
                    currentFolder = FolderBuilder()
                    inFolder = true
                } else if isSyncResponse {
                    // In Sync response, Add means calendar item
                    currentEvent = EventBuilder()
                    inEvent = true
                }
            }
        case "Attendee":
            currentAttendee = AttendeeBuilder()
            inAttendee = true
        case "Body":
            inBody = true
        case "Recurrence":
            currentRecurrence = RecurrenceBuilder()
            inRecurrence = true
        case "MoreAvailable":
            moreAvailable = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle folder parsing
        if inFolder {
            switch elementName {
            case "ServerId":
                currentFolder?.serverId = text
            case "ParentId":
                currentFolder?.parentId = text
            case "DisplayName":
                currentFolder?.displayName = text
            case "Type":
                currentFolder?.type = Int(text) ?? 0
            case "Add", "Update":
                if let folder = currentFolder?.build() {
                    folders.append(folder)
                }
                currentFolder = nil
                inFolder = false
            default:
                break
            }
        }

        // Handle event parsing
        if inEvent {
            switch elementName {
            case "ServerId":
                currentEvent?.id = text
            case "Subject":
                currentEvent?.subject = text
            case "StartTime":
                currentEvent?.startTime = parseDate(text)
            case "EndTime":
                currentEvent?.endTime = parseDate(text)
            case "Location":
                currentEvent?.location = text
            case "AllDayEvent":
                currentEvent?.isAllDay = text == "1"
            case "OrganizerEmail":
                currentEvent?.organizerEmail = text
                print("[EAS Parser] Organizer email: \(text)")
            case "OrganizerName":
                currentEvent?.organizerName = text
                print("[EAS Parser] Organizer name: \(text)")
            case "Data":
                if inBody {
                    currentEvent?.body = text
                    print("[EAS Parser] Body data length: \(text.count)")
                }
            case "Body":
                inBody = false
            case "Add", "Update":
                if let event = currentEvent?.build() {
                    events.append(event)
                }
                currentEvent = nil
                inEvent = false
            default:
                break
            }
        }

        // Handle attendee parsing - MUST check BEFORE event parsing to catch Email/Name inside Attendee
        if inAttendee {
            switch elementName {
            case "Email":
                currentAttendee?.email = text
                print("[EAS Parser] Attendee email set: \(text)")
            case "Name":
                currentAttendee?.name = text
                print("[EAS Parser] Attendee name set: \(text)")
            case "AttendeeType":
                currentAttendee?.type = Int(text) ?? 1
            case "AttendeeStatus":
                currentAttendee?.status = Int(text)
            case "Attendee":
                if let attendee = currentAttendee?.build() {
                    currentEvent?.attendees.append(attendee)
                    print("[EAS Parser] ADDED attendee: \(attendee.name) <\(attendee.email)>")
                } else {
                    print("[EAS Parser] FAILED to build attendee: email=\(currentAttendee?.email ?? "nil"), name=\(currentAttendee?.name ?? "nil")")
                }
                currentAttendee = nil
                inAttendee = false
            default:
                break
            }
        }

        // Handle recurrence parsing
        if inRecurrence {
            switch elementName {
            case "Type":
                currentRecurrence?.type = Int(text)
            case "Interval":
                currentRecurrence?.interval = Int(text)
            case "DayOfWeek":
                currentRecurrence?.dayOfWeek = Int(text)
            case "DayOfMonth":
                currentRecurrence?.dayOfMonth = Int(text)
            case "WeekOfMonth":
                currentRecurrence?.weekOfMonth = Int(text)
            case "MonthOfYear":
                currentRecurrence?.monthOfYear = Int(text)
            case "Until":
                currentRecurrence?.until = parseDate(text)
            case "Occurrences":
                currentRecurrence?.occurrences = Int(text)
            case "Recurrence":
                if let recurrence = currentRecurrence?.build() {
                    currentEvent?.recurrence = recurrence
                    print("[EAS Parser] Recurrence: type=\(recurrence.type.rawValue), interval=\(recurrence.interval), dayOfWeek=\(recurrence.dayOfWeek ?? 0)")
                }
                currentRecurrence = nil
                inRecurrence = false
            default:
                break
            }
        }

        // Handle root elements
        switch elementName {
        case "SyncKey":
            if folderSyncKey.isEmpty {
                folderSyncKey = text
            }
            if syncKey.isEmpty {
                syncKey = text
            }
        case "Status":
            if let status = Int(text) {
                if folderSyncStatus == 0 {
                    folderSyncStatus = status
                }
                if syncStatus == 0 {
                    syncStatus = status
                }
            }
        default:
            break
        }

        currentElement = ""
        currentText = ""
    }

    // MARK: - Helpers

    private func parseDate(_ string: String) -> Date? {
        // EAS uses compact ISO8601 format: 20251107T100000Z (no dashes or colons)
        // Try compact format first (most common in EAS)
        let compactFormatter = DateFormatter()
        compactFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        compactFormatter.timeZone = TimeZone(identifier: "UTC")
        compactFormatter.locale = Locale(identifier: "en_US_POSIX")

        if let date = compactFormatter.date(from: string) {
            return date
        }

        // Try standard ISO8601 format
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: string) {
            return date
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Builder Classes

private class FolderBuilder {
    var serverId = ""
    var parentId = "0"
    var displayName = ""
    var type = 0

    func build() -> EASFolder? {
        guard !serverId.isEmpty else { return nil }

        let folderType = EASFolderType(rawValue: type) ?? .unknown

        return EASFolder(
            serverId: serverId,
            parentId: parentId,
            displayName: displayName,
            type: folderType
        )
    }
}

private class EventBuilder {
    var id = ""
    var subject = ""
    var startTime: Date?
    var endTime: Date?
    var location: String?
    var body: String?
    var isAllDay = false
    var attendees: [EASAttendee] = []
    var organizerEmail: String?
    var organizerName: String?
    var recurrence: EASRecurrence?

    func build() -> EASCalendarEvent? {
        guard !id.isEmpty, let start = startTime else {
            print("[EAS Parser] Event build failed: id='\(id)', startTime=\(String(describing: startTime)), endTime=\(String(describing: endTime))")
            return nil
        }

        // If EndTime is missing, default to StartTime + 1 hour (or end of day for all-day events)
        let end: Date
        if let endTime = endTime {
            end = endTime
        } else if isAllDay {
            // All-day event: end at start of next day
            end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        } else {
            // Regular event: default to 1 hour duration
            end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        }

        // Build organizer from email/name if available
        var organizer: EASAttendee?
        if let email = organizerEmail, !email.isEmpty {
            organizer = EASAttendee(
                email: email,
                name: organizerName ?? email,
                type: .required,
                status: nil
            )
        }

        print("[EAS Parser] Built event: '\(subject)' from \(start) to \(end), organizer: \(organizer?.email ?? "none"), attendees: \(attendees.count), recurring: \(recurrence != nil)")

        return EASCalendarEvent(
            id: id,
            subject: subject.isEmpty ? "Untitled" : subject,
            startTime: start,
            endTime: end,
            location: location,
            body: body,
            organizer: organizer,
            attendees: attendees,
            isAllDay: isAllDay,
            recurrence: recurrence
        )
    }
}

private class AttendeeBuilder {
    var email = ""
    var name = ""
    var type = 1
    var status: Int?

    func build() -> EASAttendee? {
        guard !email.isEmpty else { return nil }

        return EASAttendee(
            email: email,
            name: name.isEmpty ? email : name,
            type: EASAttendeeType(rawValue: type) ?? .required,
            status: status.flatMap { EASResponseStatus(rawValue: $0) }
        )
    }
}

private class RecurrenceBuilder {
    var type: Int?
    var interval: Int?
    var dayOfWeek: Int?
    var dayOfMonth: Int?
    var weekOfMonth: Int?
    var monthOfYear: Int?
    var until: Date?
    var occurrences: Int?

    func build() -> EASRecurrence? {
        guard let typeValue = type,
              let recurrenceType = RecurrenceType(rawValue: typeValue) else {
            return nil
        }

        return EASRecurrence(
            type: recurrenceType,
            interval: interval ?? 1,
            dayOfWeek: dayOfWeek,
            dayOfMonth: dayOfMonth,
            until: until
        )
    }
}
