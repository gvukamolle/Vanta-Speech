import Combine
import Foundation
import SwiftUI

/// Manager for sending meeting summary emails to participants
@MainActor
final class SummaryEmailManager: ObservableObject {
    static let shared = SummaryEmailManager()

    // MARK: - Settings

    /// Include current user in summary email recipients (default: true)
    @AppStorage("summary_email_include_self") var includeSelfInSummaryEmail = true

    // MARK: - Published State

    @Published var isSending = false
    @Published var lastError: Error?
    @Published var lastSentRecordingId: UUID?

    // MARK: - Dependencies

    private let emailService = EASEmailService()
    private let keychainManager = KeychainManager.shared

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Send summary email to meeting participants (excluding current user)
    /// - Parameter recording: The recording with linked meeting and summary
    /// - Returns: True if email was sent successfully
    @discardableResult
    func sendSummary(for recording: Recording) async -> Bool {
        guard recording.canSendSummary else {
            debugLog("Cannot send summary: conditions not met", module: "SummaryEmail", level: .warning)
            return false
        }

        guard let summary = recording.summaryText else {
            debugLog("Cannot send summary: no summary text", module: "SummaryEmail", level: .warning)
            return false
        }

        // Get current user email first
        let currentUserEmail = getCurrentUserEmail()

        // Get attendees from live event first (more up-to-date than stored)
        var attendees = getAttendeesFromLiveEvent(meetingId: recording.linkedMeetingId)

        // Fallback to stored attendees if live event not found
        if attendees.isEmpty {
            attendees = recording.linkedMeetingAttendeeEmails
            debugLog("Using stored attendees: \(attendees.count)", module: "SummaryEmail", level: .info)
        } else {
            debugLog("Using live event attendees: \(attendees.count)", module: "SummaryEmail", level: .info)
            // Update stored attendees for consistency
            recording.linkedMeetingAttendeeEmails = attendees
        }

        // Final fallback to current user if empty and includeSelf is enabled
        if attendees.isEmpty, includeSelfInSummaryEmail, let selfEmail = currentUserEmail {
            attendees = [selfEmail]
            debugLog("No attendees found, using current user as recipient", module: "SummaryEmail", level: .info)
        }

        guard !attendees.isEmpty else {
            debugLog("Cannot send summary: no attendees and includeSelf is disabled", module: "SummaryEmail", level: .warning)
            return false
        }

        // Filter recipients based on settings
        let recipients = filterRecipients(attendees: attendees, currentUserEmail: currentUserEmail)

        guard !recipients.isEmpty else {
            debugLog("Cannot send summary: all attendees filtered out", module: "SummaryEmail", level: .warning)
            return false
        }

        // Get live event for additional details
        let liveEvent = getLiveEvent(meetingId: recording.linkedMeetingId)

        // Build email - use live event subject (most up-to-date) or fall back to stored
        let meetingSubject = liveEvent?.subject ?? recording.linkedMeetingSubject ?? "Встреча"
        let subject = "Саммари: \(meetingSubject)"

        // Build HTML email using template
        let emailHTML = buildEmailHTML(
            recording: recording,
            summary: summary,
            event: liveEvent,
            attendeeNames: getAttendeeNames(from: liveEvent, fallbackEmails: attendees)
        )

        isSending = true
        lastError = nil

        do {
            let success = try await emailService.sendEmail(
                to: recipients,
                subject: subject,
                body: emailHTML,
                isHTML: true,
                from: currentUserEmail  // Use proper email format, not DOMAIN\user
            )

            if success {
                // Update recording with sent info
                recording.summarySentAt = Date()
                recording.summarySentToEmails = encodeEmails(recipients)
                lastSentRecordingId = recording.id

                debugLog("Summary sent successfully to \(recipients.count) recipients", module: "SummaryEmail", level: .info)
            }

            isSending = false
            return success
        } catch {
            lastError = error
            isSending = false
            debugLog("Failed to send summary: \(error.localizedDescription)", module: "SummaryEmail", level: .error)
            return false
        }
    }

    /// Check if recording should auto-send summary and send if conditions are met
    /// - Parameter recording: The recording to check
    func checkAndAutoSend(recording: Recording) async {
        // Only auto-send if:
        // 1. Recording has linked meeting
        // 2. Has summary
        // 3. Summary was never sent before
        guard recording.hasLinkedMeeting,
              recording.summaryText != nil,
              recording.summarySentAt == nil else {
            return
        }

        debugLog("Auto-sending summary for recording: \(recording.id)", module: "SummaryEmail", level: .info)
        await sendSummary(for: recording)
    }

    // MARK: - Private Helpers

    /// Get attendees from live event in EASCalendarManager cache
    /// - Parameter meetingId: The meeting ID to look up
    /// - Returns: Array of attendee emails, or empty if event not found
    private func getAttendeesFromLiveEvent(meetingId: String?) -> [String] {
        guard let meetingId = meetingId else { return [] }

        // Search in cached events
        let calendarManager = EASCalendarManager.shared

        // First try exact match
        if let event = calendarManager.cachedEvents.first(where: { $0.id == meetingId }) {
            debugLog("Found live event by exact ID: \(event.subject)", module: "SummaryEmail", level: .info)
            return event.attendeeEmails
        }

        // Try matching by ID prefix (for recurring event instances like "id_0", "id_1")
        let baseId = meetingId.components(separatedBy: "_").first ?? meetingId
        if let event = calendarManager.cachedEvents.first(where: { $0.id.hasPrefix(baseId) }) {
            debugLog("Found live event by base ID: \(event.subject)", module: "SummaryEmail", level: .info)
            return event.attendeeEmails
        }

        debugLog("Live event not found for ID: \(meetingId)", module: "SummaryEmail", level: .info)
        return []
    }

