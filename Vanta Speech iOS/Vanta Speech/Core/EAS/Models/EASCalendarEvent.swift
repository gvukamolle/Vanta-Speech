import Foundation

// MARK: - Exception
/// Exception (modified/deleted occurrence) for a recurring event
struct EASException: Codable, Equatable {
    /// The original start time of this occurrence
    let originalStartTime: Date
    /// Modified start time (nil if deleted)
    let startTime: Date?
    /// Modified end time
    let endTime: Date?
    /// Modified subject
    let subject: String?
    /// Modified location
    let location: String?
    /// Whether this exception is a deletion
    var isDeleted: Bool { startTime == nil }
}

// MARK: - Meeting Status

/// EAS Meeting status values
enum EASMeetingStatus: Int, Codable, Equatable {
    case appointment = 0        // Встреча без участников
    case meeting = 1            // Встреча с участниками
    case received = 3           // Получено приглашение
    case cancelled = 5          // Отменена организатором
    case receivedCancelled = 7  // Приглашение отменено

    var isCancelled: Bool {
        self == .cancelled || self == .receivedCancelled
    }
}

/// Calendar event from EAS Sync response
struct EASCalendarEvent: Codable, Equatable, Identifiable {
    /// Server-assigned event ID
    let id: String
    
    /// Global unique identifier (UID)
    let uid: String?

    /// Event subject/title
    let subject: String

    /// Start time
    let startTime: Date

    /// End time
    let endTime: Date

    /// Location (optional)
    let location: String?

    /// Body content (HTML)
    let body: String?

    /// Meeting organizer
    let organizer: EASAttendee?

    /// List of attendees
    let attendees: [EASAttendee]

    /// Whether this is an all-day event
    let isAllDay: Bool

    /// Recurrence pattern (optional)
    let recurrence: EASRecurrence?

    /// Meeting status
    let meetingStatus: EASMeetingStatus?
    
    /// Exceptions for recurring events
    let exceptions: [EASException]?

    /// Client-generated ID for new events
    var clientId: String?
    
    /// Whether this is an orphan exception
    let isException: Bool
    
    /// Original start time for exception
    let originalStartTime: Date?

    // MARK: - Computed Properties

    var isCancelled: Bool {
        meetingStatus?.isCancelled ?? false
    }

    var isRecurring: Bool {
        recurrence != nil
    }

