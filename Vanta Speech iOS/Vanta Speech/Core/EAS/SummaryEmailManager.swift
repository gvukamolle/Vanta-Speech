import Foundation
import SwiftUI

/// Manager for sending meeting summary emails to participants
@MainActor
final class SummaryEmailManager: ObservableObject {
    static let shared = SummaryEmailManager()

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

        let attendees = recording.linkedMeetingAttendeeEmails
        guard !attendees.isEmpty else {
            debugLog("Cannot send summary: no attendees", module: "SummaryEmail", level: .warning)
            return false
        }

        // Filter out current user from recipients
        let currentUserEmail = getCurrentUserEmail()
        let recipients = filterRecipients(attendees: attendees, currentUserEmail: currentUserEmail)

        guard !recipients.isEmpty else {
            debugLog("Cannot send summary: all attendees filtered out", module: "SummaryEmail", level: .warning)
            return false
        }

        // Build email
        let meetingSubject = recording.linkedMeetingSubject ?? "Встреча"
        let subject = "Саммари: \(meetingSubject)"
        let body = formatSummaryAsPlainText(summary: summary, meetingSubject: meetingSubject)

        isSending = true
        lastError = nil

        do {
            let success = try await emailService.sendEmail(
                to: recipients,
                subject: subject,
                body: body
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

    /// Filter recipients, removing current user and organizer if it's the same as current user
    private func filterRecipients(attendees: [String], currentUserEmail: String?) -> [String] {
        guard let currentEmail = currentUserEmail?.lowercased() else {
            return attendees
        }

        return attendees.filter { email in
            email.lowercased() != currentEmail
        }
    }

    /// Format summary as plain text for email body
    private func formatSummaryAsPlainText(summary: String, meetingSubject: String) -> String {
        """
        Саммари встречи: \(meetingSubject)
        ================================================

        \(summary)

        ------------------------------------------------
        Отправлено из Vanta Speech
        """
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
        hasLinkedMeeting &&
        summaryText != nil &&
        !linkedMeetingAttendeeEmails.isEmpty
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
