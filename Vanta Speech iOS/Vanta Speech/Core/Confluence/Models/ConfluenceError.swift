import Foundation

/// Ошибки Confluence API
enum ConfluenceError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidServerURL
    case authenticationFailed
    case accessDenied
    case notFound(String)
    case conflict(String)
    case serverError(statusCode: Int, message: String?)
    case networkError(String)
    case parseError(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Необходимо войти в систему"
        case .invalidServerURL:
            return "Некорректный URL сервера Confluence"
        case .authenticationFailed:
            return "Неверные учётные данные"
        case .accessDenied:
            return "Доступ запрещён"
        case .notFound(let resource):
            return "Не найдено: \(resource)"
        case .conflict(let message):
            return "Конфликт: \(message)"
        case .serverError(let code, let message):
            return "Ошибка сервера (\(code)): \(message ?? "неизвестная ошибка")"
        case .networkError(let message):
            return "Сетевая ошибка: \(message)"
        case .parseError(let message):
            return "Ошибка обработки ответа: \(message)"
        case .offline:
            return "Отсутствует подключение к сети"
        }
    }

    /// Ошибка связана с авторизацией и требует повторного входа
    var isAuthError: Bool {
        switch self {
        case .notAuthenticated, .authenticationFailed:
            return true
        default:
            return false
        }
    }
}
