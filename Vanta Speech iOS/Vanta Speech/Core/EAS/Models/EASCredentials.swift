import Foundation

/// Credentials for Exchange ActiveSync authentication
struct EASCredentials: Codable, Equatable {
    /// Server URL (e.g., "https://mail.company.com")
    let serverURL: String

    /// Username in format "DOMAIN\\user" or "user@company.com"
    let username: String

    /// User's password
    let password: String

    /// Unique device identifier, persisted across sessions
    var deviceId: String

    /// Device type identifier for EAS
    static let deviceType = "VantaSpeech"

    /// EAS protocol version
    static let protocolVersion = "14.1"

    // MARK: - Computed Properties

    /// Base64-encoded Basic Auth header value
    var basicAuthHeader: String {
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else {
            return ""
        }
        return "Basic \(data.base64EncodedString())"
    }

    /// Full ActiveSync endpoint URL
    var activeSyncURL: URL? {
        guard var components = URLComponents(string: serverURL) else {
            return nil
        }
        components.path = "/Microsoft-Server-ActiveSync"
        return components.url
    }

    /// Username without domain prefix (for URL query parameter)
    var usernameForQuery: String {
        // If username contains backslash (DOMAIN\user), extract just the user part
        if let range = username.range(of: "\\") {
            return String(username[range.upperBound...])
        }
        return username
    }

    // MARK: - Initialization

    init(serverURL: String, username: String, password: String, deviceId: String? = nil) {
        self.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
        // DeviceId must be alphanumeric only (A-Z, a-z, 0-9), max 32 chars per MS-ASCMD spec
        if let deviceId = deviceId {
            self.deviceId = deviceId
        } else {
            // Generate alphanumeric-only device ID from UUID
            let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            self.deviceId = String(uuid.prefix(32))
        }
    }

    // MARK: - URL Building

    /// Build full URL for EAS command
    func buildURL(command: String) -> URL? {
        guard let baseURL = activeSyncURL else { return nil }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "Cmd", value: command),
            URLQueryItem(name: "User", value: usernameForQuery),
            URLQueryItem(name: "DeviceId", value: deviceId),
            URLQueryItem(name: "DeviceType", value: Self.deviceType)
        ]

        return components?.url
    }
}