    /// Generate occurrences for recurring events within a date range
    func expandOccurrences(from rangeStart: Date, to rangeEnd: Date, maxOccurrences: Int = 100) -> [EASCalendarEvent] {
        guard let recurrence = recurrence else {
            return [self]
        }

        var occurrences: [EASCalendarEvent] = []
        let calendar = Calendar.current
        let duration = endTime.timeIntervalSince(startTime)

        // Build exception map by original start time day
        let exceptionMap = exceptions?.reduce(into: [Date: EASException]()) { map, ex in
            let key = calendar.startOfDay(for: ex.originalStartTime)
            map[key] = ex
        } ?? [:]

        // Determine base time from exceptions if available (e.g., 09:30 from PMO Daily)
        // Otherwise use master's start time
        let baseTime: Date
        if let firstException = exceptions?.first(where: { !$0.isDeleted }) {
            baseTime = firstException.originalStartTime
        } else {
            baseTime = startTime
        }
        let baseHour = calendar.component(.hour, from: baseTime)
        let baseMinute = calendar.component(.minute, from: baseTime)

        // Start from rangeStart or master's start time, whichever is later
        var currentDate = max(rangeStart, startTime)
        var occurrenceIndex = 0

        while currentDate <= rangeEnd && occurrenceIndex < maxOccurrences {
            // Check recurrence end date
            if let until = recurrence.until, currentDate > until {
                break
            }

            // Check if this date matches recurrence pattern
            let shouldInclude: Bool
            switch recurrence.type {
            case .weekly:
                let weekday = calendar.component(.weekday, from: currentDate)
                shouldInclude = recurrence.includesWeekday(weekday)
            case .daily:
                shouldInclude = true
            case .monthly:
                if let dayOfMonth = recurrence.dayOfMonth {
                    shouldInclude = calendar.component(.day, from: currentDate) == dayOfMonth
                } else {
                    shouldInclude = true
                }
            default:
                shouldInclude = true
            }

            if shouldInclude {
                let occurrenceDay = calendar.startOfDay(for: currentDate)

                if let exception = exceptionMap[occurrenceDay] {
                    if !exception.isDeleted {
                        // Modified occurrence - use exception's data
                        let occurrenceStart = exception.startTime ?? currentDate
                        let occurrenceEnd = exception.endTime ?? occurrenceStart.addingTimeInterval(duration)
                        let occurrence = EASCalendarEvent(
                            id: "\(id)_exception_\(occurrenceIndex)",
                            uid: uid,
                            subject: exception.subject ?? subject,
                            startTime: occurrenceStart,
                            endTime: occurrenceEnd,
                            location: exception.location ?? location,
                            body: body,
                            organizer: organizer,
                            attendees: attendees,
                            isAllDay: isAllDay,
                            recurrence: nil,
                            meetingStatus: meetingStatus,
                            exceptions: nil,
                            clientId: nil,
                            isException: true,
                            originalStartTime: exception.originalStartTime
                        )
                        occurrences.append(occurrence)
                    }
                    // If deleted, skip (don't add occurrence)
                } else {
                    // Regular occurrence - use base time (e.g., 09:30)
                    guard let occurrenceStart = calendar.date(
                        bySettingHour: baseHour,
                        minute: baseMinute,
                        second: 0,
                        of: occurrenceDay
                    ) else {
                        continue
                    }

                    let occurrence = EASCalendarEvent(
                        id: "\(id)_\(occurrenceIndex)",
                        uid: uid,
                        subject: subject,
                        startTime: occurrenceStart,
                        endTime: occurrenceStart.addingTimeInterval(duration),
                        location: location,
                        body: body,
                        organizer: organizer,
                        attendees: attendees,
                        isAllDay: isAllDay,
                        recurrence: nil,
                        meetingStatus: meetingStatus,
                        exceptions: nil,
                        clientId: nil,
                        isException: false,
                        originalStartTime: nil
                    )
                    occurrences.append(occurrence)
                }
                occurrenceIndex += 1
            }

            // Advance to next potential occurrence
            switch recurrence.type {
            case .daily:
                currentDate = calendar.date(byAdding: .day, value: recurrence.interval, to: currentDate) ?? currentDate.addingTimeInterval(86400)
            case .weekly:
                // For weekly, advance by one day and check mask
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(86400)
            case .monthly, .monthlyNth:
                currentDate = calendar.date(byAdding: .month, value: recurrence.interval, to: currentDate) ?? currentDate.addingTimeInterval(2592000)
            case .yearly, .yearlyNth:
                currentDate = calendar.date(byAdding: .year, value: recurrence.interval, to: currentDate) ?? currentDate.addingTimeInterval(31536000)
            }
        }

        return occurrences.isEmpty ? [self] : occurrences
    }

    /// Duration in minutes
    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    /// Formatted duration string
    var formattedDuration: String {
        let minutes = durationMinutes
        if minutes < 60 {
            return "\(minutes) мин"
        } else if minutes % 60 == 0 {
            return "\(minutes / 60) ч"
        } else {
            return "\(minutes / 60) ч \(minutes % 60) мин"
        }
    }

    /// Unique attendees (deduplicated by email)
    var uniqueAttendees: [EASAttendee] {
        var seenEmails = Set<String>()
        return attendees.filter { attendee in
            let email = attendee.email.lowercased()
            if seenEmails.contains(email) {
                return false
            }
            seenEmails.insert(email)
            return true
        }
    }
    
    /// Attendees excluding resources (rooms, equipment)
    var humanAttendees: [EASAttendee] {
        var seenEmails = Set<String>()
        return attendees.filter { attendee in
            guard attendee.type != .resource else { return false }
            let email = attendee.email.lowercased()
            if seenEmails.contains(email) {
                return false
            }
            seenEmails.insert(email)
            return true
        }
    }
    
