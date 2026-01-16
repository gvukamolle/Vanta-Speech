import Foundation

/// Errors that can occur during EAS operations
enum EASError: LocalizedError, Equatable {
    /// No network connection available
    case offline

    /// No credentials stored
    case noCredentials

    /// Invalid or expired credentials (HTTP 401)
    case authenticationFailed

    /// Access denied by server (HTTP 403)
    case accessDenied

    /// Server temporarily unavailable (HTTP 503)
    case serverUnavailable

    /// Calendar folder not found in FolderSync response
    case calendarFolderNotFound

    /// Failed to parse server response
    case parseError(String)

    /// Network error during request
    case networkError(String)

    /// HTTP error with status code
    case serverError(statusCode: Int, message: String?)

    /// WBXML encoding/decoding error
    case wbxmlError(String)

    /// Invalid server URL
    case invalidServerURL

    /// Device provisioning denied by server
    case provisioningDenied

    /// Provisioning required (status 108)
    case provisioningRequired

    /// Unknown error
    case unknown(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Нет подключения к сети. Проверьте интернет-соединение."
        case .noCredentials:
            return "Требуется вход в аккаунт"
        case .authenticationFailed:
            return "Неверный логин или пароль"
        case .accessDenied:
            return "Доступ запрещён. Обратитесь к администратору."
        case .serverUnavailable:
            return "Сервер временно недоступен. Попробуйте позже."
        case .calendarFolderNotFound:
            return "Календарь не найден. Обратитесь к администратору."
        case .parseError(let details):
            return "Ошибка обработки данных: \(details)"
        case .networkError(let details):
            return "Ошибка сети: \(details)"
        case .serverError(let code, let message):
            if let message = message {
                return "Ошибка сервера (\(code)): \(message)"
            }
            return "Ошибка сервера: \(code)"
        case .wbxmlError(let details):
            return "Ошибка формата данных: \(details)"
        case .invalidServerURL:
            return "Неверный адрес сервера"
        case .provisioningDenied:
            return "Устройство заблокировано политиками безопасности. Обратитесь к администратору."
        case .provisioningRequired:
            return "Требуется принятие политик безопасности"
        case .unknown(let details):
            return "Произошла ошибка: \(details)"
        }
    }

    // MARK: - Recovery Suggestion

    /// Suggested action to recover from error
    var recoverySuggestion: RecoveryAction {
        switch self {
        case .offline, .networkError, .serverUnavailable, .parseError, .wbxmlError, .provisioningRequired:
            return .retry
        case .noCredentials, .authenticationFailed:
            return .login
        case .accessDenied, .calendarFolderNotFound, .provisioningDenied:
            return .contactAdmin
        case .serverError(let code, _):
            if code == 401 {
                return .login
            } else if code >= 500 {
                return .retry
            }
            return .contactAdmin
        case .invalidServerURL:
            return .login
        case .unknown:
            return .retry
        }
    }

    /// Whether credentials should be cleared for this error
    var shouldClearCredentials: Bool {
        switch self {
        case .authenticationFailed, .serverError(statusCode: 401, _):
            return true
        default:
            return false
        }
    }

    // MARK: - Equatable

    static func == (lhs: EASError, rhs: EASError) -> Bool {
        switch (lhs, rhs) {
        case (.offline, .offline),
             (.noCredentials, .noCredentials),
             (.authenticationFailed, .authenticationFailed),
             (.accessDenied, .accessDenied),
             (.serverUnavailable, .serverUnavailable),
             (.calendarFolderNotFound, .calendarFolderNotFound),
             (.invalidServerURL, .invalidServerURL),
             (.provisioningDenied, .provisioningDenied),
             (.provisioningRequired, .provisioningRequired):
            return true
        case (.parseError(let a), .parseError(let b)),
             (.networkError(let a), .networkError(let b)),
             (.wbxmlError(let a), .wbxmlError(let b)),
             (.unknown(let a), .unknown(let b)):
            return a == b
        case (.serverError(let codeA, let msgA), .serverError(let codeB, let msgB)):
            return codeA == codeB && msgA == msgB
        default:
            return false
        }
    }
}

/// Suggested recovery action for errors
enum RecoveryAction {
    /// User should retry the operation
    case retry

    /// User should re-authenticate
    case login

    /// User should contact system administrator
    case contactAdmin
}
