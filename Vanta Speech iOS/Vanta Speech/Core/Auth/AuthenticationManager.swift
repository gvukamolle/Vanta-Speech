import Foundation
import SwiftUI
import Combine
import SwiftData

/// Manages authentication state across the app
@MainActor
final class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentSession: UserSession?
    @Published private(set) var isLoading = false
    @Published var error: String?
    
    /// Флаг показывающий что идет процесс выхода (для UI)
    @Published private(set) var isLoggingOut = false

    private let authService = LDAPAuthService()
    private let keychain = KeychainManager.shared
    private let appResetService = AppResetService.shared

    private init() {
        loadStoredSession()
    }

    // MARK: - Public API

    /// Attempt to log in with username and password
    /// Automatically connects Exchange and Confluence with the same credentials
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

            // Auto-connect Exchange calendar after successful AD login
            await autoConnectExchangeCalendar(username: username, password: password)
            
            // Auto-connect Confluence after successful AD login
            await autoConnectConfluence(username: username, password: password)
            
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

    /// Automatically connect Exchange calendar after successful AD login
    /// Uses the same credentials as AD authentication
    private func autoConnectExchangeCalendar(username: String, password: String) async {
        let calendarManager = EASCalendarManager.shared

        // Skip if already connected
        guard !calendarManager.isConnected else {
            debugLog("Exchange calendar already connected", module: "Auth", level: .info)
            return
        }

        // Build full email: username -> username@pos-credit.ru
        let fullUsername = buildExchangeUsername(username)

        debugLog("Auto-connecting Exchange calendar for \(fullUsername)", module: "Auth", level: .info)

        let success = await calendarManager.connect(
            serverURL: Env.exchangeServerURL,
            username: fullUsername,
            password: password
        )

        if success {
            debugLog("Exchange calendar auto-connected successfully", module: "Auth", level: .info)
        } else {
            // Don't show error to user - they can connect manually later
            debugLog("Exchange calendar auto-connect failed: \(calendarManager.lastError?.localizedDescription ?? "unknown")", module: "Auth", level: .warning)
        }
    }
    
    /// Automatically connect Confluence after successful AD login
    /// Uses the same credentials as AD authentication (username without domain)
    private func autoConnectConfluence(username: String, password: String) async {
        let confluenceManager = ConfluenceManager.shared
        
        // Skip if already connected
        guard !confluenceManager.isAvailable else {
            debugLog("Confluence already connected", module: "Auth", level: .info)
            return
        }
        
        // Extract username without domain for Confluence
        // Confluence uses the same AD credentials but username without @domain
        let confluenceUsername = extractUsernameWithoutDomain(username)
        
        debugLog("Auto-connecting Confluence for user: \(confluenceUsername)", module: "Auth", level: .info)
        
        let success = await confluenceManager.connect(
            username: confluenceUsername,
            password: password
        )
        
        if success {
            debugLog("Confluence auto-connected successfully", module: "Auth", level: .info)
        } else {
            // Don't show error to user - they can connect manually later
            debugLog("Confluence auto-connect failed: \(confluenceManager.lastError?.localizedDescription ?? "unknown")", module: "Auth", level: .warning)
        }
    }

    /// Log out the current user and perform full data reset
    /// - Parameters:
    ///   - modelContext: SwiftData context for deleting recordings (optional)
    ///   - completion: Callback when logout is complete
    func logout(modelContext: ModelContext? = nil) {
        guard !isLoggingOut else { return }
        
        isLoggingOut = true
        
        Task {
            if let context = modelContext {
                // Полный сброс с удалением записей
                await appResetService.performFullReset(modelContext: context)
            } else {
                // Частичный сброс (без контекста - удалим что можем)
                await appResetService.performFullResetWithoutContext()
            }
            
            // Очищаем UI состояние
            currentSession = nil
            isAuthenticated = false
            error = nil
            isLoggingOut = false
            
            debugLog("User logged out successfully", module: "Auth", level: .info)
        }
    }
    
    /// Log out without model context (for backwards compatibility)
    /// Note: This won't delete recordings from SwiftData
    func logout() {
        logout(modelContext: nil)
    }

    /// Skip authentication for testing (temporary)
    func skipAuthentication() {
#if DEBUG
        let testSession = UserSession(
            username: "test_user",
            displayName: "Тестовый пользователь",
            email: nil
        )
        try? keychain.saveSession(testSession)
        currentSession = testSession
        isAuthenticated = true
#else
        debugLog("Skip authentication is disabled in non-debug builds", module: "Auth", level: .warning)
#endif
    }

    // MARK: - Private
    
    /// Build Exchange username: username + "@pos-credit.ru" (trimmed, without spaces)
    private func buildExchangeUsername(_ username: String) -> String {
        // Убираем пробелы
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Если уже содержит @, используем как есть (но тоже trimmed)
        if trimmedUsername.contains("@") {
            return trimmedUsername
        }
        
        // Добавляем домен
        return trimmedUsername + Env.corporateEmailDomain
    }
    
    /// Extract username without domain for Confluence
    /// Input: "user@domain.com" or "DOMAIN\user" or "user"
    /// Output: "user"
    private func extractUsernameWithoutDomain(_ username: String) -> String {
        var result = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Обрабатываем формат user@domain.com
        if let atIndex = result.firstIndex(of: "@") {
            result = String(result[..<atIndex])
        }
        
        // Обрабатываем формат DOMAIN\user
        if let slashIndex = result.lastIndex(of: "\\") {
            result = String(result[result.index(after: slashIndex)...])
        }
        
        return result
    }

    private func loadStoredSession() {
        if let session = keychain.loadSession() {
            currentSession = session
            isAuthenticated = true
        }
    }
}
