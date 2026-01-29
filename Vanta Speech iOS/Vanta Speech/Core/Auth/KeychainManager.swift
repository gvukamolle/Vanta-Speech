import Foundation
import Security

/// Manages secure storage of credentials in iOS Keychain
final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.vanta.speech"
    private let sessionKey = "user_session"
    private let easCredentialsKey = "eas_credentials"
    private let easPasswordKey = "eas_password"
    private let easDeviceIdKey = "eas_device_id"
    private let easSyncStateKey = "eas_sync_state"
    private let easCachedEventsKey = "eas_cached_events"
    
    // MARK: - Confluence Credentials Storage
    private let confluenceUsernameKey = "confluence_username"
    private let confluencePasswordKey = "confluence_password"
    
    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Session Storage

    func saveSession(_ session: UserSession) throws {
        let data = try JSONEncoder().encode(session)
        try save(data: data, forKey: sessionKey)
    }

    func loadSession() -> UserSession? {
        guard let data = load(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    func deleteSession() {
        delete(forKey: sessionKey)
    }

    // MARK: - EAS Credentials Storage

    /// Save EAS credentials for Exchange ActiveSync authentication
    func saveEASCredentials(_ credentials: EASCredentials) throws {
        try saveEASPassword(credentials.password)

        let storage = EASCredentialsStorage(
            serverURL: credentials.serverURL,
            username: credentials.username,
            deviceId: credentials.deviceId
        )
        let data = try JSONEncoder().encode(storage)
        try save(data: data, forKey: easCredentialsKey)
    }

    /// Load saved EAS credentials
    func loadEASCredentials() -> EASCredentials? {
        guard let data = load(forKey: easCredentialsKey) else { return nil }

        if let legacyCredentials = try? JSONDecoder().decode(EASCredentials.self, from: data) {
            // Migrate legacy storage (password embedded) to split storage
            try? saveEASCredentials(legacyCredentials)
            return legacyCredentials
        }

        guard let storage = try? JSONDecoder().decode(EASCredentialsStorage.self, from: data) else {
            return nil
        }

        guard let password = loadEASPassword() else {
            return nil
        }

        return EASCredentials(
            serverURL: storage.serverURL,
            username: storage.username,
            password: password,
            deviceId: storage.deviceId
        )
    }

    /// Delete EAS credentials
    func deleteEASCredentials() {
        delete(forKey: easCredentialsKey)
        deleteEASPassword()
    }

    /// Check if EAS credentials are stored
    var hasEASCredentials: Bool {
        loadEASCredentials() != nil
    }

    // MARK: - EAS Device ID

    /// Get or create a persistent device ID for EAS
    /// DeviceId must be alphanumeric only (A-Z, a-z, 0-9), max 32 characters per MS-ASCMD spec
    func getOrCreateEASDeviceId() -> String {
        // Try to load existing device ID
        if let data = load(forKey: easDeviceIdKey),
           let deviceId = String(data: data, encoding: .utf8),
           isValidEASDeviceId(deviceId) {
            return deviceId
        }

        // Generate new device ID - alphanumeric only, 32 characters
        // Use UUID without dashes, take first 32 chars
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let deviceId = String(uuid.prefix(32))

        // Save it
        if let data = deviceId.data(using: .utf8) {
            try? save(data: data, forKey: easDeviceIdKey)
        }

        return deviceId
    }

    /// Check if device ID is valid per EAS spec (alphanumeric only, 1-32 chars)
    private func isValidEASDeviceId(_ deviceId: String) -> Bool {
        let alphanumeric = CharacterSet.alphanumerics
        return deviceId.count >= 1 &&
               deviceId.count <= 32 &&
               deviceId.unicodeScalars.allSatisfy { alphanumeric.contains($0) }
    }

    // MARK: - EAS Sync State

    /// Save EAS sync state
    func saveEASSyncState(_ state: EASSyncState) throws {
        let data = try JSONEncoder().encode(state)
        try save(data: data, forKey: easSyncStateKey)
    }

    /// Load EAS sync state
    func loadEASSyncState() -> EASSyncState? {
        guard let data = load(forKey: easSyncStateKey) else { return nil }
        return try? JSONDecoder().decode(EASSyncState.self, from: data)
    }

    /// Delete EAS sync state
    func deleteEASSyncState() {
        delete(forKey: easSyncStateKey)
    }

    // MARK: - EAS Cached Events

    private var easCacheDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(service, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var easCachedEventsURL: URL {
        easCacheDirectory.appendingPathComponent("eas_cached_events.json")
    }

    /// Save EAS cached events
    func saveEASCachedEvents(_ events: [EASCalendarEvent]) throws {
        let data = try JSONEncoder().encode(events)
        try data.write(to: easCachedEventsURL, options: [.atomic, .completeFileProtection])
        // Ensure legacy Keychain cache is removed
        delete(forKey: easCachedEventsKey)
    }

    /// Load EAS cached events
    func loadEASCachedEvents() -> [EASCalendarEvent]? {
        if let data = try? Data(contentsOf: easCachedEventsURL) {
            return try? JSONDecoder().decode([EASCalendarEvent].self, from: data)
        }

        // Migration from legacy Keychain storage
        guard let legacyData = load(forKey: easCachedEventsKey),
              let events = try? JSONDecoder().decode([EASCalendarEvent].self, from: legacyData) else {
            return nil
        }
        try? saveEASCachedEvents(events)
        return events
    }

    /// Delete EAS cached events
    func deleteEASCachedEvents() {
        try? fileManager.removeItem(at: easCachedEventsURL)
        delete(forKey: easCachedEventsKey)
    }

    /// Clear all EAS data (credentials, device ID, sync state, cached events)
    func clearAllEASData() {
        delete(forKey: easCredentialsKey)
        deleteEASPassword()
        delete(forKey: easDeviceIdKey)
        delete(forKey: easSyncStateKey)
        delete(forKey: easCachedEventsKey)
    }

    // MARK: - EAS Password Storage

    private func saveEASPassword(_ password: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data: data, forKey: easPasswordKey)
    }

    private func loadEASPassword() -> String? {
        guard let data = load(forKey: easPasswordKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteEASPassword() {
        delete(forKey: easPasswordKey)
    }

    // MARK: - Internal Storage

    private struct EASCredentialsStorage: Codable {
        let serverURL: String
        let username: String
        let deviceId: String
    }

    // MARK: - Confluence Credentials
    
    /// Save Confluence credentials
    func saveConfluenceCredentials(username: String, password: String) throws {
        guard let usernameData = username.data(using: .utf8),
              let passwordData = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data: usernameData, forKey: confluenceUsernameKey)
        try save(data: passwordData, forKey: confluencePasswordKey)
    }
    
    /// Load Confluence credentials
    func loadConfluenceCredentials() -> (username: String, password: String)? {
        guard let usernameData = load(forKey: confluenceUsernameKey),
              let passwordData = load(forKey: confluencePasswordKey),
              let username = String(data: usernameData, encoding: .utf8),
              let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }
        return (username, password)
    }
    
    /// Delete Confluence credentials
    func deleteConfluenceCredentials() {
        delete(forKey: confluenceUsernameKey)
        delete(forKey: confluencePasswordKey)
    }
    
    /// Check if Confluence credentials exist
    var hasConfluenceCredentials: Bool {
        loadConfluenceCredentials() != nil
    }
    
    // MARK: - Generic Keychain Operations

    private func save(data: Data, forKey key: String) throws {
        // Delete any existing item first
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save to Keychain: \(status)"
            case .encodingFailed:
                return "Failed to encode data for Keychain"
            }
        }
    }
}
