# Интеграция Outlook Calendar в Vanta Speech

Техническая документация по интеграции Microsoft Outlook Calendar через Graph API для iOS/iPadOS приложения без собственного бэкенда.

---

## Содержание

1. [Обзор интеграции](#обзор-интеграции)
2. [Регистрация приложения в Azure AD](#регистрация-приложения-в-azure-ad)
3. [Настройка MSAL в iOS-проекте](#настройка-msal-в-ios-проекте)
4. [Аутентификация пользователя](#аутентификация-пользователя)
5. [Работа с событиями календаря](#работа-с-событиями-календаря)
6. [Получение участников встречи](#получение-участников-встречи)
7. [Инкрементальная синхронизация (Delta Queries)](#инкрементальная-синхронизация-delta-queries)
8. [Безопасное хранение токенов](#безопасное-хранение-токенов)
9. [Фоновая синхронизация](#фоновая-синхронизация)
10. [Связывание записей с событиями](#связывание-записей-с-событиями)
11. [Обработка ошибок](#обработка-ошибок)
12. [Рекомендуемая архитектура](#рекомендуемая-архитектура)

---

## Обзор интеграции

### Что даёт интеграция с Outlook

| Функция Vanta Speech | Реализация через Graph API |
|---------------------|---------------------------|
| Связать запись со встречей | Получение событий → сохранение `id` + `iCalUId` |
| Добавить встречу после записи | `POST /me/events` |
| Переименовать встречу | `PATCH /me/events/{id}` |
| Видеть гостей встречи | Поле `attendees` в событии — **email доступен** |

### Ключевые преимущества Microsoft Graph

- **Не требует верификации приложения** (в отличие от Google Calendar)
- **Полный доступ к email участников** (в отличие от Apple EventKit)
- **Delta queries** для эффективной инкрементальной синхронизации
- **MSAL SDK** полностью управляет OAuth flow и токенами
- Поддержка personal Microsoft accounts + Work/School accounts

### Необходимые permissions (scopes)

| Scope | Назначение | Admin consent |
|-------|-----------|---------------|
| `Calendars.Read` | Чтение событий и участников | ❌ Не требуется |
| `Calendars.ReadWrite` | Создание и редактирование событий | ❌ Не требуется |
| `User.Read` | Получение профиля пользователя | ❌ Не требуется |
| `offline_access` | Refresh token для фоновой работы | ❌ Не требуется |

**Рекомендуемый набор для Vanta Speech**: `["Calendars.ReadWrite", "User.Read", "offline_access"]`

---

## Регистрация приложения в Azure AD

### Шаг 1: Создание App Registration

1. Открыть [Azure Portal](https://portal.azure.com)
2. Перейти в **Microsoft Entra ID** → **App registrations** → **New registration**

**Параметры регистрации:**

| Поле | Значение |
|------|----------|
| Name | `Vanta Speech` |
| Supported account types | `Accounts in any organizational directory and personal Microsoft accounts` |
| Redirect URI | Пока оставить пустым (добавим на следующем шаге) |

### Шаг 2: Настройка Redirect URI для iOS

1. В созданном приложении перейти в **Authentication** → **Add a platform** → **iOS / macOS**
2. Ввести **Bundle ID**: `com.vantaspeech.app` (заменить на реальный)
3. Azure автоматически сгенерирует Redirect URI формата:

```
msauth.com.vantaspeech.app://auth
```

### Шаг 3: Включение Public Client Flow

1. В разделе **Authentication** найти **Advanced settings**
2. Установить **Allow public client flows** = **Yes**
3. Сохранить изменения

> ⚠️ Без этой настройки мобильное приложение не сможет получить токены

### Шаг 4: Сохранить credentials

После регистрации сохранить:

| Параметр | Где найти |
|----------|-----------|
| Application (client) ID | Overview → Application (client) ID |
| Redirect URI | Authentication → iOS/macOS platform |

**Client Secret не нужен** — мобильные приложения используют PKCE flow.

---

## Настройка MSAL в iOS-проекте

### Установка зависимости

**Swift Package Manager (рекомендуется):**

```
https://github.com/AzureAD/microsoft-authentication-library-for-objc
```

Или **CocoaPods:**

```ruby
pod 'MSAL', '~> 1.4'
```

### Конфигурация Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- URL Schemes для OAuth callback -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>msauth.$(PRODUCT_BUNDLE_IDENTIFIER)</string>
            </array>
        </dict>
    </array>
    
    <!-- Разрешить открытие Microsoft Authenticator -->
    <key>LSApplicationQueriesSchemes</key>
    <array>
        <string>msauthv2</string>
        <string>msauthv3</string>
    </array>
</dict>
</plist>
```

### Настройка Keychain Sharing

1. Открыть **Signing & Capabilities** в Xcode
2. Добавить **Keychain Sharing** capability
3. Добавить Keychain Group: `com.microsoft.adalcache`

> MSAL хранит токены в shared keychain group — без этой настройки silent token acquisition не работает

### Обработка OAuth callback в AppDelegate/SceneDelegate

**AppDelegate.swift:**

```swift
import MSAL

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return MSALPublicClientApplication.handleMSALResponse(
            url,
            sourceApplication: options[.sourceApplication] as? String
        )
    }
}
```

**Для SceneDelegate (iOS 13+):**

```swift
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let urlContext = URLContexts.first else { return }
    
    MSALPublicClientApplication.handleMSALResponse(
        urlContext.url,
        sourceApplication: urlContext.options.sourceApplication
    )
}
```

---

## Аутентификация пользователя

### MSALAuthManager — полная реализация

```swift
import MSAL
import Foundation

/// Менеджер аутентификации Microsoft Graph
final class MSALAuthManager: ObservableObject {
    
    // MARK: - Configuration
    
    private let clientId = "YOUR_CLIENT_ID"  // Из Azure Portal
    private let redirectUri = "msauth.com.vantaspeech.app://auth"
    private let authority = "https://login.microsoftonline.com/common"
    
    private let scopes = [
        "Calendars.ReadWrite",
        "User.Read",
        "offline_access"
    ]
    
    // MARK: - State
    
    private var application: MSALPublicClientApplication?
    @Published private(set) var currentAccount: MSALAccount?
    @Published private(set) var isSignedIn = false
    
    // MARK: - Initialization
    
    init() {
        setupApplication()
        loadCachedAccount()
    }
    
    private func setupApplication() {
        do {
            let authorityURL = URL(string: authority)!
            let msalAuthority = try MSALAADAuthority(url: authorityURL)
            
            let config = MSALPublicClientApplicationConfig(
                clientId: clientId,
                redirectUri: redirectUri,
                authority: msalAuthority
            )
            
            // Поддержка нескольких аккаунтов
            config.multipleCloudsSupported = true
            
            application = try MSALPublicClientApplication(configuration: config)
        } catch {
            print("❌ MSAL setup failed: \(error.localizedDescription)")
        }
    }
    
    private func loadCachedAccount() {
        guard let app = application else { return }
        
        do {
            let accounts = try app.allAccounts()
            if let account = accounts.first {
                currentAccount = account
                isSignedIn = true
            }
        } catch {
            print("⚠️ Failed to load cached account: \(error)")
        }
    }
    
    // MARK: - Sign In
    
    /// Интерактивный вход пользователя
    @MainActor
    func signIn(from viewController: UIViewController) async throws -> String {
        guard let app = application else {
            throw MSALAuthError.notConfigured
        }
        
        let webParameters = MSALWebviewParameters(authPresentationViewController: viewController)
        let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParameters)
        
        // Подсказка для выбора аккаунта
        parameters.promptType = .selectAccount
        
        return try await withCheckedThrowingContinuation { continuation in
            app.acquireToken(with: parameters) { [weak self] result, error in
                if let error = error {
                    let nsError = error as NSError
                    
                    // Пользователь отменил
                    if nsError.domain == MSALErrorDomain &&
                       nsError.code == MSALError.userCanceled.rawValue {
                        continuation.resume(throwing: MSALAuthError.userCanceled)
                        return
                    }
                    
                    continuation.resume(throwing: MSALAuthError.signInFailed(error))
                    return
                }
                
                guard let result = result else {
                    continuation.resume(throwing: MSALAuthError.noResult)
                    return
                }
                
                self?.currentAccount = result.account
                self?.isSignedIn = true
                
                continuation.resume(returning: result.accessToken)
            }
        }
    }
    
    // MARK: - Silent Token Acquisition
    
    /// Получение токена без UI (для фоновой синхронизации)
    func acquireTokenSilently() async throws -> String {
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
    }
    
    // MARK: - Sign Out
    
    /// Выход из аккаунта
    @MainActor
    func signOut(from viewController: UIViewController) async throws {
        guard let app = application, let account = currentAccount else { return }
        
        let webParameters = MSALWebviewParameters(authPresentationViewController: viewController)
        let parameters = MSALSignoutParameters(webviewParameters: webParameters)
        parameters.signoutFromBrowser = true
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            app.signout(with: account, signoutParameters: parameters) { [weak self] success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                self?.currentAccount = nil
                self?.isSignedIn = false
                continuation.resume()
            }
        }
    }
    
    /// Локальный выход (без очистки сессии браузера)
    func signOutLocally() {
        guard let app = application, let account = currentAccount else { return }
        
        try? app.remove(account)
        currentAccount = nil
        isSignedIn = false
    }
}

// MARK: - Errors

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
            return "MSAL not configured"
        case .noAccount:
            return "No signed-in account"
        case .noResult:
            return "No result from authentication"
        case .userCanceled:
            return "User canceled sign-in"
        case .interactionRequired:
            return "Interactive sign-in required"
        case .signInFailed(let error):
            return "Sign-in failed: \(error.localizedDescription)"
        case .tokenAcquisitionFailed(let error):
            return "Token acquisition failed: \(error.localizedDescription)"
        }
    }
}
```

### Использование в SwiftUI

```swift
struct SettingsView: View {
    @StateObject private var authManager = MSALAuthManager()
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        VStack(spacing: 20) {
            if authManager.isSignedIn {
                Text("Connected to Outlook")
                Button("Disconnect") {
                    Task { await signOut() }
                }
            } else {
                Button("Connect Outlook Calendar") {
                    Task { await signIn() }
                }
                .disabled(isLoading)
            }
            
            if let error = error {
                Text(error).foregroundColor(.red)
            }
        }
    }
    
    private func signIn() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let viewController = windowScene.windows.first?.rootViewController else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let token = try await authManager.signIn(from: viewController)
            print("✅ Got access token: \(token.prefix(20))...")
        } catch MSALAuthError.userCanceled {
            // Пользователь отменил — не показываем ошибку
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func signOut() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let viewController = windowScene.windows.first?.rootViewController else { return }
        
        try? await authManager.signOut(from: viewController)
    }
}
```

---

## Работа с событиями календаря

### GraphCalendarService — основной сервис

```swift
import Foundation

/// Сервис для работы с календарём через Microsoft Graph API
final class GraphCalendarService {
    
    private let baseURL = "https://graph.microsoft.com/v1.0"
    private let authManager: MSALAuthManager
    
    init(authManager: MSALAuthManager) {
        self.authManager = authManager
    }
    
    // MARK: - Private Helpers
    
    private func authorizedRequest(url: URL, method: String = "GET") async throws -> URLRequest {
        let token = try await authManager.acquireTokenSilently()
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        return request
    }
    
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GraphError.invalidResponse
        }
        
        // Обработка ошибок
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
            // Rate limiting — получить Retry-After header
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
        
        let request = try await authorizedRequest(url: components.url!)
        let response: GraphEventsResponse = try await performRequest(request)
        
        return response.value
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
    func createEvent(_ event: CreateEventRequest) async throws -> GraphEvent {
        let url = URL(string: "\(baseURL)/me/events")!
        var request = try await authorizedRequest(url: url, method: "POST")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(event)
        
        return try await performRequest(request)
    }
}

// MARK: - Update Event

extension GraphCalendarService {
    
    /// Обновить существующее событие (частичное обновление)
    func updateEvent(id: String, changes: UpdateEventRequest) async throws -> GraphEvent {
        let url = URL(string: "\(baseURL)/me/events/\(id)")!
        var request = try await authorizedRequest(url: url, method: "PATCH")
        
        request.httpBody = try JSONEncoder().encode(changes)
        
        return try await performRequest(request)
    }
    
    /// Переименовать событие
    func renameEvent(id: String, newTitle: String) async throws -> GraphEvent {
        return try await updateEvent(id: id, changes: UpdateEventRequest(subject: newTitle))
    }
}

// MARK: - Delete Event

extension GraphCalendarService {
    
    /// Удалить событие
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
```

### Модели данных

```swift
import Foundation

// MARK: - Response Models

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
    let location: Location?
    
    /// Флаг удаления (для delta sync)
    var removed: Removed?
    
    enum CodingKeys: String, CodingKey {
        case id, subject, bodyPreview, start, end
        case attendees, organizer, isOrganizer
        case iCalUId, webLink, location
        case removed = "@removed"
    }
    
    var startDate: Date? {
        ISO8601DateFormatter().date(from: start.dateTime)
    }
    
    var endDate: Date? {
        ISO8601DateFormatter().date(from: end.dateTime)
    }
}

struct DateTimeTimeZone: Codable {
    let dateTime: String
    let timeZone: String
}

struct GraphAttendee: Codable {
    let emailAddress: EmailAddress
    let type: String           // required, optional, resource
    let status: ResponseStatus?
}

struct EmailAddress: Codable {
    let address: String
    let name: String?
}

struct ResponseStatus: Codable {
    let response: String       // none, accepted, declined, tentativelyAccepted
    let time: String?
}

struct Organizer: Codable {
    let emailAddress: EmailAddress
}

struct Location: Codable {
    let displayName: String?
    let address: PhysicalAddress?
}

struct PhysicalAddress: Codable {
    let street: String?
    let city: String?
    let state: String?
    let countryOrRegion: String?
    let postalCode: String?
}

struct Removed: Codable {
    let reason: String  // "deleted" или "changed"
}

// MARK: - Request Models

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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        self.subject = subject
        self.start = DateTimeTimeZone(dateTime: formatter.string(from: start), timeZone: timeZone)
        self.end = DateTimeTimeZone(dateTime: formatter.string(from: end), timeZone: timeZone)
        self.body = body.map { EventBody(contentType: "text", content: $0) }
        self.attendees = attendees?.map { AttendeeRequest(emailAddress: EmailAddress(address: $0, name: nil), type: "required") }
        self.location = location.map { LocationRequest(displayName: $0) }
    }
}