    /// Body content as plain text (strips HTML tags)
    var plainBody: String? {
        guard let body = body, !body.isEmpty else { return nil }
        
        var result = body
        
        // Replace common HTML entities
        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…",
            "&bull;": "•"
        ]
        
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Replace numeric HTML entities
        let numericEntityPattern = "&#(\\d+);"
        if let numericRegex = try? NSRegularExpression(pattern: numericEntityPattern, options: []) {
            let matches = numericRegex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            for match in matches.reversed() {
                if let numberRange = Range(match.range(at: 1), in: result),
                   let number = Int(result[numberRange]),
                   let scalar = UnicodeScalar(number) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }
        
        // Replace hex HTML entities
        let hexEntityPattern = "&#x([0-9A-Fa-f]+);"
        if let hexRegex = try? NSRegularExpression(pattern: hexEntityPattern, options: []) {
            let matches = hexRegex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            for match in matches.reversed() {
                if let hexRange = Range(match.range(at: 1), in: result),
                   let number = Int(result[hexRange], radix: 16),
                   let scalar = UnicodeScalar(number) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }
        
        // Remove HTML tags
        let pattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // Normalize whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        
        while result.contains("\n\n") {
            result = result.replacingOccurrences(of: "\n\n", with: "\n")
        }
        
        return result.isEmpty ? nil : result
    }

    /// Email list for all human attendees
    var attendeeEmails: [String] {
        var emails = humanAttendees.map { $0.email }
        if let organizerEmail = organizer?.email,
           !emails.contains(where: { $0.lowercased() == organizerEmail.lowercased() }) {
            emails.append(organizerEmail)
        }
        return emails
    }

    // MARK: - Initialization

    init(
        id: String,
        uid: String? = nil,
        subject: String,
        startTime: Date,
        endTime: Date,
        location: String? = nil,
        body: String? = nil,
        organizer: EASAttendee? = nil,
        attendees: [EASAttendee] = [],
        isAllDay: Bool = false,
        recurrence: EASRecurrence? = nil,
        meetingStatus: EASMeetingStatus? = nil,
        exceptions: [EASException]? = nil,
        clientId: String? = nil,
        isException: Bool = false,
        originalStartTime: Date? = nil
    ) {
        self.id = id
        self.uid = uid
        self.subject = subject
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.body = body
        self.organizer = organizer
        self.attendees = attendees
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.meetingStatus = meetingStatus
        self.exceptions = exceptions
        self.clientId = clientId
        self.isException = isException
        self.originalStartTime = originalStartTime
    }

    /// Create a new event for meeting summary
    static func createMeetingSummary(
        originalEvent: EASCalendarEvent,
        summaryHtml: String,
        startTime: Date = Date().addingTimeInterval(3600),
        durationMinutes: Int = 15
    ) -> EASCalendarEvent {
        EASCalendarEvent(
            id: "",
            subject: "Meeting Summary: \(originalEvent.subject)",
            startTime: startTime,
            endTime: startTime.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            location: nil,
            body: summaryHtml,
            organizer: nil,
            attendees: originalEvent.humanAttendees,
            isAllDay: false,
            recurrence: nil,
            exceptions: nil,
            clientId: UUID().uuidString
        )
    }
}

// MARK: - EAS XML Generation

extension EASCalendarEvent {
    /// Convert to EAS XML format for Sync Add command
    func toEASXml() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var xml = """
        <calendar:Subject>\(subject.xmlEscaped)</calendar:Subject>
        <calendar:StartTime>\(dateFormatter.string(from: startTime))</calendar:StartTime>
        <calendar:EndTime>\(dateFormatter.string(from: endTime))</calendar:EndTime>
        <calendar:AllDayEvent>\(isAllDay ? "1" : "0")</calendar:AllDayEvent>
        """

        if let location = location {
            xml += "<calendar:Location>\(location.xmlEscaped)</calendar:Location>"
        }

        if let body = body {
            xml += """
            <Body xmlns="AirSyncBase">
                <Type>2</Type>
                <Data>\(body.xmlEscaped)</Data>
            </Body>
            """
        }

        if !attendees.isEmpty {
            xml += "<calendar:Attendees>"
            for attendee in attendees {
                xml += """
                <calendar:Attendee>
                    <calendar:Email>\(attendee.email.xmlEscaped)</calendar:Email>
                    <calendar:Name>\(attendee.name.xmlEscaped)</calendar:Name>
                    <calendar:AttendeeType>\(attendee.type.rawValue)</calendar:AttendeeType>
                </calendar:Attendee>
                """
            }
            xml += "</calendar:Attendees>"
        }

        return xml
    }
}

// MARK: - Recurrence

/// Recurrence pattern for repeating events
struct EASRecurrence: Codable, Equatable {
    let type: RecurrenceType
    let interval: Int
    let dayOfWeek: Int?
    let dayOfMonth: Int?
    let until: Date?

    /// DayOfWeek bitmask constants (EAS format)
    struct DayOfWeekMask {
        static let sunday = 1
        static let monday = 2
        static let tuesday = 4
        static let wednesday = 8
        static let thursday = 16
        static let friday = 32
        static let saturday = 64
    }

    /// Check if a given weekday is included in the mask
    func includesWeekday(_ weekday: Int) -> Bool {
        guard let mask = dayOfWeek else { return false }
        let bit = 1 << (weekday - 1)
        return (mask & bit) != 0
    }
}

/// Recurrence type values
enum RecurrenceType: Int, Codable, Equatable {
    case daily = 0
    case weekly = 1
    case monthly = 2
    case monthlyNth = 3
    case yearly = 5
    case yearlyNth = 6
}

// MARK: - String XML Escaping

extension String {
    /// Escape special XML characters
    var xmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
