import Foundation
import SwiftUI
import Combine

/// Manages authentication state across the app
@MainActor
final class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentSession: UserSession?
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let authService = LDAPAuthService()
    private let keychain = KeychainManager.shared

    private init() {
        loadStoredSession()
    }

    // MARK: - Public API

    /// Attempt to log in with username and password
    func login(username: String, password: String) async {
        guard !username.isEmpty, !password.isEmpty else {
            error = "Введите логин и пароль"
            return
        }

        isLoading = true
        error = nil

        do {
            let session = try await authService.authenticate(username: username, password: password)
            try keychain.saveSession(session)

            currentSession = session
            isAuthenticated = true
            isLoading = false
        } catch let authError as LDAPAuthService.AuthError {
            // LDAP specific errors with full description
            self.error = authError.errorDescription ?? authError.localizedDescription
            isLoading = false
            debugCaptureError(authError, context: "LDAP authentication")
        } catch {
            // Generic errors - show full details
            self.error = "\(error.localizedDescription)\n\nПодробности: \(String(describing: error))"
            isLoading = false
            debugCaptureError(error, context: "Authentication")
        }
    }

    /// Log out the current user
    func logout() {
        keychain.deleteSession()
        currentSession = nil
        isAuthenticated = false
    }

    /// Skip authentication for testing (temporary)
    func skipAuthentication() {
        let testSession = UserSession(
            username: "test_user",
            displayName: "Тестовый пользователь",
            email: nil
        )
        try? keychain.saveSession(testSession)
        currentSession = testSession
        isAuthenticated = true
    }

    // MARK: - Private

    private func loadStoredSession() {
        if let session = keychain.loadSession() {
            currentSession = session
            isAuthenticated = true
        }
    }
}