    /// Get current user's email from EAS credentials
    private func getCurrentUserEmail() -> String? {
        guard let credentials = keychainManager.loadEASCredentials() else {
            return nil
        }

        // Username might be in format DOMAIN\user or user@domain.com
        let username = credentials.username

        // If it's already an email, return it
        if username.contains("@") {
            return username.lowercased()
        }

        // Otherwise, append corporate domain
        let cleanUsername = username.components(separatedBy: "\\").last ?? username
        return (cleanUsername + Env.corporateEmailDomain).lowercased()
    }

    /// Filter recipients based on settings
    /// - If includeSelfInSummaryEmail is true, returns all attendees
    /// - If false, removes current user from the list
    private func filterRecipients(attendees: [String], currentUserEmail: String?) -> [String] {
        // If setting is enabled, include everyone (including self)
        if includeSelfInSummaryEmail {
            return attendees
        }

        // Otherwise, filter out current user
        guard let currentEmail = currentUserEmail?.lowercased() else {
            return attendees
        }

        return attendees.filter { email in
            email.lowercased() != currentEmail
        }
    }

    /// Get live event from cache by meeting ID
    private func getLiveEvent(meetingId: String?) -> EASCalendarEvent? {
        guard let meetingId = meetingId else { return nil }

        let calendarManager = EASCalendarManager.shared

        // Try exact match
        if let event = calendarManager.cachedEvents.first(where: { $0.id == meetingId }) {
            return event
        }

        // Try base ID for recurring events
        let baseId = meetingId.components(separatedBy: "_").first ?? meetingId
        return calendarManager.cachedEvents.first(where: { $0.id.hasPrefix(baseId) })
    }

    /// Build HTML email body using template
    private func buildEmailHTML(
        recording: Recording,
        summary: String,
        event: EASCalendarEvent?,
        attendeeNames: [String]
    ) -> String {
        let preset = recording.preset ?? .projectMeeting

        // Use live event subject (most up-to-date) or fall back to stored/title
        let meetingSubject = event?.subject ?? recording.linkedMeetingSubject ?? recording.title

        let context = SummaryEmailContext(
            meetingSubject: meetingSubject,
            meetingLocation: event?.location,
            meetingStartTime: event?.startTime,
            meetingEndTime: event?.endTime,
            meetingDuration: event?.formattedDuration,
            attendeeNames: attendeeNames,
            attendeeCount: attendeeNames.isEmpty
                ? recording.linkedMeetingAttendeeEmails.count
                : attendeeNames.count,
            recordingTitle: recording.title,
            presetDisplayName: preset.displayName,
            summaryMarkdown: summary,
            feedbackEmail: "t.grushko@pos-credit.ru"
        )

        return SummaryEmailTemplate.render(context: context)
    }

    /// Get attendee names from live event, or format emails as fallback
    /// Includes organizer in the list
    private func getAttendeeNames(from event: EASCalendarEvent?, fallbackEmails: [String]) -> [String] {
        // If we have live event with attendees, use their names
        if let event = event {
            var names = event.humanAttendees.map { attendee in
                // Use name if available, otherwise format email
                if !attendee.name.isEmpty {
                    return formatName(attendee.name)
                } else {
                    return formatEmailAsName(attendee.email)
                }
            }

            // Add organizer if present and not already in the list
            if let organizer = event.organizer {
                let organizerName = !organizer.name.isEmpty
                    ? formatName(organizer.name)
                    : formatEmailAsName(organizer.email)

                // Check if organizer is already in the list (by comparing formatted names)
                if !names.contains(organizerName) {
                    names.insert(organizerName, at: 0) // Organizer first
                }
            }

            if !names.isEmpty {
                return names
            }
        }

        // Fallback: format emails as names
        return fallbackEmails.map { formatEmailAsName($0) }
    }

    /// Format full name to short format (Грушко Т.А.)
    /// Supports formats: "Фамилия Имя Отчество" → "Фамилия И.О."
    private func formatName(_ name: String) -> String {
        let parts = name.components(separatedBy: " ").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return name }

        // Format: "Фамилия Имя Отчество" → "Фамилия И.О."
        let lastName = parts[0]
        let firstInitial = parts[1].prefix(1)

        if parts.count >= 3 {
            // Has patronymic
            let patronymicInitial = parts[2].prefix(1)
            return "\(lastName) \(firstInitial).\(patronymicInitial)."
        } else {
            // Only first name
            return "\(lastName) \(firstInitial)."
        }
    }

    /// Format email address as name (ivanov.i → Ivanov I.)
    private func formatEmailAsName(_ email: String) -> String {
        let localPart = email.components(separatedBy: "@").first ?? email
        // Replace dots/underscores with spaces and capitalize
        let formatted = localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return formatted
    }

    /// Encode email array to JSON string
    private func encodeEmails(_ emails: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(emails),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

// MARK: - Recording Extension for Summary Email

extension Recording {
    /// Whether this recording can send a summary email
    var canSendSummary: Bool {
        hasLinkedMeeting && summaryText != nil
    }

    /// Whether summary was already sent
    var hasSentSummary: Bool {
        summarySentAt != nil
    }

    /// List of emails the summary was sent to
    var summarySentToEmailList: [String] {
        guard let json = summarySentToEmails,
              let data = json.data(using: .utf8),
              let emails = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return emails
    }
}
