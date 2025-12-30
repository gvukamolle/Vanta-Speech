import Foundation
import Combine

/// High-level coordinator for EWS calendar integration
@MainActor
final class EWSCalendarManager: ObservableObject {
    static let shared = EWSCalendarManager()

    // MARK: - Published State

    @Published private(set) var isConnected = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var cachedEvents: [EWSEvent] = []
    @Published private(set) var lastError: Error?
    @Published private(set) var serverURL: String?
    @Published private(set) var userEmail: String?

    // MARK: - Private

    private let authManager = EWSAuthManager.shared
    private var service: EWSCalendarService?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupBindings()
        restoreConnection()
    }

    // MARK: - Connection

    /// Connect to EWS server with credentials
    func connect(
        serverURL: String,
        domain: String,
        username: String,
        password: String
    ) async -> Bool {
        lastError = nil

        let success = await authManager.authenticate(
            serverURL: serverURL,
            domain: domain,
            username: username,
            password: password
        )

        if success {
            await setupService()
            await syncEvents()
        } else {
            lastError = authManager.lastError
        }

        return success
    }

    /// Disconnect and clear all data
    func disconnect() {
        authManager.signOut()
        service = nil
        cachedEvents = []
        lastSyncDate = nil
        serverURL = nil
        userEmail = nil
        isConnected = false
    }

    // MARK: - Sync

    /// Sync calendar events for today and upcoming week
    func syncEvents() async {
        guard isConnected, let service = service else { return }

        isSyncing = true
        lastError = nil

        do {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let endDate = calendar.date(byAdding: .day, value: 7, to: startOfDay)!

            let events = try await service.findEvents(from: startOfDay, to: endDate)

            cachedEvents = events.sorted { $0.startDate < $1.startDate }
            lastSyncDate = Date()

            debugLog("Synced \(events.count) events", module: "EWSCalendarManager")
        } catch {
            lastError = error
            debugLog("Sync failed: \(error.localizedDescription)", module: "EWSCalendarManager", level: .error)
            debugCaptureError(error, context: "EWSCalendarManager sync")
        }

        isSyncing = false
    }

    /// Get events for today
    func getTodayEvents() -> [EWSEvent] {
        let calendar = Calendar.current
        return cachedEvents.filter { calendar.isDateInToday($0.startDate) }
    }

    /// Get current or next event (within 15 minutes)
    func getCurrentOrNextEvent() -> EWSEvent? {
        let now = Date()
        let threshold = now.addingTimeInterval(15 * 60) // 15 minutes ahead

        // First check for ongoing event
        if let current = cachedEvents.first(where: { $0.startDate <= now && $0.endDate > now }) {
            return current
        }

        // Then check for upcoming event
        return cachedEvents.first { $0.startDate > now && $0.startDate <= threshold }
    }

    // MARK: - Event Operations

    /// Update event body with meeting summary
    func updateEventBody(
        event: EWSEvent,
        htmlContent: String,
        notifyAttendees: Bool = false
    ) async throws {
        guard let service = service else {
            throw EWSError.notConfigured
        }

        // Append to existing body or replace
        let newBody: String
        if let existingBody = event.bodyHtml, !existingBody.isEmpty {
            newBody = existingBody + "<hr/>" + htmlContent
        } else {
            newBody = htmlContent
        }

        let newChangeKey = try await service.updateEventBody(
            itemId: event.itemId,
            changeKey: event.changeKey,
            bodyHtml: newBody,
            notifyAttendees: notifyAttendees
        )

        // Update cached event with new changeKey
        if let index = cachedEvents.firstIndex(where: { $0.itemId == event.itemId }) {
            let updated = EWSEvent(
                itemId: event.itemId,
                changeKey: newChangeKey,
                subject: event.subject,
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                bodyHtml: newBody,
                bodyText: event.bodyText,
                attendees: event.attendees,
                organizerEmail: event.organizerEmail,
                organizerName: event.organizerName,
                isAllDay: event.isAllDay
            )
            cachedEvents[index] = updated
        }

        debugLog("Updated event body for: \(event.subject)", module: "EWSCalendarManager")
    }

    /// Send email to event attendees
    func sendSummaryToAttendees(
        event: EWSEvent,
        subject: String,
        htmlContent: String,
        includeOptional: Bool = false
    ) async throws {
        guard let service = service else {
            throw EWSError.notConfigured
        }

        var recipients = event.attendees
            .filter { $0.isRequired || includeOptional }
            .map { $0.email }

        // Add organizer if not in list
        if let organizer = event.organizerEmail, !recipients.contains(organizer) {
            recipients.append(organizer)
        }

        guard !recipients.isEmpty else {
            throw EWSError.serverError("Нет получателей для отправки")
        }

        let email = EWSNewEmail(
            toRecipients: recipients,
            subject: subject,
            bodyHtml: htmlContent
        )

        try await service.sendEmail(email)

        debugLog("Sent email to \(recipients.count) recipients", module: "EWSCalendarManager")
    }

    /// Create a new calendar event
    func createEvent(_ event: EWSNewEvent) async throws -> String {
        guard let service = service else {
            throw EWSError.notConfigured
        }

        let itemId = try await service.createEvent(event)
        await syncEvents() // Refresh cache

        debugLog("Created event: \(event.subject)", module: "EWSCalendarManager")
        return itemId
    }

    /// Search contacts for autocomplete
    func searchContacts(query: String) async throws -> [EWSContact] {
        guard let service = service else {
            throw EWSError.notConfigured
        }

        return try await service.resolveNames(query: query)
    }

    // MARK: - Private

    private func setupBindings() {
        authManager.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuth in
                self?.isConnected = isAuth
            }
            .store(in: &cancellables)

        authManager.$credentials
            .receive(on: DispatchQueue.main)
            .sink { [weak self] creds in
                self?.serverURL = creds?.serverURL
                self?.userEmail = creds?.email ?? creds?.username
            }
            .store(in: &cancellables)
    }

    private func restoreConnection() {
        if authManager.isAuthenticated {
            isConnected = true
            serverURL = authManager.credentials?.serverURL
            userEmail = authManager.credentials?.email ?? authManager.credentials?.username

            Task {
                await setupService()
                await syncEvents()
            }
        }
    }

    private func setupService() async {
        do {
            let client = try authManager.createClient()
            service = EWSCalendarService(client: client)
        } catch {
            debugLog("Failed to create service: \(error)", module: "EWSCalendarManager", level: .error)
            debugCaptureError(error, context: "EWSCalendarManager setupService")
            lastError = error
        }
    }
}

