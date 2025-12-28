import Foundation

/// Сервис инкрементальной синхронизации календаря через Delta Queries
final class CalendarSyncService {

    private let baseURL = "https://graph.microsoft.com/v1.0"
    private let authManager: MSALAuthManager
    private let storage: SyncStorageProtocol

    /// Delta link хранится между сессиями
    private var deltaLink: String? {
        get { storage.getDeltaLink() }
        set { storage.saveDeltaLink(newValue) }
    }

    init(authManager: MSALAuthManager, storage: SyncStorageProtocol = UserDefaultsSyncStorage()) {
        self.authManager = authManager
        self.storage = storage
    }

    // MARK: - Public API

    /// Синхронизировать календарь
    /// - Returns: Результат синхронизации (обновлённые события, удалённые ID)
    func sync() async throws -> SyncResult {
        if let deltaLink = deltaLink {
            return try await incrementalSync(deltaLink: deltaLink)
        } else {
            return try await fullSync()
        }
    }

    /// Сбросить delta link (принудительная полная синхронизация)
    func resetSync() {
        deltaLink = nil
        print("[CalendarSyncService] Sync reset, next sync will be full")
    }

    /// Дата последней синхронизации
    var lastSyncDate: Date? {
        storage.getLastSyncDate()
    }

    // MARK: - Full Sync

    private func fullSync() async throws -> SyncResult {
        print("[CalendarSyncService] Starting full sync...")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        // Синхронизируем события за последние 3 месяца + 3 месяца вперёд
        let startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        let endDate = Calendar.current.date(byAdding: .month, value: 3, to: Date())!

        var components = URLComponents(string: "\(baseURL)/me/calendarView/delta")!
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: formatter.string(from: startDate)),
            URLQueryItem(name: "endDateTime", value: formatter.string(from: endDate)),
            URLQueryItem(name: "$select", value: "id,subject,start,end,attendees,organizer,isOrganizer,iCalUId,bodyPreview,webLink,location")
        ]

        guard let url = components.url else {
            throw GraphError.invalidResponse
        }

        let result = try await fetchAllPages(startingFrom: url)
        storage.saveLastSyncDate(Date())

        print("[CalendarSyncService] Full sync completed: \(result.updatedEvents.count) events")
        return SyncResult(
            updatedEvents: result.updatedEvents,
            deletedEventIds: result.deletedEventIds,
            isFullSync: true
        )
    }

    // MARK: - Incremental Sync

    private func incrementalSync(deltaLink: String) async throws -> SyncResult {
        print("[CalendarSyncService] Starting incremental sync...")

        guard let url = URL(string: deltaLink) else {
            // Невалидный delta link — делаем full sync
            self.deltaLink = nil
            return try await fullSync()
        }

        do {
            let result = try await fetchAllPages(startingFrom: url)
            storage.saveLastSyncDate(Date())

            print("[CalendarSyncService] Incremental sync completed: \(result.updatedEvents.count) updated, \(result.deletedEventIds.count) deleted")
            return SyncResult(
                updatedEvents: result.updatedEvents,
                deletedEventIds: result.deletedEventIds,
                isFullSync: false
            )
        } catch GraphError.httpError(statusCode: 410, _) {
            // 410 Gone = delta link expired
            print("[CalendarSyncService] Delta link expired, performing full sync")
            self.deltaLink = nil
            return try await fullSync()
        }
    }

    // MARK: - Pagination

    private func fetchAllPages(startingFrom url: URL) async throws -> (updatedEvents: [GraphEvent], deletedEventIds: [String]) {
        var allEvents: [GraphEvent] = []
        var deletedIds: [String] = []
        var currentURL: URL? = url

        while let url = currentURL {
            let token = try await authManager.acquireTokenSilently()

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GraphError.invalidResponse
            }

            if httpResponse.statusCode == 410 {
                throw GraphError.httpError(statusCode: 410, data: data)
            }

            guard httpResponse.statusCode == 200 else {
                throw GraphError.httpError(statusCode: httpResponse.statusCode, data: data)
            }

            let decoded = try JSONDecoder().decode(GraphEventsResponse.self, from: data)

            for event in decoded.value {
                if event.removed != nil {
                    deletedIds.append(event.id)
                } else {
                    allEvents.append(event)
                }
            }

            // Проверяем наличие следующей страницы
            if let nextLink = decoded.nextLink {
                currentURL = URL(string: nextLink)
            } else {
                // Сохраняем delta link для следующей синхронизации
                self.deltaLink = decoded.deltaLink
                currentURL = nil
            }
        }

        return (allEvents, deletedIds)
    }
}

// MARK: - Storage Protocol

/// Протокол хранилища для данных синхронизации
protocol SyncStorageProtocol {
    func getDeltaLink() -> String?
    func saveDeltaLink(_ link: String?)
    func getLastSyncDate() -> Date?
    func saveLastSyncDate(_ date: Date?)
}

// MARK: - UserDefaults Storage

/// Хранилище на основе UserDefaults
final class UserDefaultsSyncStorage: SyncStorageProtocol {
    private let deltaLinkKey = "com.vantaspeech.outlookDeltaLink"
    private let lastSyncKey = "com.vantaspeech.outlookLastSync"

    func getDeltaLink() -> String? {
        UserDefaults.standard.string(forKey: deltaLinkKey)
    }

    func saveDeltaLink(_ link: String?) {
        if let link = link {
            UserDefaults.standard.set(link, forKey: deltaLinkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: deltaLinkKey)
        }
    }

    func getLastSyncDate() -> Date? {
        UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    func saveLastSyncDate(_ date: Date?) {
        if let date = date {
            UserDefaults.standard.set(date, forKey: lastSyncKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSyncKey)
        }
    }
}

// MARK: - Secure Storage (Keychain)

/// Безопасное хранилище на основе Keychain
final class SecureSyncStorage: SyncStorageProtocol {
    private let service = "com.vantaspeech.calendar"

    enum Key: String {
        case deltaLink = "outlook_delta_link"
        case lastSyncDate = "last_sync_date"
    }

    func getDeltaLink() -> String? {
        retrieve(for: .deltaLink)
    }

    func saveDeltaLink(_ link: String?) {
        if let link = link {
            try? save(link, for: .deltaLink)
        } else {
            delete(for: .deltaLink)
        }
    }

    func getLastSyncDate() -> Date? {
        guard let dateString = retrieve(for: .lastSyncDate) else { return nil }
        return ISO8601DateFormatter().date(from: dateString)
    }

    func saveLastSyncDate(_ date: Date?) {
        if let date = date {
            let dateString = ISO8601DateFormatter().string(from: date)
            try? save(dateString, for: .lastSyncDate)
        } else {
            delete(for: .lastSyncDate)
        }
    }

    // MARK: - Keychain Operations

    private func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]

        // Удаляем существующий
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func retrieve(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func delete(for key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}
