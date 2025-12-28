import Foundation

// MARK: - Response Models

/// Ответ со списком событий от Microsoft Graph API
struct GraphEventsResponse: Codable {
    let value: [GraphEvent]

    /// Ссылка на следующую страницу (pagination)
    var nextLink: String?

    /// Delta link для инкрементальной синхронизации
    var deltaLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
        case deltaLink = "@odata.deltaLink"
    }
}

/// Событие календаря Outlook
struct GraphEvent: Codable, Identifiable {
    let id: String
    let subject: String?
    let bodyPreview: String?
    let start: DateTimeTimeZone
    let end: DateTimeTimeZone
    let attendees: [GraphAttendee]?
    let organizer: Organizer?
    let isOrganizer: Bool?
    let iCalUId: String?
    let webLink: String?
    let location: GraphLocation?

    /// Флаг удаления (для delta sync)
    var removed: Removed?

    enum CodingKeys: String, CodingKey {
        case id, subject, bodyPreview, start, end
        case attendees, organizer, isOrganizer
        case iCalUId, webLink, location
        case removed = "@removed"
    }

    /// Дата начала события
    var startDate: Date? {
        parseGraphDate(start.dateTime)
    }

    /// Дата окончания события
    var endDate: Date? {
        parseGraphDate(end.dateTime)
    }

    /// Название для отображения
    var displayTitle: String {
        subject ?? "Без названия"
    }

    private func parseGraphDate(_ dateString: String) -> Date? {
        // Graph API возвращает даты в формате ISO8601
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Fallback без fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}

/// Дата и время с часовым поясом
struct DateTimeTimeZone: Codable {
    let dateTime: String
    let timeZone: String

    init(dateTime: String, timeZone: String) {
        self.dateTime = dateTime
        self.timeZone = timeZone
    }

    init(date: Date, timeZone: String = TimeZone.current.identifier) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.dateTime = formatter.string(from: date)
        self.timeZone = timeZone
    }
}

/// Участник встречи
struct GraphAttendee: Codable {
    let emailAddress: EmailAddress
    let type: String           // required, optional, resource
    let status: ResponseStatus?
}

/// Email адрес
struct EmailAddress: Codable {
    let address: String
    let name: String?
}

/// Статус ответа участника
struct ResponseStatus: Codable {
    let response: String       // none, accepted, declined, tentativelyAccepted
    let time: String?
}

/// Организатор встречи
struct Organizer: Codable {
    let emailAddress: EmailAddress
}

/// Локация встречи
struct GraphLocation: Codable {
    let displayName: String?
    let address: PhysicalAddress?
}

/// Физический адрес
struct PhysicalAddress: Codable {
    let street: String?
    let city: String?
    let state: String?
    let countryOrRegion: String?
    let postalCode: String?
}

/// Флаг удаления для delta sync
struct Removed: Codable {
    let reason: String  // "deleted" или "changed"
}

// MARK: - Request Models

/// Запрос на создание события
struct CreateEventRequest: Codable {
    let subject: String
    let start: DateTimeTimeZone
    let end: DateTimeTimeZone
    let body: EventBody?
    let attendees: [AttendeeRequest]?
    let location: LocationRequest?

    init(
        subject: String,
        start: Date,
        end: Date,
        timeZone: String = TimeZone.current.identifier,
        body: String? = nil,
        attendees: [String]? = nil,
        location: String? = nil
    ) {
        self.subject = subject
        self.start = DateTimeTimeZone(date: start, timeZone: timeZone)
        self.end = DateTimeTimeZone(date: end, timeZone: timeZone)
        self.body = body.map { EventBody(contentType: "text", content: $0) }
        self.attendees = attendees?.map {
            AttendeeRequest(
                emailAddress: EmailAddress(address: $0, name: nil),
                type: "required"
            )
        }
        self.location = location.map { LocationRequest(displayName: $0) }
    }
}

/// Запрос на обновление события
struct UpdateEventRequest: Codable {
    var subject: String?
    var start: DateTimeTimeZone?
    var end: DateTimeTimeZone?
    var body: EventBody?
    var location: LocationRequest?
}

/// Тело события
struct EventBody: Codable {
    let contentType: String  // "text" или "html"
    let content: String
}

/// Запрос участника
struct AttendeeRequest: Codable {
    let emailAddress: EmailAddress
    let type: String
}

/// Запрос локации
struct LocationRequest: Codable {
    let displayName: String
}

// MARK: - Participant Models

/// Участник встречи для отображения в UI
struct MeetingParticipant: Identifiable {
    let id = UUID()
    let email: String
    let name: String?
    let role: ParticipantRole
    let responseStatus: ParticipantResponseStatus

    var displayName: String {
        name ?? email
    }
}

/// Роль участника
enum ParticipantRole {
    case organizer
    case required
    case optional
}

/// Статус ответа участника
enum ParticipantResponseStatus {
    case accepted
    case declined
    case tentative
    case notResponded

    var displayText: String {
        switch self {
        case .accepted: return "Принял"
        case .declined: return "Отклонил"
        case .tentative: return "Возможно"
        case .notResponded: return "Не ответил"
        }
    }

    var iconName: String {
        switch self {
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .tentative: return "questionmark.circle.fill"
        case .notResponded: return "circle"
        }
    }
}

// MARK: - Sync Models

/// Результат синхронизации
struct SyncResult {
    let updatedEvents: [GraphEvent]
    let deletedEventIds: [String]
    let isFullSync: Bool

    var isEmpty: Bool {
        updatedEvents.isEmpty && deletedEventIds.isEmpty
    }
}

// MARK: - Errors

/// Ошибки Microsoft Graph API
enum GraphError: LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: Int)
    case httpError(statusCode: Int, data: Data)
    case deleteFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Некорректный ответ от сервера"
        case .unauthorized:
            return "Требуется авторизация"
        case .forbidden:
            return "Доступ запрещён"
        case .notFound:
            return "Событие не найдено"
        case .rateLimited(let retryAfter):
            return "Превышен лимит запросов. Повторите через \(retryAfter) сек."
        case .httpError(let statusCode, _):
            return "Ошибка HTTP: \(statusCode)"
        case .deleteFailed:
            return "Не удалось удалить событие"
        case .encodingFailed:
            return "Ошибка кодирования данных"
        }
    }
}
