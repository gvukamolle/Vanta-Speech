import Foundation

/// Meeting attendee from EAS calendar event
struct EASAttendee: Codable, Equatable, Identifiable {
    /// Email address (used as ID)
    let email: String

    /// Display name
    let name: String

    /// Attendee type (required, optional, resource)
    let type: EASAttendeeType

    /// Response status (accepted, declined, etc.)
    let status: EASResponseStatus?

    var id: String { email }

    // MARK: - Initialization

    init(email: String, name: String, type: EASAttendeeType = .required, status: EASResponseStatus? = nil) {
        self.email = email
        self.name = name
        self.type = type
        self.status = status
    }
}

/// Attendee type values from EAS protocol
enum EASAttendeeType: Int, Codable, Equatable {
    case required = 1
    case optional = 2
    case resource = 3

    var displayName: String {
        switch self {
        case .required: return "Обязательный"
        case .optional: return "Необязательный"
        case .resource: return "Ресурс"
        }
    }
}

/// Response status values from EAS protocol
enum EASResponseStatus: Int, Codable, Equatable {
    case none = 0
    case organizer = 1
    case tentative = 2
    case accepted = 3
    case declined = 4
    case notResponded = 5

    var displayName: String {
        switch self {
        case .none: return "Нет ответа"
        case .organizer: return "Организатор"
        case .tentative: return "Возможно"
        case .accepted: return "Принято"
        case .declined: return "Отклонено"
        case .notResponded: return "Не ответил"
        }
    }

    var iconName: String {
        switch self {
        case .none, .notResponded: return "questionmark.circle"
        case .organizer: return "star.circle.fill"
        case .tentative: return "questionmark.circle.fill"
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        }
    }
}
