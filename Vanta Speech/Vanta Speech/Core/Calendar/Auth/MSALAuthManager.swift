import Combine
import Foundation
import UIKit

#if canImport(MSAL)
import MSAL
#endif

/// Менеджер аутентификации Microsoft через MSAL SDK
@MainActor
final class MSALAuthManager: ObservableObject {

    // MARK: - Configuration

    /// Client ID из Azure Portal (App Registration)
    /// TODO: Заменить на реальный Client ID после регистрации приложения
    private let clientId = "YOUR_AZURE_CLIENT_ID"

    /// Redirect URI для OAuth callback
    /// Формат: msauth.<bundle_id>://auth
    private var redirectUri: String {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return "msauth.ru.poscredit.Vanta-Speech://auth"
        }
        return "msauth.\(bundleId)://auth"
    }

    /// Authority URL для аутентификации
    /// "common" поддерживает personal + work/school accounts
    private let authority = "https://login.microsoftonline.com/common"

    /// Запрашиваемые разрешения
    private let scopes = [
        "Calendars.ReadWrite",  // Чтение и запись событий
        "User.Read",            // Профиль пользователя
        "offline_access"        // Refresh token
    ]

    // MARK: - State

    #if canImport(MSAL)
    private var application: MSALPublicClientApplication?
    @Published private(set) var currentAccount: MSALAccount?
    #endif

    @Published private(set) var isSignedIn = false
    @Published private(set) var isLoading = false
    @Published private(set) var userName: String?
    @Published private(set) var userEmail: String?
    @Published var error: String?

    // MARK: - Initialization

    init() {
        #if canImport(MSAL)
        setupApplication()
        loadCachedAccount()
        #endif
    }

    #if canImport(MSAL)
    private func setupApplication() {
        do {
            guard let authorityURL = URL(string: authority) else {
                debugLog("Invalid authority URL", module: "MSALAuthManager", level: .error)
                return
            }

            let msalAuthority = try MSALAADAuthority(url: authorityURL)

            let config = MSALPublicClientApplicationConfig(
                clientId: clientId,
                redirectUri: redirectUri,
                authority: msalAuthority
            )

            // Поддержка нескольких облаков (global, US Gov, China)
            config.multipleCloudsSupported = true

            application = try MSALPublicClientApplication(configuration: config)
            debugLog("MSAL configured successfully", module: "MSALAuthManager")
        } catch {
            debugLog("MSAL setup failed: \(error.localizedDescription)", module: "MSALAuthManager", level: .error)
            debugCaptureError(error, context: "MSAL setup")
            self.error = "Ошибка настройки аутентификации: \(error.localizedDescription)"
        }
    }

    private func loadCachedAccount() {
        guard let app = application else { return }

        do {
            let accounts = try app.allAccounts()
            if let account = accounts.first {
                currentAccount = account
                isSignedIn = true
                userName = account.username
                userEmail = account.username
                debugLog("Loaded cached account: \(account.username ?? "unknown")", module: "MSALAuthManager")
            }
        } catch {
            debugLog("Failed to load cached account: \(error)", module: "MSALAuthManager", level: .error)
            debugCaptureError(error, context: "MSALAuthManager.loadCachedAccount")
        }
    }
    #endif

    // MARK: - Sign In

    /// Интерактивный вход пользователя
    /// - Parameter viewController: UIViewController для презентации web view
    /// - Returns: Access token для Microsoft Graph API
    func signIn(from viewController: UIViewController) async throws -> String {
        #if canImport(MSAL)
        guard let app = application else {
            throw MSALAuthError.notConfigured
        }

        isLoading = true
        error = nil

        defer { isLoading = false }

        let webParameters = MSALWebviewParameters(authPresentationViewController: viewController)
        let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParameters)

        // Показываем выбор аккаунта
        parameters.promptType = .selectAccount

        return try await withCheckedThrowingContinuation { continuation in
            app.acquireToken(with: parameters) { [weak self] result, error in
                Task { @MainActor in
                    if let error = error {
                        let nsError = error as NSError

                        // Пользователь отменил
                        if nsError.domain == MSALErrorDomain &&
                           nsError.code == MSALError.userCanceled.rawValue {
                            continuation.resume(throwing: MSALAuthError.userCanceled)
                            return
                        }

                        self?.error = error.localizedDescription
                        continuation.resume(throwing: MSALAuthError.signInFailed(error))
                        return
                    }

                    guard let result = result else {
                        continuation.resume(throwing: MSALAuthError.noResult)
                        return
                    }

                    self?.currentAccount = result.account
                    self?.isSignedIn = true
                    self?.userName = result.account.username
                    self?.userEmail = result.account.username

                    debugLog("Sign in successful: \(result.account.username ?? "unknown")", module: "MSALAuthManager")
                    continuation.resume(returning: result.accessToken)
                }
            }
        }
        #else
        throw MSALAuthError.notConfigured
        #endif
    }

    // MARK: - Silent Token Acquisition

    /// Получение токена без UI (для фоновых операций)
    /// - Returns: Access token для Microsoft Graph API
    func acquireTokenSilently() async throws -> String {
        #if canImport(MSAL)
        guard let app = application else {
            throw MSALAuthError.notConfigured
        }

        guard let account = currentAccount else {
            throw MSALAuthError.noAccount
        }

        let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)

        return try await withCheckedThrowingContinuation { continuation in
            app.acquireTokenSilent(with: parameters) { result, error in
                if let error = error {
                    let nsError = error as NSError

                    // Требуется интерактивный вход
                    if nsError.domain == MSALErrorDomain &&
                       nsError.code == MSALError.interactionRequired.rawValue {
                        continuation.resume(throwing: MSALAuthError.interactionRequired)
                        return
                    }

                    continuation.resume(throwing: MSALAuthError.tokenAcquisitionFailed(error))
                    return
                }

                guard let result = result else {
                    continuation.resume(throwing: MSALAuthError.noResult)
                    return
                }

                continuation.resume(returning: result.accessToken)
            }
        }
        #else
        throw MSALAuthError.notConfigured
        #endif
    }

    // MARK: - Sign Out

    /// Выход из аккаунта с очисткой сессии браузера
    /// - Parameter viewController: UIViewController для презентации web view
    func signOut(from viewController: UIViewController) async throws {
        #if canImport(MSAL)
        guard let app = application, let account = currentAccount else { return }

        isLoading = true
        defer { isLoading = false }

        let webParameters = MSALWebviewParameters(authPresentationViewController: viewController)
        let parameters = MSALSignoutParameters(webviewParameters: webParameters)
        parameters.signoutFromBrowser = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            app.signout(with: account, signoutParameters: parameters) { [weak self] success, error in
                Task { @MainActor in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    self?.currentAccount = nil
                    self?.isSignedIn = false
                    self?.userName = nil
                    self?.userEmail = nil

                    debugLog("Sign out successful", module: "MSALAuthManager")
                    continuation.resume()
                }
            }
        }
        #endif
    }

    /// Локальный выход (без очистки сессии браузера)
    func signOutLocally() {
        #if canImport(MSAL)
        guard let app = application, let account = currentAccount else { return }

        try? app.remove(account)
        currentAccount = nil
        isSignedIn = false
        userName = nil
        userEmail = nil

        debugLog("Local sign out successful", module: "MSALAuthManager")
        #endif
    }

    // MARK: - MSAL URL Handling

    /// Обработка URL callback от MSAL
    /// Вызывается из AppDelegate или SceneDelegate
    static func handleMSALResponse(_ url: URL, sourceApplication: String?) -> Bool {
        #if canImport(MSAL)
        return MSALPublicClientApplication.handleMSALResponse(
            url,
            sourceApplication: sourceApplication
        )
        #else
        return false
        #endif
    }
}

// MARK: - Errors

/// Ошибки аутентификации MSAL
enum MSALAuthError: LocalizedError {
    case notConfigured
    case noAccount
    case noResult
    case userCanceled
    case interactionRequired
    case signInFailed(Error)
    case tokenAcquisitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MSAL не настроен. Добавьте MSAL SDK в проект."
        case .noAccount:
            return "Нет авторизованного аккаунта"
        case .noResult:
            return "Не получен результат аутентификации"
        case .userCanceled:
            return "Вход отменён пользователем"
        case .interactionRequired:
            return "Требуется повторный вход"
        case .signInFailed(let error):
            return "Ошибка входа: \(error.localizedDescription)"
        case .tokenAcquisitionFailed(let error):
            return "Ошибка получения токена: \(error.localizedDescription)"
        }
    }
}
