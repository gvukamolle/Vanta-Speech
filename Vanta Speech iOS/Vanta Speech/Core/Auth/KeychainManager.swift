import Foundation
import Security

/// Manages secure storage of credentials in iOS Keychain
final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.vanta.speech"
    private let sessionKey = "user_session"
    private let easCredentialsKey = "eas_credentials"
    private let easDeviceIdKey = "eas_device_id"
    private let easSyncStateKey = "eas_sync_state"
    private let googleRefreshTokenKey = "google_refresh_token"
    private let googleUserInfoKey = "google_user_info"

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
        let data = try JSONEncoder().encode(credentials)
        try save(data: data, forKey: easCredentialsKey)
    }

    /// Load saved EAS credentials
    func loadEASCredentials() -> EASCredentials? {
        guard let data = load(forKey: easCredentialsKey) else { return nil }
        return try? JSONDecoder().decode(EASCredentials.self, from: data)
    }

    /// Delete EAS credentials
    func deleteEASCredentials() {
        delete(forKey: easCredentialsKey)
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

    /// Clear all EAS data (credentials, device ID, sync state)
    func clearAllEASData() {
        delete(forKey: easCredentialsKey)
        delete(forKey: easDeviceIdKey)
        delete(forKey: easSyncStateKey)
    }

    // MARK: - Google OAuth Storage

    /// Save Google refresh token
    func saveGoogleRefreshToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data: data, forKey: googleRefreshTokenKey)
    }

    /// Load Google refresh token
    func loadGoogleRefreshToken() -> String? {
        guard let data = load(forKey: googleRefreshTokenKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete Google refresh token
    func deleteGoogleRefreshToken() {
        delete(forKey: googleRefreshTokenKey)
    }

    /// Save Google user info (email, name)
    func saveGoogleUserInfo(_ info: GoogleUserInfo) throws {
        let dict: [String: String?] = [
            "email": info.email,
            "displayName": info.displayName,
            "profileImageURL": info.profileImageURL?.absoluteString
        ]
        let data = try JSONEncoder().encode(dict)
        try save(data: data, forKey: googleUserInfoKey)
    }

    /// Load Google user info
    func loadGoogleUserInfo() -> GoogleUserInfo? {
        guard let data = load(forKey: googleUserInfoKey),
              let dict = try? JSONDecoder().decode([String: String?].self, from: data),
              let email = dict["email"] ?? nil else {
            return nil
        }
        return GoogleUserInfo(
            email: email,
            displayName: dict["displayName"] ?? nil,
            profileImageURL: (dict["profileImageURL"] ?? nil).flatMap { URL(string: $0) }
        )
    }

    /// Delete all Google credentials
    func deleteGoogleCredentials() {
        delete(forKey: googleRefreshTokenKey)
        delete(forKey: googleUserInfoKey)
    }

    /// Check if Google credentials are stored
    var hasGoogleCredentials: Bool {
        loadGoogleRefreshToken() != nil
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
