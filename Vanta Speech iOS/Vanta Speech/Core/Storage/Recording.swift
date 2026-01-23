import Foundation
import SwiftData

@Model
final class Recording {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFileURL: String
    var transcriptionText: String?
    var summaryText: String?
    var isTranscribed: Bool = false
    var isUploading: Bool = false
    var isSummaryGenerating: Bool = false
    var presetRawValue: String?

    // MARK: - Calendar Meeting Link

    /// ID of linked calendar event (from EAS)
    var linkedMeetingId: String?

    /// Subject of the linked meeting (for display when event not loaded)
    var linkedMeetingSubject: String?

    /// JSON-encoded array of attendee emails for sending summary
    var linkedMeetingAttendeesJSON: String?

    /// Organizer email for the linked meeting
    var linkedMeetingOrganizerEmail: String?

    // MARK: - Summary Email Tracking

    /// When the summary was sent to participants
    var summarySentAt: Date?

    /// JSON-encoded array of emails the summary was sent to
    var summarySentToEmails: String?

    // MARK: - Confluence Export Tracking

    /// ID страницы в Confluence (для обновления)
    var confluencePageId: String?

    /// URL страницы в Confluence (для открытия в браузере)
    var confluencePageURL: String?

    /// Когда саммари было экспортировано в Confluence
    var confluenceExportedAt: Date?

    /// Whether this recording has a linked calendar meeting
    var hasLinkedMeeting: Bool {
        linkedMeetingId != nil
    }

    /// Whether this recording has been exported to Confluence
    var isExportedToConfluence: Bool {
        confluencePageId != nil
    }

    /// Attendee emails parsed from JSON
    var linkedMeetingAttendeeEmails: [String] {
        get {
            guard let json = linkedMeetingAttendeesJSON,
                  let data = json.data(using: .utf8),
                  let emails = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return emails
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                linkedMeetingAttendeesJSON = json
            }
        }
    }

    /// The meeting preset used for this recording
    var preset: RecordingPreset? {
        get { presetRawValue.flatMap { RecordingPreset(rawValue: $0) } }
        set { presetRawValue = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileURL: String,
        transcriptionText: String? = nil,
        summaryText: String? = nil,
        isTranscribed: Bool = false,
        isUploading: Bool = false,
        isSummaryGenerating: Bool = false,
        preset: RecordingPreset? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionText = transcriptionText
        self.summaryText = summaryText
        self.isTranscribed = isTranscribed
        self.isUploading = isUploading
        self.isSummaryGenerating = isSummaryGenerating
        self.presetRawValue = preset?.rawValue
    }
}

extension Recording {
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Link this recording to a calendar event
    func linkToMeeting(_ event: EASCalendarEvent) {
        linkedMeetingId = event.id
        linkedMeetingSubject = event.subject
        linkedMeetingAttendeeEmails = event.attendeeEmails
        linkedMeetingOrganizerEmail = event.organizer?.email
    }

    /// Unlink from calendar meeting
    func unlinkFromMeeting() {
        linkedMeetingId = nil
        linkedMeetingSubject = nil
        linkedMeetingAttendeesJSON = nil
        linkedMeetingOrganizerEmail = nil
    }

    /// Mark as exported to Confluence
    func markExportedToConfluence(pageId: String, pageURL: String?) {
        confluencePageId = pageId
        confluencePageURL = pageURL
        confluenceExportedAt = Date()
    }

    /// Clear Confluence export data
    func clearConfluenceExport() {
        confluencePageId = nil
        confluencePageURL = nil
        confluenceExportedAt = nil
    }
}
