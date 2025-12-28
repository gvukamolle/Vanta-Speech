import Foundation

/// Сервис для работы с календарём через Microsoft Graph API
final class GraphCalendarService {

    private let baseURL = "https://graph.microsoft.com/v1.0"
    private let authManager: MSALAuthManager

    init(authManager: MSALAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Private Helpers

    /// Создание авторизованного запроса
    private func authorizedRequest(url: URL, method: String = "GET") async throws -> URLRequest {
        let token = try await authManager.acquireTokenSilently()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return request
    }

    /// Выполнение запроса с декодированием ответа
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GraphError.invalidResponse
        }

        // Обработка ошибок HTTP
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw GraphError.unauthorized
        case 403:
            throw GraphError.forbidden
        case 404:
            throw GraphError.notFound
        case 429:
            // Rate limiting
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
            throw GraphError.rateLimited(retryAfter: Int(retryAfter ?? "60") ?? 60)
        default:
            throw GraphError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Fetch Events

extension GraphCalendarService {

    /// Получить события календаря за период
    /// - Parameters:
    ///   - startDate: Начало периода
    ///   - endDate: Конец периода
    ///   - maxResults: Максимальное количество событий
    /// - Returns: Массив событий
    func fetchEvents(
        from startDate: Date,
        to endDate: Date,
        maxResults: Int = 50
    ) async throws -> [GraphEvent] {

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)

        // calendarView раскрывает recurring events в отдельные instances
        var components = URLComponents(string: "\(baseURL)/me/calendarView")!
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: startString),
            URLQueryItem(name: "endDateTime", value: endString),
            URLQueryItem(name: "$select", value: "id,subject,start,end,attendees,organizer,isOrganizer,iCalUId,bodyPreview,webLink,location"),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
            URLQueryItem(name: "$top", value: String(maxResults))
        ]

        guard let url = components.url else {
            throw GraphError.invalidResponse
        }

        let request = try await authorizedRequest(url: url)
        let response: GraphEventsResponse = try await performRequest(request)

        return response.value
    }

    /// Получить события на сегодня
    func fetchTodayEvents() async throws -> [GraphEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await fetchEvents(from: startOfDay, to: endOfDay)
    }

    /// Получить конкретное событие по ID
    func fetchEvent(id: String) async throws -> GraphEvent {
        let url = URL(string: "\(baseURL)/me/events/\(id)")!
        let request = try await authorizedRequest(url: url)
        return try await performRequest(request)
    }
}

// MARK: - Create Event

extension GraphCalendarService {

    /// Создать новое событие
    /// - Parameter event: Данные события
    /// - Returns: Созданное событие
    func createEvent(_ event: CreateEventRequest) async throws -> GraphEvent {
        let url = URL(string: "\(baseURL)/me/events")!
        var request = try await authorizedRequest(url: url, method: "POST")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(event)

        return try await performRequest(request)
    }

    /// Быстрое создание события
    /// - Parameters:
    ///   - title: Название события
    ///   - start: Время начала
    ///   - end: Время окончания
    ///   - location: Место проведения (опционально)
    /// - Returns: Созданное событие
    func createEvent(
        title: String,
        start: Date,
        end: Date,
        location: String? = nil
    ) async throws -> GraphEvent {
        let request = CreateEventRequest(
            subject: title,
            start: start,
            end: end,
            location: location
        )
        return try await createEvent(request)
    }
}

// MARK: - Update Event

extension GraphCalendarService {

    /// Обновить существующее событие (частичное обновление)
    /// - Parameters:
    ///   - id: ID события
    ///   - changes: Изменения
    /// - Returns: Обновлённое событие
    func updateEvent(id: String, changes: UpdateEventRequest) async throws -> GraphEvent {
        let url = URL(string: "\(baseURL)/me/events/\(id)")!
        var request = try await authorizedRequest(url: url, method: "PATCH")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(changes)

        return try await performRequest(request)
    }

    /// Переименовать событие
    /// - Parameters:
    ///   - id: ID события
    ///   - newTitle: Новое название
    /// - Returns: Обновлённое событие
    func renameEvent(id: String, newTitle: String) async throws -> GraphEvent {
        var changes = UpdateEventRequest()
        changes.subject = newTitle
        return try await updateEvent(id: id, changes: changes)
    }
}

// MARK: - Delete Event

extension GraphCalendarService {

    /// Удалить событие
    /// - Parameter id: ID события
    func deleteEvent(id: String) async throws {
        let url = URL(string: "\(baseURL)/me/events/\(id)")!
        let request = try await authorizedRequest(url: url, method: "DELETE")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw GraphError.deleteFailed
        }
    }
}

// MARK: - Attendees

extension GraphCalendarService {

    /// Получить участников события с их статусами
    /// - Parameter eventId: ID события
    /// - Returns: Список участников
    func getAttendees(eventId: String) async throws -> [MeetingParticipant] {
        let event = try await fetchEvent(id: eventId)

        var participants: [MeetingParticipant] = []

        // Организатор
        if let organizer = event.organizer {
            participants.append(MeetingParticipant(
                email: organizer.emailAddress.address,
                name: organizer.emailAddress.name,
                role: .organizer,
                responseStatus: .accepted  // Организатор всегда accepted
            ))
        }

        // Участники
        for attendee in event.attendees ?? [] {
            let role: ParticipantRole = attendee.type == "required" ? .required : .optional
            let status = mapResponseStatus(attendee.status?.response)

            participants.append(MeetingParticipant(
                email: attendee.emailAddress.address,
                name: attendee.emailAddress.name,
                role: role,
                responseStatus: status
            ))
        }

        return participants
    }

    private func mapResponseStatus(_ response: String?) -> ParticipantResponseStatus {
        switch response {
        case "accepted": return .accepted
        case "declined": return .declined
        case "tentativelyAccepted": return .tentative
        case "none", .none: return .notResponded
        default: return .notResponded
        }
    }
}

// MARK: - User Profile

extension GraphCalendarService {

    /// Получить профиль текущего пользователя
    func fetchUserProfile() async throws -> UserProfile {
        let url = URL(string: "\(baseURL)/me")!
        let request = try await authorizedRequest(url: url)
        return try await performRequest(request)
    }
}

/// Профиль пользователя Microsoft
struct UserProfile: Codable {
    let id: String
    let displayName: String?
    let mail: String?
    let userPrincipalName: String?

    var email: String {
        mail ?? userPrincipalName ?? "unknown"
    }
}
