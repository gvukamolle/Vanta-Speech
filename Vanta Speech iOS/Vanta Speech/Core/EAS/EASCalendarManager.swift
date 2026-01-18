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

        // Load cached events from Keychain
        if let cached = keychainManager.loadEASCachedEvents() {
            cachedEvents = cached
            debugLog("Loaded \(cached.count) cached events from Keychain", module: "EAS", level: .info)
        }
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

            // Automatically sync events after successful connection
            await syncEvents()

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

    /// Force full sync - resets syncKey to get all events and replaces cache
    func forceFullSync() async {
        guard isConnected else {
            lastError = .noCredentials
            return
        }

        guard !isSyncing else {
            debugLog("forceFullSync: sync already in progress, skipping", module: "EAS", level: .info)
            return
        }

        // Set flag IMMEDIATELY to prevent race conditions
        isSyncing = true

        debugLog("Force full sync requested - resetting syncKey", module: "EAS", level: .info)

        // Reset calendar sync key to trigger full sync
        syncState.calendarSyncKey = "0"
        try? keychainManager.saveEASSyncState(syncState)

        // Use detached task to prevent SwiftUI from cancelling the sync
        // when ScrollView .refreshable view updates
        // IMPORTANT: isSyncing = false is set INSIDE the detached task
        // to prevent premature flag reset if parent task is cancelled
        Task.detached { @MainActor [weak self] in
            await self?.performFullSyncInternal()
            self?.isSyncing = false
            debugLog("Force full sync completed", module: "EAS", level: .info)
        }

        // Don't await the detached task - it will complete independently
        // This prevents SwiftUI task cancellation from affecting the sync
    }

    /// Sync calendar events from server
    func syncEvents() async {
        guard isConnected else {
            lastError = .noCredentials
            return
        }

        guard !isSyncing else {
            debugLog("Sync already in progress, skipping", module: "EAS", level: .info)
            return
        }

        isSyncing = true
        await performSyncInternal()
        isSyncing = false
    }

    /// Internal sync implementation - called by both syncEvents() and forceFullSync()
    /// IMPORTANT: Caller must set isSyncing = true before calling and = false after
    private func performSyncInternal() async {
        lastError = nil

        do {
            // Ensure we have calendar folder
            if !syncState.hasDiscoveredCalendar {
                try await discoverCalendarFolder()
            }

            guard let folderId = syncState.calendarFolderId else {
                throw EASError.calendarFolderNotFound
            }

            // Use a loop instead of recursion to handle initial sync and moreAvailable
            var continueSync = true

            while continueSync {
                continueSync = false  // Default to stopping after this iteration

                // Check if this is initial sync (SyncKey = "0")
                let isInitialSync = syncState.calendarSyncKey == "0"

                debugLog("Starting sync iteration: syncKey=\(syncState.calendarSyncKey), isInitial=\(isInitialSync)", module: "EAS", level: .info)

                // Perform sync
                var response = try await client.sync(
                    folderId: folderId,
                    syncKey: syncState.calendarSyncKey,
                    getChanges: !isInitialSync, // Don't request changes on initial sync
                    policyKey: syncState.policyKey ?? "0"
                )

                // Handle provisioning required (status 142/144)
                if response.status == 142 || response.status == 144 {
                    debugLog("Sync requires provisioning, status: \(response.status)", module: "EAS", level: .info)
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
                    debugLog("Sync failed with status: \(response.status)", module: "EAS", level: .error)
                    throw EASError.serverError(statusCode: response.status, message: "Sync status: \(response.status)")
                }

                // Update sync key
                syncState.calendarSyncKey = response.syncKey
                try? keychainManager.saveEASSyncState(syncState)

                // If this was initial sync, continue to get actual events
                if isInitialSync {
                    debugLog("Initial sync complete, SyncKey: \(response.syncKey). Continuing to fetch events...", module: "EAS", level: .info)
                    continueSync = true
                    continue
                }

                // Update events from response
                if response.events.isEmpty && response.deletedEventIds.isEmpty {
                    debugLog("No events in response", module: "EAS", level: .info)
                } else {
                    debugLog("Received \(response.events.count) events, \(response.deletedEventIds.count) deletions", module: "EAS", level: .info)
                    mergeEvents(response.events, deletedIds: response.deletedEventIds)
                }

                syncState.lastSyncDate = Date()
                try? keychainManager.saveEASSyncState(syncState)
                lastSyncDate = syncState.lastSyncDate

                // Handle more available
                if response.moreAvailable {
                    debugLog("More events available, continuing sync...", module: "EAS", level: .info)
                    continueSync = true
                }
            }

        } catch let error as EASError {
            lastError = error
            if error.shouldClearCredentials {
                disconnect()
            }
        } catch {
            lastError = .unknown(error.localizedDescription)
        }
    }

    /// Internal full sync implementation - replaces cache instead of merging
    /// Used by forceFullSync() to avoid triggering @Published during sync
    private func performFullSyncInternal() async {
        lastError = nil
        var allEvents: [EASCalendarEvent] = []

        do {
            // Ensure we have calendar folder
            if !syncState.hasDiscoveredCalendar {
                try await discoverCalendarFolder()
            }

            guard let folderId = syncState.calendarFolderId else {
                throw EASError.calendarFolderNotFound
            }

            // Use a loop instead of recursion to handle initial sync and moreAvailable
            var continueSync = true

            while continueSync {
                continueSync = false  // Default to stopping after this iteration

                // Check if this is initial sync (SyncKey = "0")
                let isInitialSync = syncState.calendarSyncKey == "0"

                debugLog("Starting sync iteration: syncKey=\(syncState.calendarSyncKey), isInitial=\(isInitialSync)", module: "EAS", level: .info)

                // Perform sync
                var response = try await client.sync(
                    folderId: folderId,
                    syncKey: syncState.calendarSyncKey,
                    getChanges: !isInitialSync, // Don't request changes on initial sync
                    policyKey: syncState.policyKey ?? "0"
                )

                // Handle provisioning required (status 142/144)
                if response.status == 142 || response.status == 144 {
                    debugLog("Sync requires provisioning, status: \(response.status)", module: "EAS", level: .info)
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
                    debugLog("Sync failed with status: \(response.status)", module: "EAS", level: .error)
                    throw EASError.serverError(statusCode: response.status, message: "Sync status: \(response.status)")
                }

                // Update sync key
                syncState.calendarSyncKey = response.syncKey
                try? keychainManager.saveEASSyncState(syncState)

                // If this was initial sync, continue to get actual events
                if isInitialSync {
                    debugLog("Initial sync complete, SyncKey: \(response.syncKey). Continuing to fetch events...", module: "EAS", level: .info)
                    continueSync = true
                    continue
                }

                // Accumulate events (instead of merging)
                if !response.events.isEmpty {
                    debugLog("Received \(response.events.count) events in this batch", module: "EAS", level: .info)
                    allEvents.append(contentsOf: response.events)
                }

                syncState.lastSyncDate = Date()
                try? keychainManager.saveEASSyncState(syncState)
                lastSyncDate = syncState.lastSyncDate

                // Handle more available
                if response.moreAvailable {
                    debugLog("More events available, continuing sync...", module: "EAS", level: .info)
                    continueSync = true
                }
            }

            // After all iterations complete - replace cache with new events (single @Published trigger)
            // No client-side filtering - show everything server returns
            let calendar = Calendar.current
            let now = Date()
            // Wide range for recurring events expansion only
            let rangeStart = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            let rangeEnd = calendar.date(byAdding: .month, value: 3, to: now) ?? now

            // Process events: expand recurring events, no date filtering
            var processedEvents: [EASCalendarEvent] = []

            for event in allEvents {
                // Skip cancelled events
                if event.isCancelled {
                    continue
                }

                if event.isRecurring {
                    // Expand recurring event into occurrences
                    let occurrences = event.expandOccurrences(from: rangeStart, to: rangeEnd)
                    debugLog("Expanded recurring event '\(event.subject)' into \(occurrences.count) occurrences", module: "EAS", level: .info)
                    processedEvents.append(contentsOf: occurrences)
                } else {
                    // Add single events without filtering
                    processedEvents.append(event)
                }
            }

            // Sort by start time
            processedEvents.sort { $0.startTime < $1.startTime }

            debugLog("Full sync complete. Replacing cache with \(processedEvents.count) events (from \(allEvents.count) raw)", module: "EAS", level: .info)
            cachedEvents = processedEvents
            try? keychainManager.saveEASCachedEvents(cachedEvents)

        } catch let error as EASError {
            debugLog("Full sync failed with EASError: \(error)", module: "EAS", level: .error)
            lastError = error
            if error.shouldClearCredentials {
                disconnect()
            }
        } catch is CancellationError {
            debugLog("Full sync was cancelled", module: "EAS", level: .warning)
        } catch {
            debugLog("Full sync failed with error: \(error.localizedDescription)", module: "EAS", level: .error)
            lastError = .unknown(error.localizedDescription)
        }
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
            debugLog("Provisioning required, status: \(response.status)", module: "EAS", level: .info)
            try await performProvisioning()

            // Retry FolderSync with new policy key
            let newPolicyKey = syncState.policyKey ?? "0"
            response = try await client.folderSync(syncKey: syncState.folderSyncKey, policyKey: newPolicyKey)
        }

        // Check for other errors (status 1 = success)
        if response.status != 1 {
            debugLog("FolderSync failed with status: \(response.status)", module: "EAS", level: .error)
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
        debugLog("Starting provisioning...", module: "EAS", level: .info)

        let provisionResponse = try await client.provision()

        if provisionResponse.isSuccess, let policyKey = provisionResponse.policyKey {
            debugLog("Provisioning successful, policyKey: \(policyKey)", module: "EAS", level: .info)
            syncState.policyKey = policyKey
            try? keychainManager.saveEASSyncState(syncState)
        } else {
            debugLog("Provisioning failed, status: \(provisionResponse.status)", module: "EAS", level: .error)
            if provisionResponse.status == 2 {
                throw EASError.provisioningDenied
            }
            throw EASError.serverError(statusCode: provisionResponse.status, message: "Provisioning status: \(provisionResponse.status)")
        }
    }

    private func mergeEvents(_ newEvents: [EASCalendarEvent], deletedIds: [String] = []) {
        var eventMap = Dictionary(uniqueKeysWithValues: cachedEvents.map { ($0.id, $0) })

        // Remove deleted events
        for deletedId in deletedIds {
            eventMap.removeValue(forKey: deletedId)
            // Also remove occurrences for recurring events (id format: "baseId_occurrenceId")
            let keysToRemove = eventMap.keys.filter { $0.hasPrefix("\(deletedId)_") }
            for key in keysToRemove {
                eventMap.removeValue(forKey: key)
            }
            debugLog("Removed deleted event: \(deletedId)", module: "EAS", level: .info)
        }

        let calendar = Calendar.current
        let now = Date()

        // Wide range for recurring events expansion only (no filtering)
        let rangeStart = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        let rangeEnd = calendar.date(byAdding: .month, value: 3, to: now) ?? now

        for event in newEvents {
            // Skip cancelled events
            if event.isCancelled {
                // Remove from cache if it was previously there
                eventMap.removeValue(forKey: event.id)
                let keysToRemove = eventMap.keys.filter { $0.hasPrefix("\(event.id)_") }
                for key in keysToRemove {
                    eventMap.removeValue(forKey: key)
                }
                continue
            }

            if event.isRecurring {
                // Expand recurring event into occurrences
                let occurrences = event.expandOccurrences(from: rangeStart, to: rangeEnd)
                debugLog("Expanded recurring event '\(event.subject)' into \(occurrences.count) occurrences", module: "EAS", level: .info)
                for occurrence in occurrences {
                    eventMap[occurrence.id] = occurrence
                }
            } else {
                eventMap[event.id] = event
            }
        }

        // No filtering - keep all events
        cachedEvents = eventMap.values.sorted { $0.startTime < $1.startTime }

        // Persist cached events to Keychain
        try? keychainManager.saveEASCachedEvents(cachedEvents)
        debugLog("Saved \(cachedEvents.count) events to Keychain cache", module: "EAS", level: .info)
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

    /// Find the most probable meeting for a recording based on start time proximity
    func findMostProbableMeeting(for recording: Recording) -> EASCalendarEvent? {
        let recordingStart = recording.createdAt
        let calendar = Calendar.current

        // Filter events for the same day as the recording
        let sameDayEvents = cachedEvents.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: recordingStart)
        }

        guard !sameDayEvents.isEmpty else { return nil }

        // Return event with minimum time difference from recording start
        return sameDayEvents.min { event1, event2 in
            let diff1 = abs(event1.startTime.timeIntervalSince(recordingStart))
            let diff2 = abs(event2.startTime.timeIntervalSince(recordingStart))
            return diff1 < diff2
        }
    }
}