struct UpdateEventRequest: Codable {
    var subject: String?
    var start: DateTimeTimeZone?
    var end: DateTimeTimeZone?
    var body: EventBody?
    var location: LocationRequest?
}

struct EventBody: Codable {
    let contentType: String  // "text" или "html"
    let content: String
}

struct AttendeeRequest: Codable {
    let emailAddress: EmailAddress
    let type: String
}

struct LocationRequest: Codable {
    let displayName: String
}

// MARK: - Errors

enum GraphError: LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: Int)
    case httpError(statusCode: Int, data: Data)
    case deleteFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Authentication required"
        case .forbidden:
            return "Access denied"
        case .notFound:
            return "Event not found"
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry after \(retryAfter) seconds"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .deleteFailed:
            return "Failed to delete event"
        }
    }
}
```

---

## Получение участников встречи

### Полный доступ к email участников

**В отличие от Apple EventKit, Microsoft Graph предоставляет полные данные об участниках:**

```swift
extension GraphCalendarService {
    
    /// Получить участников события с их статусами
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

// MARK: - Participant Models

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

enum ParticipantRole {
    case organizer
    case required
    case optional
}

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
```

### Использование участников в контексте встречи

```swift
struct MeetingContextView: View {
    let event: GraphEvent
    @State private var participants: [MeetingParticipant] = []
    @EnvironmentObject private var calendarService: GraphCalendarService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.subject ?? "Без названия")
                .font(.headline)
            