// MARK: - Summary HTML Builder

extension EWSCalendarManager {

    /// Build HTML summary for event body
    static func buildSummaryHTML(
        title: String,
        summary: String,
        transcription: String? = nil,
        date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ru_RU")

        var html = """
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px;">
            <h2 style="color: #1a1a1a; border-bottom: 2px solid #007AFF; padding-bottom: 8px;">
                📝 \(escapeHTML(title))
            </h2>
            <p style="color: #666; font-size: 14px;">
                Создано: \(formatter.string(from: date)) • Vanta Speech
            </p>

            <h3 style="color: #333; margin-top: 24px;">Краткое содержание</h3>
            <div style="background: #f5f5f7; padding: 16px; border-radius: 8px; white-space: pre-wrap;">
                \(escapeHTML(summary))
            </div>
        """

        if let transcription = transcription, !transcription.isEmpty {
            html += """

            <details style="margin-top: 24px;">
                <summary style="cursor: pointer; color: #007AFF; font-weight: 600;">
                    Полная транскрипция
                </summary>
                <div style="background: #fafafa; padding: 16px; border-radius: 8px; margin-top: 8px; white-space: pre-wrap; font-size: 13px; color: #444;">
                    \(escapeHTML(transcription))
                </div>
            </details>
            """
        }

        html += """

            <p style="color: #999; font-size: 12px; margin-top: 24px; border-top: 1px solid #eee; padding-top: 12px;">
                Автоматически сгенерировано приложением Vanta Speech
            </p>
        </div>
        """

        return html
    }

    /// Build HTML email for attendees
    static func buildEmailHTML(
        meetingTitle: String,
        summary: String,
        transcription: String? = nil,
        date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ru_RU")

        var html = """
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto;">
            <p>Коллеги,</p>
            <p>Прикрепляю краткое содержание нашей встречи <strong>\(escapeHTML(meetingTitle))</strong>.</p>

            <div style="background: #f5f5f7; padding: 20px; border-radius: 12px; margin: 20px 0;">
                <h3 style="color: #333; margin-top: 0;">📋 Краткое содержание</h3>
                <div style="white-space: pre-wrap; color: #1a1a1a;">
                    \(escapeHTML(summary))
                </div>
            </div>
        """

        if let transcription = transcription, !transcription.isEmpty {
            html += """
            <details style="margin: 20px 0;">
                <summary style="cursor: pointer; color: #007AFF; font-weight: 600; padding: 8px 0;">
                    📝 Показать полную транскрипцию
                </summary>
                <div style="background: #fafafa; padding: 16px; border-radius: 8px; margin-top: 8px; white-space: pre-wrap; font-size: 13px; color: #444; max-height: 400px; overflow-y: auto;">
                    \(escapeHTML(transcription))
                </div>
            </details>
            """
        }

        html += """

            <p style="color: #666; margin-top: 24px;">
                С уважением,<br/>
                <em>Автоматически сгенерировано приложением Vanta Speech</em>
            </p>
        </div>
        """

        return html
    }

    private static func escapeHTML(_ string: String) -> String {
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        return escaped
    }
}
