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
    private var fullSyncTask: Task<Void, Never>?

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

        fullSyncTask = Task.detached { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isSyncing = false
                self.fullSyncTask = nil
                debugLog("Force full sync completed", module: "EAS", level: .info)
            }
            await self.performFullSyncInternal()
        }
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

    /// Internal sync implementation
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
                continueSync = false

                // Check if this is initial sync (SyncKey = "0")
                let isInitialSync = syncState.calendarSyncKey == "0"

                debugLog("Starting sync iteration: syncKey=\(syncState.calendarSyncKey), isInitial=\(isInitialSync)", module: "EAS", level: .info)

                // Perform sync
                var response = try await client.sync(
                    folderId: folderId,
                    syncKey: syncState.calendarSyncKey,
                    getChanges: !isInitialSync,
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
                continueSync = false

                let isInitialSync = syncState.calendarSyncKey == "0"

                debugLog("Starting sync iteration: syncKey=\(syncState.calendarSyncKey), isInitial=\(isInitialSync)", module: "EAS", level: .info)

                var response = try await client.sync(
                    folderId: folderId,
                    syncKey: syncState.calendarSyncKey,
                    getChanges: !isInitialSync,
                    policyKey: syncState.policyKey ?? "0"
                )

                // Handle provisioning required
                if response.status == 142 || response.status == 144 {
                    debugLog("Sync requires provisioning, status: \(response.status)", module: "EAS", level: .info)
                    try await performProvisioning()

                    response = try await client.sync(
                        folderId: folderId,
                        syncKey: syncState.calendarSyncKey,
                        getChanges: !isInitialSync,
                        policyKey: syncState.policyKey ?? "0"
                    )
                }

                if response.status != 1 {
                    debugLog("Sync failed with status: \(response.status)", module: "EAS", level: .error)
                    throw EASError.serverError(statusCode: response.status, message: "Sync status: \(response.status)")
                }

                syncState.calendarSyncKey = response.syncKey
                try? keychainManager.saveEASSyncState(syncState)

                if isInitialSync {
                    debugLog("Initial sync complete, SyncKey: \(response.syncKey). Continuing...", module: "EAS", level: .info)
                    continueSync = true
                    continue
                }

                if !response.events.isEmpty {
                    debugLog("Received \(response.events.count) events", module: "EAS", level: .info)
                    allEvents.append(contentsOf: response.events)
                }

                syncState.lastSyncDate = Date()
                try? keychainManager.saveEASSyncState(syncState)
                lastSyncDate = syncState.lastSyncDate

                if response.moreAvailable {
                    debugLog("More events available...", module: "EAS", level: .info)
                    continueSync = true
                }
            }

            // Process events with new logic: merge masters by UID, extrapolate series
            let processedEvents = processEvents(allEvents)

            debugLog("Full sync complete. Total: \(processedEvents.count) events (from \(allEvents.count) raw)", module: "EAS", level: .info)
            cachedEvents = processedEvents
            try? keychainManager.saveEASCachedEvents(cachedEvents)

        } catch let error as EASError {
            debugLog("Full sync failed: \(error)", module: "EAS", level: .error)
            lastError = error
            if error.shouldClearCredentials {
                disconnect()
            }
        } catch is CancellationError {
            debugLog("Full sync was cancelled", module: "EAS", level: .warning)
        } catch {
            debugLog("Full sync failed: \(error.localizedDescription)", module: "EAS", level: .error)
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
        let policyKey = syncState.policyKey ?? "0"
        var response = try await client.folderSync(syncKey: syncState.folderSyncKey, policyKey: policyKey)

        // Status 108/142/144 means provisioning required
        if response.status == 108 || response.status == 142 || response.status == 144 {
            debugLog("Provisioning required, status: \(response.status)", module: "EAS", level: .info)
            try await performProvisioning()

            let newPolicyKey = syncState.policyKey ?? "0"
            response = try await client.folderSync(syncKey: syncState.folderSyncKey, policyKey: newPolicyKey)
        }

        if response.status != 1 {
            debugLog("FolderSync failed with status: \(response.status)", module: "EAS", level: .error)
            throw EASError.serverError(statusCode: response.status, message: "FolderSync status: \(response.status)")
        }

        syncState.folderSyncKey = response.syncKey

        guard let calendarFolder = response.calendarFolder else {
            throw EASError.calendarFolderNotFound
        }

        syncState.calendarFolderId = calendarFolder.serverId
        syncState.calendarSyncKey = "0"

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
            debugLog("Removed deleted event: \(deletedId)", module: "EAS", level: .info)
        }

        // Add or update events
        for event in newEvents {
            if event.isCancelled {
                eventMap.removeValue(forKey: event.id)
            } else {
                eventMap[event.id] = event
            }
        }

        cachedEvents = eventMap.values.sorted { $0.startTime < $1.startTime }
        try? keychainManager.saveEASCachedEvents(cachedEvents)
        debugLog("Saved \(cachedEvents.count) events to cache", module: "EAS", level: .info)
    }

    /// Process events: group masters by (Subject + BaseTime + Recurrence), extrapolate series
    private func processEvents(_ events: [EASCalendarEvent]) -> [EASCalendarEvent] {
        let calendar = Calendar.current
        let now = Date()
        let rangeStart = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        let rangeEnd = calendar.date(byAdding: .month, value: 3, to: now) ?? now

        // Separate recurring masters, exceptions, and single events
        var allMasters: [EASCalendarEvent] = []
        var orphanExceptions: [EASCalendarEvent] = []
        var singleEvents: [EASCalendarEvent] = []

        for event in events {
            if event.isCancelled { continue }
            
            if event.isRecurring && !event.isException {
                allMasters.append(event)
            } else if event.isException {
                orphanExceptions.append(event)
            } else {
                singleEvents.append(event)
            }
        }

        var processedEvents: [EASCalendarEvent] = []
        
        // Add single events as-is
        processedEvents.append(contentsOf: singleEvents)
        
        // Process orphan exceptions as standalone
        processedEvents.append(contentsOf: orphanExceptions)

        // Group masters by series key (Subject + BaseTime + Recurrence)
        var mastersBySeries: [String: [EASCalendarEvent]] = [:]
        
        for master in allMasters {
            let seriesKey = makeSeriesKey(for: master)
            mastersBySeries[seriesKey, default: []].append(master)
        }
        
        // Process each series group
        for (seriesKey, masters) in mastersBySeries {
            guard let firstMaster = masters.first else { continue }
            
            debugLog("Processing series '\(firstMaster.subject)' with \(masters.count) master(s), key: \(seriesKey)", module: "EAS", level: .info)
            
            // Collect all exceptions from all masters in this series
            var allExceptions: [EASException] = []
            for master in masters {
                if let exceptions = master.exceptions {
                    allExceptions.append(contentsOf: exceptions)
                }
            }
            
            debugLog("  Masters: \(masters.map { "\($0.id)@\(dateToString($0.startTime))" }.joined(separator: ", "))", module: "EAS", level: .info)
            debugLog("  Exceptions: \(allExceptions.count) total", module: "EAS", level: .info)
            
            guard let recurrence = firstMaster.recurrence else {
                processedEvents.append(contentsOf: masters)
                continue
            }
            
            // Determine base time (most common time from exceptions)
            let baseTime = determineBaseTime(from: allExceptions, masters: masters)
            let calendar = Calendar.current
            let baseHour = calendar.component(.hour, from: baseTime)
            let baseMinute = calendar.component(.minute, from: baseTime)
            debugLog("  Base time: \(baseHour):\(baseMinute) (from \(allExceptions.count) exceptions)", module: "EAS", level: .info)
            
            // Find time range for this series (from exceptions and masters)
            let exceptionDates = allExceptions.map(\.originalStartTime)
            let masterStartDates = masters.map(\.startTime)
            
            // Series start: earliest of exception dates OR earliest master start date
            let seriesStart: Date
            if let minException = exceptionDates.min(), let minMaster = masterStartDates.min() {
                seriesStart = min(minException, minMaster)
            } else if let minException = exceptionDates.min() {
                seriesStart = minException
            } else if let minMaster = masterStartDates.min() {
                seriesStart = minMaster
            } else {
                seriesStart = firstMaster.startTime
            }
            
            // Find the latest until date from all masters (for series that actually end)
            let maxUntil = masters.compactMap { $0.recurrence?.until }.max()
            if let until = maxUntil {
                debugLog("  Latest until date: \(dateToString(until))", module: "EAS", level: .info)
            }
            
            // Series end: consider until date from masters, exception dates, and sync range
            let seriesEnd: Date
            if let maxUntil = maxUntil {
                // Master has explicit end date - use it (limited by sync range)
                seriesEnd = min(rangeEnd, maxUntil)
            } else if let maxException = exceptionDates.max() {
                // No until date, but have exceptions - expand at least to last exception
                seriesEnd = max(rangeEnd, maxException)
            } else {
                // No until, no exceptions - use sync range
                seriesEnd = rangeEnd
            }
            
            debugLog("  Series range: \(dateToString(seriesStart)) to \(dateToString(seriesEnd))", module: "EAS", level: .info)
            debugLog("  Global range: \(dateToString(rangeStart)) to \(dateToString(rangeEnd))", module: "EAS", level: .info)
            
            // Calculate actual expansion range
            let expandStart = max(rangeStart, seriesStart)
            let expandEnd = min(rangeEnd, seriesEnd)
            debugLog("  Expand range: \(dateToString(expandStart)) to \(dateToString(expandEnd))", module: "EAS", level: .info)
            
            // Use the master with most exceptions as template
            let bestMaster = masters.sorted { 
                ($0.exceptions?.count ?? 0) > ($1.exceptions?.count ?? 0)
            }.first ?? firstMaster
            
            let duration = bestMaster.endTime.timeIntervalSince(bestMaster.startTime)
            
            // Create virtual master for this series
            // Use the latest until date from all masters (if any)
            let virtualRecurrence = EASRecurrence(
                type: recurrence.type,
                interval: recurrence.interval,
                dayOfWeek: recurrence.dayOfWeek,
                dayOfMonth: recurrence.dayOfMonth,
                until: maxUntil  // Use actual until date to stop expansion
            )
            
            let virtualMaster = EASCalendarEvent(
                id: bestMaster.id,
                uid: bestMaster.uid,
                subject: bestMaster.subject,
                startTime: seriesStart,
                endTime: seriesStart.addingTimeInterval(duration),
                location: bestMaster.location,
                body: bestMaster.body,
                organizer: bestMaster.organizer,
                attendees: bestMaster.attendees,
                isAllDay: bestMaster.isAllDay,
                recurrence: virtualRecurrence,
                meetingStatus: bestMaster.meetingStatus,
                exceptions: allExceptions.isEmpty ? nil : allExceptions,
                clientId: bestMaster.clientId,
                isException: false,
                originalStartTime: nil
            )
            
            // Expand only within series time range (limited by global range)
            // expandStart and expandEnd already calculated above for logging
            
            let occurrences = expandOccurrences(
                for: virtualMaster,
                from: expandStart,
                to: expandEnd,
                baseTime: baseTime,
                duration: duration
            )
            
            debugLog("Expanded '\(virtualMaster.subject)' into \(occurrences.count) occurrences (Series: \(seriesKey))", module: "EAS", level: .info)
            processedEvents.append(contentsOf: occurrences)
        }

        // Sort by start time
        return processedEvents.sorted { $0.startTime < $1.startTime }
    }
    
    /// Create a series key from master for grouping
    private func makeSeriesKey(for master: EASCalendarEvent) -> String {
        guard let recurrence = master.recurrence else {
            return master.id  // Non-recurring events are their own series
        }
        
        // Get base time from master's exceptions
        let baseTime: String
        if let exceptions = master.exceptions, !exceptions.isEmpty {
            let calendar = Calendar.current
            var timeComponents: [(hour: Int, minute: Int)] = []
            for ex in exceptions where !ex.isDeleted {
                let hour = calendar.component(.hour, from: ex.originalStartTime)
                let minute = calendar.component(.minute, from: ex.originalStartTime)
                timeComponents.append((hour, minute))
            }
            let grouped = Dictionary(grouping: timeComponents) { "\($0.hour):\($0.minute)" }
            if let mostCommon = grouped.max(by: { $0.value.count < $1.value.count })?.key {
                baseTime = mostCommon
            } else {
                baseTime = "\(calendar.component(.hour, from: master.startTime)):\(calendar.component(.minute, from: master.startTime))"
            }
        } else {
            let calendar = Calendar.current
            baseTime = "\(calendar.component(.hour, from: master.startTime)):\(calendar.component(.minute, from: master.startTime))"
        }
        
        // Recurrence signature
        let dayOfWeek = recurrence.dayOfWeek ?? 0
        let recSignature = "\(recurrence.type.rawValue)_\(recurrence.interval)_\(dayOfWeek)"
        
        return "\(master.subject)|\(baseTime)|\(recSignature)"
    }
    
    /// Determine the most common time from exceptions
    private func determineBaseTime(from exceptions: [EASException], masters: [EASCalendarEvent]) -> Date {
        let calendar = Calendar.current
        
        // Collect time components from non-deleted exceptions
        var timeComponents: [(hour: Int, minute: Int)] = []
        
        for exception in exceptions {
            if !exception.isDeleted {
                let hour = calendar.component(.hour, from: exception.originalStartTime)
                let minute = calendar.component(.minute, from: exception.originalStartTime)
                timeComponents.append((hour, minute))
            }
        }
        
        // Find most common time (convert to string for Hashable)
        let grouped = Dictionary(grouping: timeComponents) { "\($0.hour):\($0.minute)" }
        if let mostCommonKey = grouped.max(by: { $0.value.count < $1.value.count })?.key {
            let parts = mostCommonKey.split(separator: ":")
            if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
                // Create a date with this time
                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = hour
                components.minute = minute
                return calendar.date(from: components) ?? Date()
            }
        }
        
        // Fallback to first master's start time
        return masters.first?.startTime ?? Date()
    }
    
    /// Expand occurrences for a master using base time
    /// Handles: regular occurrences, time changes, date moves, and deletions
    private func expandOccurrences(
        for master: EASCalendarEvent,
        from rangeStart: Date,
        to rangeEnd: Date,
        baseTime: Date,
        duration: TimeInterval,
        maxOccurrences: Int = 200
    ) -> [EASCalendarEvent] {
        guard let recurrence = master.recurrence else {
            return [master]
        }

        var occurrences: [EASCalendarEvent] = []
        let calendar = Calendar.current
        
        // Get base time components
        let baseHour = calendar.component(.hour, from: baseTime)
        let baseMinute = calendar.component(.minute, from: baseTime)

        // Build exception map by original start time day
        let exceptionMap = master.exceptions?.reduce(into: [Date: EASException]()) { map, ex in
            let key = calendar.startOfDay(for: ex.originalStartTime)
            map[key] = ex
        } ?? [:]
        
        // Find exceptions that moved to a different date (not just time change)
        // These need to be added separately at their new date
        let movedExceptions = master.exceptions?.filter { ex in
            guard let startTime = ex.startTime, !ex.isDeleted else { return false }
            let originalDay = calendar.startOfDay(for: ex.originalStartTime)
            let newDay = calendar.startOfDay(for: startTime)
            return originalDay != newDay
        } ?? []
        
        var movedOccurrenceIds = Set<String>() // Track which moved exceptions we've added

        // Start from rangeStart
        var currentDate = rangeStart
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

            let occurrenceDay = calendar.startOfDay(for: currentDate)
            
            // Check for moved exceptions that target this date (ALWAYS, not just for pattern-matching days)
            // This handles exceptions moved to days that don't match the recurrence pattern
            for movedEx in movedExceptions {
                guard let movedStartTime = movedEx.startTime else { continue }
                let movedDay = calendar.startOfDay(for: movedStartTime)
                let movedId = "\(master.id)_moved_\(movedEx.originalStartTime.timeIntervalSince1970)"
                
                if movedDay == occurrenceDay && !movedOccurrenceIds.contains(movedId) {
                    // This moved exception belongs on this day
                    let occurrenceEnd = movedEx.endTime ?? movedStartTime.addingTimeInterval(duration)
                    
                    let occurrence = EASCalendarEvent(
                        id: movedId,
                        uid: master.uid,
                        subject: movedEx.subject ?? master.subject,
                        startTime: movedStartTime,
                        endTime: occurrenceEnd,
                        location: movedEx.location ?? master.location,
                        body: master.body,
                        organizer: master.organizer,
                        attendees: master.attendees,
                        isAllDay: master.isAllDay,
                        recurrence: nil,
                        meetingStatus: master.meetingStatus,
                        exceptions: nil,
                        clientId: nil,
                        isException: true,
                        originalStartTime: movedEx.originalStartTime
                    )
                    occurrences.append(occurrence)
                    movedOccurrenceIds.insert(movedId)
                    occurrenceIndex += 1
                }
            }
            
            if shouldInclude {
                // Handle regular occurrence or same-day exception
                if let exception = exceptionMap[occurrenceDay] {
                    if !exception.isDeleted {
                        // Check if this is a moved exception (handled above)
                        if let startTime = exception.startTime {
                            let originalDay = calendar.startOfDay(for: exception.originalStartTime)
                            let newDay = calendar.startOfDay(for: startTime)
                            if originalDay != newDay {
                                // This exception moved to a different date - skip here
                                // It will be created when we reach the target date
                                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(86400)
                                continue
                            }
                        }
                        
                        // Same-day modification - use exception's data
                        let occurrenceStart = exception.startTime ?? calendar.date(
                            bySettingHour: baseHour,
                            minute: baseMinute,
                            second: 0,
                            of: occurrenceDay
                        )!
                        let occurrenceEnd = exception.endTime ?? occurrenceStart.addingTimeInterval(duration)
                        
                        let occurrence = EASCalendarEvent(
                            id: "\(master.id)_exception_\(occurrenceIndex)",
                            uid: master.uid,
                            subject: exception.subject ?? master.subject,
                            startTime: occurrenceStart,
                            endTime: occurrenceEnd,
                            location: exception.location ?? master.location,
                            body: master.body,
                            organizer: master.organizer,
                            attendees: master.attendees,
                            isAllDay: master.isAllDay,
                            recurrence: nil,
                            meetingStatus: master.meetingStatus,
                            exceptions: nil,
                            clientId: nil,
                            isException: true,
                            originalStartTime: exception.originalStartTime
                        )
                        occurrences.append(occurrence)
                        occurrenceIndex += 1
                    }
                    // If deleted, skip entirely
                } else {
                    // Regular occurrence - use base time
                    guard let occurrenceStart = calendar.date(
                        bySettingHour: baseHour,
                        minute: baseMinute,
                        second: 0,
                        of: occurrenceDay
                    ) else {
                        currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(86400)
                        continue
                    }

                    let occurrence = EASCalendarEvent(
                        id: "\(master.id)_\(occurrenceIndex)",
                        uid: master.uid,
                        subject: master.subject,
                        startTime: occurrenceStart,
                        endTime: occurrenceStart.addingTimeInterval(duration),
                        location: master.location,
                        body: master.body,
                        organizer: master.organizer,
                        attendees: master.attendees,
                        isAllDay: master.isAllDay,
                        recurrence: nil,
                        meetingStatus: master.meetingStatus,
                        exceptions: nil,
                        clientId: nil,
                        isException: false,
                        originalStartTime: nil
                    )
                    occurrences.append(occurrence)
                    occurrenceIndex += 1
                }
            }

            // Advance to next potential occurrence
            switch recurrence.type {
            case .daily:
                currentDate = calendar.date(byAdding: .day, value: recurrence.interval, to: currentDate) ?? currentDate.addingTimeInterval(86400)
            case .weekly:
                // For weekly recurrence, we need to handle interval correctly
                // Move forward by 1 day to continue checking days in current week
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(86400)
                
                // If we've moved past all days in the current week that match the pattern,
                // and interval > 1, we need to skip ahead by (interval - 1) weeks
                if recurrence.interval > 1 {
                    // Check if there are any more matching days in this week
                    let weekday = calendar.component(.weekday, from: currentDate)
                    let hasMoreDaysInWeek = (weekday...7).contains { day in
                        recurrence.includesWeekday(day)
                    }
                    
                    // If no more matching days in this week, skip to next occurrence week
                    if !hasMoreDaysInWeek {
                        let daysToSkip = (recurrence.interval - 1) * 7
                        currentDate = calendar.date(byAdding: .day, value: daysToSkip, to: currentDate) ?? currentDate.addingTimeInterval(TimeInterval(86400 * daysToSkip))
                    }
                }
            case .monthly, .monthlyNth:
                currentDate = calendar.date(byAdding: .month, value: recurrence.interval, to: currentDate) ?? currentDate.addingTimeInterval(2592000)
            case .yearly, .yearlyNth:
                currentDate = calendar.date(byAdding: .year, value: recurrence.interval, to: currentDate) ?? currentDate.addingTimeInterval(31536000)
            }
        }

        return occurrences.isEmpty ? [master] : occurrences
    }

    // MARK: - Helpers
    
    private func dateToString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
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

    /// Find the most probable meeting for a recording based on time overlap
    func findMostProbableMeeting(for recording: Recording) -> EASCalendarEvent? {
        let recordingEnd = recording.createdAt
        let recordingStart = recordingEnd.addingTimeInterval(-recording.duration)

        let calendar = Calendar.current

        let sameDayEvents = cachedEvents.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: recordingEnd) ||
            calendar.isDate(event.endTime, inSameDayAs: recordingEnd)
        }

        guard !sameDayEvents.isEmpty else { return nil }

        let overlappingEvents = sameDayEvents.filter { event in
            event.startTime <= recordingEnd && event.endTime >= recordingStart
        }

        if !overlappingEvents.isEmpty {
            return overlappingEvents.max { event1, event2 in
                let overlap1 = calculateOverlap(event: event1, recordingStart: recordingStart, recordingEnd: recordingEnd)
                let overlap2 = calculateOverlap(event: event2, recordingStart: recordingStart, recordingEnd: recordingEnd)
                return overlap1 < overlap2
            }
        }

        return sameDayEvents.min { event1, event2 in
            let diff1 = abs(event1.endTime.timeIntervalSince(recordingEnd))
            let diff2 = abs(event2.endTime.timeIntervalSince(recordingEnd))
            return diff1 < diff2
        }
    }

    private func calculateOverlap(event: EASCalendarEvent, recordingStart: Date, recordingEnd: Date) -> TimeInterval {
        let overlapStart = max(event.startTime, recordingStart)
        let overlapEnd = min(event.endTime, recordingEnd)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
}
