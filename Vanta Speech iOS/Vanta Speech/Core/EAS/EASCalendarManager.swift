import Foundation
import Combine

/// Manager for Exchange ActiveSync calendar operations
@MainActor
final class EASCalendarManager: ObservableObject {

    // MARK: - Singleton

    static let shared = EASCalendarManager()

    // MARK: - Published State

    @Published private(set) var isConnected = false
    @Published private(set) var isSyncing = false
    @Published private(set) var cachedEvents: [EASCalendarEvent] = []
    @Published private(set) var lastError: EASError?
    @Published private(set) var lastSyncDate: Date?

    // MARK: - Private Properties

    private let client: EASClient
    private let keychainManager: KeychainManager
    private var syncState: EASSyncState

    // MARK: - Initialization

    private init(
        client: EASClient = EASClient(),
        keychainManager: KeychainManager = .shared
    ) {
        self.client = client
        self.keychainManager = keychainManager
        self.syncState = keychainManager.loadEASSyncState() ?? .initial

        // Check if we have stored credentials
        isConnected = keychainManager.hasEASCredentials
    }

    // MARK: - Public API

    /// Connect with new credentials
    func connect(serverURL: String, username: String, password: String) async -> Bool {
        // Create credentials with persistent device ID
        let deviceId = keychainManager.getOrCreateEASDeviceId()
        let credentials = EASCredentials(
            serverURL: serverURL,
            username: username,
            password: password,
            deviceId: deviceId
        )

        do {
            // Save credentials first
            try keychainManager.saveEASCredentials(credentials)

            // Test connection
            let serverInfo = try await client.testConnection()

            // Check if server supports required version
            guard serverInfo.supportsVersion14 else {
                lastError = .serverError(statusCode: 0, message: "Server does not support EAS 14.1")
                keychainManager.deleteEASCredentials()
                return false
            }

            // Discover calendar folder
            try await discoverCalendarFolder()

            isConnected = true
            lastError = nil
            return true

        } catch let error as EASError {
            lastError = error
            if error.shouldClearCredentials {
                keychainManager.deleteEASCredentials()
            }
            isConnected = false
            return false
        } catch {
            lastError = .unknown(error.localizedDescription)
            keychainManager.deleteEASCredentials()
            isConnected = false
            return false
        }
    }

    /// Disconnect and clear credentials
    func disconnect() {
        keychainManager.clearAllEASData()
        isConnected = false
        cachedEvents = []
        syncState = .initial
        lastError = nil
        lastSyncDate = nil
    }

    /// Sync calendar events from server
    func syncEvents() async {
        guard isConnected else {
            lastError = .noCredentials
            return
        }

        guard !isSyncing else { return }

        isSyncing = true
        lastError = nil

        do {
            // Ensure we have calendar folder
            if !syncState.hasDiscoveredCalendar {
                try await discoverCalendarFolder()
            }

            guard let folderId = syncState.calendarFolderId else {
                throw EASError.calendarFolderNotFound
            }

            // Check if this is initial sync (SyncKey = "0")
            let isInitialSync = syncState.calendarSyncKey == "0"

            // Perform sync
            var response = try await client.sync(
                folderId: folderId,
                syncKey: syncState.calendarSyncKey,
                getChanges: !isInitialSync, // Don't request changes on initial sync
                policyKey: syncState.policyKey ?? "0"
            )

            // Handle provisioning required (status 142/144)
            if response.status == 142 || response.status == 144 {
                print("[EAS] Sync requires provisioning, status: \(response.status)")
                try await performProvisioning()

                // Retry sync with new policy key
                response = try await client.sync(
                    folderId: folderId,
                    syncKey: syncState.calendarSyncKey,
                    getChanges: !isInitialSync,
                    policyKey: syncState.policyKey ?? "0"
                )
            }

            // Check for errors (status 1 = success)
            if response.status != 1 {
                print("[EAS] Sync failed with status: \(response.status)")
                throw EASError.serverError(statusCode: response.status, message: "Sync status: \(response.status)")
            }

            // Update sync key
            syncState.calendarSyncKey = response.syncKey
            try? keychainManager.saveEASSyncState(syncState)

            // If this was initial sync, we need to do a second sync to get actual events
            if isInitialSync {
                print("[EAS] Initial sync complete, SyncKey: \(response.syncKey). Fetching events...")
                // Recursively call to get events with new SyncKey
                isSyncing = false
                await syncEvents()
                return
            }

            // Update events from response
            if response.events.isEmpty {
                print("[EAS] No events in response")
            } else {
                print("[EAS] Received \(response.events.count) events")
                mergeEvents(response.events)
            }

            syncState.lastSyncDate = Date()
            try? keychainManager.saveEASSyncState(syncState)
            lastSyncDate = syncState.lastSyncDate

            // Handle more available
            if response.moreAvailable {
                print("[EAS] More events available, continuing sync...")
                isSyncing = false
                await syncEvents()
                return
            }

        } catch let error as EASError {
            lastError = error
            if error.shouldClearCredentials {
                disconnect()
            }
        } catch {
            lastError = .unknown(error.localizedDescription)
        }

        isSyncing = false
    }

