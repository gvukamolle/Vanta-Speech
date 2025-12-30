import Foundation
import Combine

/// Manages EWS authentication and credential storage
@MainActor
final class EWSAuthManager: ObservableObject {
    static let shared = EWSAuthManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var credentials: EWSCredentials?
    @Published private(set) var lastError: Error?

    private let keychainManager = KeychainManager.shared

    private init() {
        loadStoredCredentials()
    }

    // MARK: - Public API

    /// Authenticate with EWS server
    /// - Parameters:
    ///   - serverURL: Exchange server base URL (e.g., https://exchange.company.ru)
    ///   - domain: Windows domain (e.g., COMPANY)
    ///   - username: Username without domain (e.g., user)
    ///   - password: User password
    /// - Returns: True if authentication successful
    @discardableResult
    func authenticate(
        serverURL: String,
        domain: String,
        username: String,
        password: String
    ) async -> Bool {
        let credentials = EWSCredentials(
            serverURL: serverURL,
            domain: domain,
            username: username,
            password: password,
            email: nil
        )

        return await authenticate(with: credentials)
    }

    /// Authenticate with pre-built credentials
    @discardableResult
    func authenticate(with credentials: EWSCredentials) async -> Bool {
        lastError = nil

        do {
            // Create client and test connection
            let client = try EWSClient.fromCredentials(credentials)

            // Test with a simple FindItem request for today
            let today = Date()
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

            let request = EWSXMLBuilder.buildFindItemRequest(
                startDate: today,
                endDate: tomorrow,
                maxEntries: 1
            )

            let response = try await client.sendRequest(
                soapAction: EWSXMLBuilder.SOAPAction.findItem,
                body: request
            )

            // Check if response is valid (contains success indicator)
            guard let responseString = String(data: response, encoding: .utf8),
                  responseString.contains("ResponseClass=\"Success\"") ||
                  responseString.contains("NoError") else {
                throw EWSError.authenticationFailed
            }

            // Success - save credentials
            try keychainManager.saveEWSCredentials(credentials)
            self.credentials = credentials
            self.isAuthenticated = true

            print("[EWSAuthManager] Authentication successful")
            return true

        } catch {
            lastError = error
            isAuthenticated = false
            print("[EWSAuthManager] Authentication failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Sign out and clear credentials
    func signOut() {
        keychainManager.deleteEWSCredentials()
        credentials = nil
        isAuthenticated = false
        lastError = nil
        print("[EWSAuthManager] Signed out")
    }

    /// Get current credentials or throw if not authenticated
    func getCredentials() throws -> EWSCredentials {
        guard let credentials = credentials else {
            throw EWSError.notConfigured
        }
        return credentials
    }

    /// Create EWSClient with current credentials
    func createClient() throws -> EWSClient {
        let creds = try getCredentials()
        return try EWSClient.fromCredentials(creds)
    }

    // MARK: - Private

    private func loadStoredCredentials() {
        if let stored = keychainManager.loadEWSCredentials() {
            credentials = stored
            isAuthenticated = true
            print("[EWSAuthManager] Loaded stored credentials for \(stored.username)")
        }
    }
}