            if !participants.isEmpty {
                Text("Участники")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ForEach(participants) { participant in
                    HStack {
                        Image(systemName: participant.responseStatus.iconName)
                            .foregroundColor(colorFor(participant.responseStatus))
                        
                        VStack(alignment: .leading) {
                            Text(participant.displayName)
                            Text(participant.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if participant.role == .organizer {
                            Text("Организатор")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .task {
            participants = (try? await calendarService.getAttendees(eventId: event.id)) ?? []
        }
    }
    
    private func colorFor(_ status: ParticipantResponseStatus) -> Color {
        switch status {
        case .accepted: return .green
        case .declined: return .red
        case .tentative: return .orange
        case .notResponded: return .gray
        }
    }
}
```

---

## Инкрементальная синхронизация (Delta Queries)

### Принцип работы Delta Queries

Delta queries позволяют получать **только изменения** с момента последней синхронизации:

1. Первый запрос возвращает все события + `deltaLink`
2. Последующие запросы по `deltaLink` возвращают только изменённые/удалённые события
3. Удалённые события помечены `@removed: { reason: "deleted" }`

**Экономия трафика**: вместо загрузки 500 событий — только 3 изменённых.

### GraphCalendarSyncService

```swift
import Foundation

/// Сервис инкрементальной синхронизации календаря
final class GraphCalendarSyncService {
    
    private let baseURL = "https://graph.microsoft.com/v1.0"
    private let authManager: MSALAuthManager
    private let storage: SyncStorageProtocol
    
    // Delta link хранится между сессиями
    private var deltaLink: String? {
        get { storage.getDeltaLink() }
        set { storage.saveDeltaLink(newValue) }
    }
    
    init(authManager: MSALAuthManager, storage: SyncStorageProtocol) {
        self.authManager = authManager
        self.storage = storage
    }
    
    /// Синхронизировать календарь
    /// - Returns: Кортеж (обновлённые события, удалённые ID)
    func sync() async throws -> SyncResult {
        if let deltaLink = deltaLink {
            return try await incrementalSync(deltaLink: deltaLink)
        } else {
            return try await fullSync()
        }
    }
    
    // MARK: - Full Sync
    
    private func fullSync() async throws -> SyncResult {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        // Синхронизируем события за последние 3 месяца + 3 месяца вперёд
        let startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        let endDate = Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        
        var components = URLComponents(string: "\(baseURL)/me/calendarView/delta")!
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: formatter.string(from: startDate)),
            URLQueryItem(name: "endDateTime", value: formatter.string(from: endDate)),
            URLQueryItem(name: "$select", value: "id,subject,start,end,attendees,organizer,isOrganizer,iCalUId")
        ]
        
        return try await fetchAllPages(startingFrom: components.url!)
    }
    
    // MARK: - Incremental Sync
    
    private func incrementalSync(deltaLink: String) async throws -> SyncResult {
        guard let url = URL(string: deltaLink) else {
            // Невалидный delta link — делаем full sync
            self.deltaLink = nil
            return try await fullSync()
        }
        
        do {
            return try await fetchAllPages(startingFrom: url)
        } catch GraphError.httpError(statusCode: 410, _) {
            // 410 Gone = delta link expired
            self.deltaLink = nil
            return try await fullSync()
        }
    }
    
    // MARK: - Pagination
    
    private func fetchAllPages(startingFrom url: URL) async throws -> SyncResult {
        var allEvents: [GraphEvent] = []
        var deletedIds: [String] = []
        var currentURL: URL? = url
        
        while let url = currentURL {
            let token = try await authManager.acquireTokenSilently()
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GraphError.invalidResponse
            }
            
            if httpResponse.statusCode == 410 {
                throw GraphError.httpError(statusCode: 410, data: data)
            }
            
            guard httpResponse.statusCode == 200 else {
                throw GraphError.httpError(statusCode: httpResponse.statusCode, data: data)
            }
            
            let decoded = try JSONDecoder().decode(GraphEventsResponse.self, from: data)
            
            for event in decoded.value {
                if event.removed != nil {
                    deletedIds.append(event.id)
                } else {
                    allEvents.append(event)
                }
            }
            
            // Проверяем наличие следующей страницы
            if let nextLink = decoded.nextLink {
                currentURL = URL(string: nextLink)
            } else {
                // Сохраняем delta link для следующей синхронизации
                self.deltaLink = decoded.deltaLink
                currentURL = nil
            }
        }
        
        return SyncResult(
            updatedEvents: allEvents,
            deletedEventIds: deletedIds,
            isFullSync: deltaLink == nil
        )
    }
    
    /// Сбросить delta link (принудительная полная синхронизация)
    func resetSync() {
        deltaLink = nil
    }
}

// MARK: - Models

struct SyncResult {
    let updatedEvents: [GraphEvent]
    let deletedEventIds: [String]
    let isFullSync: Bool
    
    var isEmpty: Bool {
        updatedEvents.isEmpty && deletedEventIds.isEmpty
    }
}

protocol SyncStorageProtocol {
    func getDeltaLink() -> String?
    func saveDeltaLink(_ link: String?)
}

// MARK: - UserDefaults Storage

final class UserDefaultsSyncStorage: SyncStorageProtocol {
    private let key = "com.vantaspeech.outlookDeltaLink"
    
    func getDeltaLink() -> String? {
        UserDefaults.standard.string(forKey: key)
    }
    
    func saveDeltaLink(_ link: String?) {
        if let link = link {
            UserDefaults.standard.set(link, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
```

### Обработка результатов синхронизации

```swift
final class CalendarSyncManager: ObservableObject {
    
    private let syncService: GraphCalendarSyncService
    private let eventStore: LocalEventStore  // Локальное хранилище (Core Data / SwiftData)
    
    @Published var lastSyncDate: Date?
    @Published var isSyncing = false
    
    func performSync() async {
        guard !isSyncing else { return }
        
        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }
        
        do {
            let result = try await syncService.sync()
            
            // Применяем изменения к локальному хранилищу
            await eventStore.applyChanges(
                updated: result.updatedEvents,
                deleted: result.deletedEventIds
            )
            
            await MainActor.run {
                lastSyncDate = Date()
            }
            
            print("✅ Sync completed: \(result.updatedEvents.count) updated, \(result.deletedEventIds.count) deleted")
            
        } catch MSALAuthError.interactionRequired {
            // Требуется повторный вход
            await MainActor.run {
                // Показать UI для повторного входа
            }
        } catch {
            print("❌ Sync failed: \(error)")
        }
    }
}
```

---

## Безопасное хранение токенов

### MSAL автоматически управляет токенами

**MSAL SDK самостоятельно сохраняет токены в iOS Keychain** — дополнительная реализация не требуется.

Однако для `deltaLink` и других данных синхронизации рекомендуется отдельное безопасное хранилище:

```swift
import Security

final class SecureStorage {
    
    private let service = "com.vantaspeech.calendar"
    
    enum Key: String {
        case deltaLink = "outlook_delta_link"
        case lastSyncDate = "last_sync_date"
    }
    
    // MARK: - Save
    
    func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecureStorageError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            // Важно для background sync
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        
        // Удаляем существующий
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.saveFailed(status)
        }
    }
    
    // MARK: - Retrieve
    
    func retrieve(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    // MARK: - Delete
    
    func delete(for key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

enum SecureStorageError: Error {
    case invalidData
    case saveFailed(OSStatus)
}
```

### Accessibility уровни для Keychain

| Значение | Доступ при заблокированном устройстве | Рекомендация |
|----------|--------------------------------------|--------------|
| `kSecAttrAccessibleWhenUnlocked` | ❌ | Только foreground |
| `kSecAttrAccessibleAfterFirstUnlock` | ✅ | **Для sync данных** |
| `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` | ❌ | Максимальная защита |

---

## Фоновая синхронизация

### Ограничения iOS

| Ограничение | Значение |
|-------------|----------|
| Максимальное время выполнения | ~30 секунд |
| Гарантия выполнения | ❌ Не гарантировано |
| Low Power Mode | Фоновые задачи отключены |
| Батарея < 20% | Задачи откладываются |

**Реалистичные ожидания**: фоновая синхронизация — это "nice to have", а не основной механизм. Главная синхронизация должна происходить при открытии приложения.

### BGTaskScheduler реализация

**Info.plist:**

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.vantaspeech.calendarSync</string>
</array>
```

**Capabilities**: Background Modes → Background fetch ✓

```swift
import BackgroundTasks

final class BackgroundSyncManager {
    
    static let taskIdentifier = "com.vantaspeech.calendarSync"
    
    private let syncManager: CalendarSyncManager
    
    init(syncManager: CalendarSyncManager) {
        self.syncManager = syncManager
    }
    
    // MARK: - Registration
    
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }
    }
    
    // MARK: - Scheduling
    
    func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        
        // Минимум 15 минут до следующего запуска
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background sync scheduled")
        } catch {
            print("⚠️ Failed to schedule background sync: \(error)")
        }
    }
    
    // MARK: - Execution
    
    private func handleBackgroundSync(task: BGAppRefreshTask) {
        // Запланировать следующую задачу
        scheduleBackgroundSync()
        
        let syncTask = Task {
            await syncManager.performSync()
        }
        
        task.expirationHandler = {
            syncTask.cancel()
        }
        
        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }
}

// MARK: - AppDelegate Integration

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    let backgroundSyncManager = BackgroundSyncManager(
        syncManager: CalendarSyncManager(/* ... */)
    )
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        backgroundSyncManager.registerBackgroundTask()
        
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        backgroundSyncManager.scheduleBackgroundSync()
    }
}
```

### Синхронизация при открытии приложения

**Основной механизм синхронизации:**

```swift
struct ContentView: View {
    @StateObject private var syncManager: CalendarSyncManager
    
    var body: some View {
        MainTabView()
            .task {
                // Синхронизация при каждом открытии
                await syncManager.performSync()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Синхронизация при возврате из background
                Task {
                    await syncManager.performSync()
                }
            }
    }
}
```

---

## Связывание записей с событиями

### Стратегия хранения связей

```swift
import Foundation
import SwiftData

@Model
final class MeetingRecording {
    @Attribute(.unique) var id: UUID
    
    // Связь с событием Outlook
    var outlookEventId: String?
    var outlookICalUID: String?  // Более стабильный идентификатор
    
    // Кэшированные данные события (для офлайн доступа)
    var eventTitle: String?
    var eventStartDate: Date?
    var eventEndDate: Date?
    var cachedAttendees: [CachedAttendee]?
    
    // Данные записи
    var recordingURL: URL
    var transcription: String?
    var duration: TimeInterval
    var createdAt: Date
    
    init(recordingURL: URL, duration: TimeInterval) {
        self.id = UUID()
        self.recordingURL = recordingURL
        self.duration = duration
        self.createdAt = Date()
    }
}

struct CachedAttendee: Codable {
    let email: String
    let name: String?
    let role: String
    let responseStatus: String
}
```

### Связывание записи с событием

```swift
extension MeetingRecording {
    
    /// Связать запись с событием календаря
    func link(to event: GraphEvent) {
        self.outlookEventId = event.id
        self.outlookICalUID = event.iCalUId
        self.eventTitle = event.subject
        self.eventStartDate = event.startDate
        self.eventEndDate = event.endDate
        
        // Кэшируем участников
        self.cachedAttendees = event.attendees?.map { attendee in
            CachedAttendee(
                email: attendee.emailAddress.address,
                name: attendee.emailAddress.name,
                role: attendee.type,
                responseStatus: attendee.status?.response ?? "none"
            )
        }
    }
    
    /// Отвязать запись от события
    func unlink() {
        self.outlookEventId = nil
        self.outlookICalUID = nil
        // Сохраняем кэшированные данные для истории
    }
}
```

### Автоматическое связывание по времени

```swift
final class RecordingLinkService {
    
    private let calendarService: GraphCalendarService
    
    init(calendarService: GraphCalendarService) {
        self.calendarService = calendarService
    }
    
    /// Найти подходящее событие для записи
    func findMatchingEvent(
        for recording: MeetingRecording,
        toleranceMinutes: Int = 15
    ) async throws -> GraphEvent? {
        
        let tolerance = TimeInterval(toleranceMinutes * 60)
        let searchStart = recording.createdAt.addingTimeInterval(-tolerance)
        let searchEnd = recording.createdAt.addingTimeInterval(recording.duration + tolerance)
        
        let events = try await calendarService.fetchEvents(
            from: searchStart,
            to: searchEnd
        )
        
        // Ищем событие, которое перекрывается со временем записи
        return events.first { event in
            guard let eventStart = event.startDate,
                  let eventEnd = event.endDate else { return false }
            
            // Проверяем перекрытие временных интервалов
            let recordingEnd = recording.createdAt.addingTimeInterval(recording.duration)
            return eventStart <= recordingEnd && eventEnd >= recording.createdAt
        }
    }
    
    /// Автоматически связать запись с ближайшим событием
    func autoLink(recording: MeetingRecording) async throws -> Bool {
        guard recording.outlookEventId == nil else {
            return false // Уже связано
        }
        
        if let matchingEvent = try await findMatchingEvent(for: recording) {
            recording.link(to: matchingEvent)
            return true
        }
        
        return false
    }
}
```

### Обработка изменения Event ID

```swift
final class EventLinkValidator {
    
    private let calendarService: GraphCalendarService
    
    init(calendarService: GraphCalendarService) {
        self.calendarService = calendarService
    }
    
    /// Проверить и обновить связь с событием
    func validateLink(for recording: MeetingRecording) async throws -> LinkValidationResult {
        guard let eventId = recording.outlookEventId else {
            return .notLinked
        }
        
        do {
            // Пробуем получить событие по ID
            let event = try await calendarService.fetchEvent(id: eventId)
            
            // Обновляем кэшированные данные
            recording.link(to: event)
            return .valid
            
        } catch GraphError.notFound {
            // Событие удалено или ID изменился
            
            // Пробуем найти по iCalUId (более стабильный)
            if let iCalUId = recording.outlookICalUID {
                if let event = try await findEventByICalUID(iCalUId) {
                    recording.link(to: event)
                    return .relinked(newId: event.id)
                }
            }
            
            // Пробуем найти по title + date
            if let title = recording.eventTitle,
               let startDate = recording.eventStartDate {
                if let event = try await findEventByTitleAndDate(title: title, date: startDate) {
                    recording.link(to: event)
                    return .relinked(newId: event.id)
                }
            }
            
            return .orphaned
        }
    }
    
    private func findEventByICalUID(_ iCalUId: String) async throws -> GraphEvent? {
        // Graph API не поддерживает прямой поиск по iCalUId
        // Нужно искать среди закэшированных событий
        // или использовать $filter (требует additional permissions)
        return nil
    }
    
    private func findEventByTitleAndDate(title: String, date: Date) async throws -> GraphEvent? {
        let events = try await calendarService.fetchEvents(
            from: date.addingTimeInterval(-300),  // ±5 минут
            to: date.addingTimeInterval(300)
        )
        
        return events.first { $0.subject == title }
    }
}

enum LinkValidationResult {
    case valid
    case relinked(newId: String)
    case orphaned
    case notLinked
}
```

---

## Обработка ошибок

### Централизованная обработка

```swift
final class CalendarErrorHandler {
    
    func handle(_ error: Error) -> CalendarErrorAction {
        
        // MSAL ошибки
        if let msalError = error as? MSALAuthError {
            switch msalError {
            case .interactionRequired:
                return .requiresReauth
            case .userCanceled:
                return .dismiss
            case .noAccount:
                return .requiresSignIn
            default:
                return .showError(msalError.localizedDescription)
            }
        }
        
        // Graph API ошибки
        if let graphError = error as? GraphError {
            switch graphError {
            case .unauthorized:
                return .requiresReauth
            case .forbidden:
                return .showError("Нет доступа к календарю. Проверьте разрешения.")
            case .notFound:
                return .eventNotFound
            case .rateLimited(let retryAfter):
                return .retryAfter(seconds: retryAfter)
            default:
                return .showError(graphError.localizedDescription)
            }
        }
        
        // Сетевые ошибки
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .offline
            case .timedOut:
                return .retry
            default:
                return .showError("Ошибка сети: \(urlError.localizedDescription)")
            }
        }
        
        return .showError(error.localizedDescription)
    }
}

enum CalendarErrorAction {
    case dismiss
    case showError(String)
    case requiresSignIn
    case requiresReauth
    case eventNotFound
    case retryAfter(seconds: Int)
    case retry
    case offline
}
```

### UI для обработки ошибок

```swift
struct CalendarErrorView: View {
    let action: CalendarErrorAction
    let onRetry: () -> Void
    let onReauth: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            switch action {
            case .offline:
                Image(systemName: "wifi.slash")
                    .font(.largeTitle)
                Text("Нет подключения к интернету")
                Button("Повторить", action: onRetry)
                
            case .requiresReauth:
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.largeTitle)
                Text("Требуется повторный вход")
                Button("Войти в Outlook", action: onReauth)
                
            case .retryAfter(let seconds):
                Image(systemName: "clock")
                    .font(.largeTitle)
                Text("Слишком много запросов")
                Text("Повтор через \(seconds) сек.")
                    .foregroundColor(.secondary)
                
            case .showError(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(message)
                Button("Повторить", action: onRetry)
                
            default:
                EmptyView()
            }
        }
        .padding()
    }
}
```

---

## Рекомендуемая архитектура

### Структура модулей

```
VantaSpeech/
├── Calendar/
│   ├── Auth/
│   │   └── MSALAuthManager.swift
│   ├── API/
│   │   ├── GraphCalendarService.swift
│   │   └── GraphModels.swift
│   ├── Sync/
│   │   ├── GraphCalendarSyncService.swift
│   │   ├── CalendarSyncManager.swift
│   │   └── BackgroundSyncManager.swift
│   ├── Storage/
│   │   ├── SecureStorage.swift
│   │   └── LocalEventStore.swift
│   ├── Linking/
│   │   ├── RecordingLinkService.swift
│   │   └── EventLinkValidator.swift
│   └── UI/
│       ├── CalendarConnectionView.swift
│       ├── EventPickerView.swift
│       └── MeetingContextView.swift
└── ...
```

### Dependency Injection

```swift
@MainActor
final class CalendarDependencies: ObservableObject {
    
    let authManager: MSALAuthManager
    let calendarService: GraphCalendarService
    let syncService: GraphCalendarSyncService
    let syncManager: CalendarSyncManager
    let linkService: RecordingLinkService
    
    init() {
        self.authManager = MSALAuthManager()
        self.calendarService = GraphCalendarService(authManager: authManager)
        
        let storage = UserDefaultsSyncStorage()
        self.syncService = GraphCalendarSyncService(authManager: authManager, storage: storage)
        
        self.syncManager = CalendarSyncManager(/* ... */)
        self.linkService = RecordingLinkService(calendarService: calendarService)
    }
}

// Использование в SwiftUI
struct VantaSpeechApp: App {
    @StateObject private var calendarDeps = CalendarDependencies()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(calendarDeps)
        }
    }
}
```

---

## Чек-лист для запуска

### Настройка Azure AD

- [ ] Создать App Registration в Azure Portal
- [ ] Настроить Redirect URI для iOS (Bundle ID)
- [ ] Включить "Allow public client flows"
- [ ] Сохранить Client ID

### Настройка Xcode проекта

- [ ] Добавить MSAL через SPM
- [ ] Настроить CFBundleURLSchemes в Info.plist
- [ ] Добавить LSApplicationQueriesSchemes
- [ ] Включить Keychain Sharing capability (`com.microsoft.adalcache`)
- [ ] Включить Background fetch capability (опционально)
- [ ] Добавить BGTaskSchedulerPermittedIdentifiers (опционально)

### Реализация

- [ ] MSALAuthManager — аутентификация
- [ ] GraphCalendarService — базовые операции
- [ ] GraphCalendarSyncService — инкрементальная синхронизация
- [ ] Модели данных для локального хранения
- [ ] RecordingLinkService — связывание записей

### Тестирование

- [ ] Sign in / Sign out flow
- [ ] Получение событий
- [ ] Создание события
- [ ] Обновление названия события
- [ ] Получение участников
- [ ] Инкрементальная синхронизация
- [ ] Обработка истёкшего токена
- [ ] Офлайн режим

---

## Полезные ссылки

- [Microsoft Graph Calendar API Reference](https://learn.microsoft.com/en-us/graph/api/resources/calendar)
- [MSAL for iOS Documentation](https://github.com/AzureAD/microsoft-authentication-library-for-objc)
- [Delta Query Documentation](https://learn.microsoft.com/en-us/graph/delta-query-overview)
- [Azure App Registration Guide](https://learn.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)