    /// Create a calendar event (meeting summary)
    func createEvent(_ event: EASCalendarEvent) async throws -> String {
        guard isConnected else {
            throw EASError.noCredentials
        }

        guard let folderId = syncState.calendarFolderId else {
            throw EASError.calendarFolderNotFound
        }

        var eventToCreate = event
        if eventToCreate.clientId == nil {
            eventToCreate.clientId = UUID().uuidString
        }

        let response = try await client.sync(
            folderId: folderId,
            syncKey: syncState.calendarSyncKey,
            getChanges: false,
            addItems: [eventToCreate],
            policyKey: syncState.policyKey ?? "0"
        )

        // Update sync key
        syncState.calendarSyncKey = response.syncKey
        try? keychainManager.saveEASSyncState(syncState)

        return eventToCreate.clientId ?? ""
    }

    /// Create meeting summary from original event
    func createMeetingSummary(
        originalEvent: EASCalendarEvent,
        summaryHtml: String
    ) async throws -> String {
        let summaryEvent = EASCalendarEvent.createMeetingSummary(
            originalEvent: originalEvent,
            summaryHtml: summaryHtml
        )
        return try await createEvent(summaryEvent)
    }

    // MARK: - Private Methods

    private func discoverCalendarFolder() async throws {
        // Try FolderSync, handle provisioning if required
        let policyKey = syncState.policyKey ?? "0"
        var response = try await client.folderSync(syncKey: syncState.folderSyncKey, policyKey: policyKey)

        // Status 108/142/144 means provisioning required
        if response.status == 108 || response.status == 142 || response.status == 144 {
            print("[EAS] Provisioning required, status: \(response.status)")
            try await performProvisioning()

            // Retry FolderSync with new policy key
            let newPolicyKey = syncState.policyKey ?? "0"
            response = try await client.folderSync(syncKey: syncState.folderSyncKey, policyKey: newPolicyKey)
        }

        // Check for other errors (status 1 = success)
        if response.status != 1 {
            print("[EAS] FolderSync failed with status: \(response.status)")
            throw EASError.serverError(statusCode: response.status, message: "FolderSync status: \(response.status)")
        }

        // Update folder sync key
        syncState.folderSyncKey = response.syncKey

        // Find calendar folder
        guard let calendarFolder = response.calendarFolder else {
            throw EASError.calendarFolderNotFound
        }

        syncState.calendarFolderId = calendarFolder.serverId
        syncState.calendarSyncKey = "0" // Reset calendar sync key for new folder

        // Save state
        try? keychainManager.saveEASSyncState(syncState)
    }

    private func performProvisioning() async throws {
        print("[EAS] Starting provisioning...")

        let provisionResponse = try await client.provision()

        if provisionResponse.isSuccess, let policyKey = provisionResponse.policyKey {
            print("[EAS] Provisioning successful, policyKey: \(policyKey)")
            syncState.policyKey = policyKey
            try? keychainManager.saveEASSyncState(syncState)
        } else {
            print("[EAS] Provisioning failed, status: \(provisionResponse.status)")
            if provisionResponse.status == 2 {
                throw EASError.provisioningDenied
            }
            throw EASError.serverError(statusCode: provisionResponse.status, message: "Provisioning status: \(provisionResponse.status)")
        }
    }

    private func mergeEvents(_ newEvents: [EASCalendarEvent]) {
        var eventMap = Dictionary(uniqueKeysWithValues: cachedEvents.map { ($0.id, $0) })

        // Date range for expanding recurring events: 30 days back, 60 days forward
        let rangeStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let rangeEnd = Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date()

        for event in newEvents {
            if event.isRecurring {
                // Expand recurring event into occurrences
                let occurrences = event.expandOccurrences(from: rangeStart, to: rangeEnd)
                print("[EAS] Expanded recurring event '\(event.subject)' into \(occurrences.count) occurrences")
                for occurrence in occurrences {
                    eventMap[occurrence.id] = occurrence
                }
            } else {
                eventMap[event.id] = event
            }
        }

        cachedEvents = Array(eventMap.values).sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Convenience

    /// Get events for a specific date
    func events(for date: Date) -> [EASCalendarEvent] {
        let calendar = Calendar.current
        return cachedEvents.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: date)
        }
    }

    /// Get today's events
    var todayEvents: [EASCalendarEvent] {
        events(for: Date())
    }

    /// Get upcoming events (next 7 days)
    var upcomingEvents: [EASCalendarEvent] {
        let now = Date()
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        return cachedEvents.filter { event in
            event.startTime >= now && event.startTime <= weekFromNow
        }
    }

    /// Get recent events (sorted by date, most recent first)
    var recentEvents: [EASCalendarEvent] {
        cachedEvents.sorted { $0.startTime > $1.startTime }
    }

    /// Get all events sorted chronologically
    var allEventsSorted: [EASCalendarEvent] {
        cachedEvents.sorted { $0.startTime < $1.startTime }
    }
}
