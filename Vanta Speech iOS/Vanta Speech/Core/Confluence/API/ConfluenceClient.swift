import Foundation
import Network

/// HTTP клиент для Confluence REST API
final class ConfluenceClient: NSObject {

    // MARK: - Properties

    private var session: URLSession!
    private let keychainManager: KeychainManager
    private let networkMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.vantaspeech.confluence.network")

    private var isNetworkAvailable = true

    /// Base URL сервера Confluence (HTTPS с самоподписанным сертификатом)
    private let serverURL = "https://cnfl.b2serv.local"

    // MARK: - Initialization

    init(
        keychainManager: KeychainManager = .shared
    ) {
        self.keychainManager = keychainManager
        self.networkMonitor = NWPathMonitor()

        super.init()

        // Создаём URLSession с делегатом для обработки самоподписанных сертификатов
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkAvailable = path.status == .satisfied
        }
        networkMonitor.start(queue: monitorQueue)
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Public API

    /// Проверить наличие credentials (залогинен ли пользователь)
    var hasCredentials: Bool {
        keychainManager.loadEASCredentials() != nil
    }

    /// Тест соединения с сервером
    func testConnection() async throws -> Bool {
        let _ = try await getSpaces(limit: 1)
        return true
    }

    /// Получить список пространств
    func getSpaces(limit: Int = 50, start: Int = 0) async throws -> SpacesResponse {
        let request = try buildRequest(
            endpoint: "space",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "start", value: "\(start)"),
                URLQueryItem(name: "type", value: "global")
            ]
        )
        return try await execute(request)
    }

    /// Получить корневые страницы пространства
    func getRootPages(spaceKey: String, limit: Int = 50) async throws -> ChildPagesResponse {
        let request = try buildRequest(
            endpoint: "space/\(spaceKey)/content/page",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "depth", value: "root")
            ]
        )
        return try await execute(request)
    }

    /// Получить дочерние страницы
    func getChildPages(pageId: String, limit: Int = 50) async throws -> ChildPagesResponse {
        let request = try buildRequest(
            endpoint: "content/\(pageId)/child/page",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        return try await execute(request)
    }

    /// Получить страницу по ID
    func getPage(pageId: String) async throws -> ConfluencePage {
        let request = try buildRequest(
            endpoint: "content/\(pageId)",
            queryItems: [
                URLQueryItem(name: "expand", value: "version,space")
            ]
        )
        return try await execute(request)
    }

    /// Создать страницу
    func createPage(
        spaceKey: String,
        title: String,
        content: String,
        parentPageId: String?
    ) async throws -> ConfluencePage {
        let body = CreatePageRequest(
            title: title,
            spaceKey: spaceKey,
            parentPageId: parentPageId,
            content: content
        )

        var request = try buildRequest(endpoint: "content", method: "POST")
        request.httpBody = try JSONEncoder().encode(body)

        return try await execute(request)
    }

    /// Обновить страницу
    func updatePage(
        pageId: String,
        title: String,
        content: String,
        currentVersion: Int
    ) async throws -> ConfluencePage {
        let body = UpdatePageRequest(
            title: title,
            content: content,
            newVersion: currentVersion + 1
        )

        var request = try buildRequest(endpoint: "content/\(pageId)", method: "PUT")
        request.httpBody = try JSONEncoder().encode(body)

        return try await execute(request)
    }

    /// Обновить страницу с автоматическим retry при конфликте версий
    /// - Parameters:
    ///   - pageId: ID страницы
    ///   - title: Новый заголовок
    ///   - content: Новый контент (Storage Format)
    ///   - maxRetries: Максимальное количество попыток (по умолчанию 3)
    /// - Returns: Обновлённая страница
    func updatePageWithRetry(
        pageId: String,
        title: String,
        content: String,
        maxRetries: Int = 3
    ) async throws -> ConfluencePage {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                // Получаем актуальную версию перед обновлением
                let currentPage = try await getPage(pageId: pageId)
                guard let version = currentPage.version?.number else {
                    throw ConfluenceError.parseError("Не удалось получить версию страницы")
                }

                // Пытаемся обновить
                return try await updatePage(
                    pageId: pageId,
                    title: title,
                    content: content,
                    currentVersion: version
                )
            } catch let error as ConfluenceError {
                // При конфликте версий - retry с exponential backoff
                if case .conflict = error {
                    lastError = error
                    let delay = UInt64(100_000_000 * (1 << attempt)) // 100ms, 200ms, 400ms...
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }

        throw lastError ?? ConfluenceError.conflict("Не удалось обновить страницу после \(maxRetries) попыток")
    }

    // MARK: - Private Methods

    private func getCredentials() throws -> (username: String, password: String) {
        // Используем EAS credentials (те же AD credentials)
        guard let easCredentials = keychainManager.loadEASCredentials() else {
            throw ConfluenceError.notAuthenticated
        }

        // Confluence требует username без @-домена (только логин)
        // EAS хранит как user@domain.com, извлекаем часть до @
        var username = easCredentials.username
        if let atIndex = username.firstIndex(of: "@") {
            username = String(username[..<atIndex])
        }
        // Также обрабатываем формат DOMAIN\user
        if let slashIndex = username.lastIndex(of: "\\") {
            username = String(username[username.index(after: slashIndex)...])
        }

        return (username, easCredentials.password)
    }

    private func buildRequest(
        endpoint: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        let credentials = try getCredentials()

        guard var components = URLComponents(string: "\(serverURL)/rest/api/\(endpoint)") else {
            throw ConfluenceError.invalidServerURL
        }

        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw ConfluenceError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        // Basic Auth
        let authString = "\(credentials.username):\(credentials.password)"
        if let authData = authString.data(using: .utf8) {
            request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("VantaSpeech/1.0", forHTTPHeaderField: "User-Agent")

        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        guard isNetworkAvailable else {
            throw ConfluenceError.offline
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ConfluenceError.networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200, 201:
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw ConfluenceError.parseError(error.localizedDescription)
                }
            case 401:
                throw ConfluenceError.authenticationFailed
            case 403:
                throw ConfluenceError.accessDenied
            case 404:
                throw ConfluenceError.notFound("Resource not found")
            case 409:
                let message = extractErrorMessage(from: data) ?? "Страница с таким названием уже существует"
                throw ConfluenceError.conflict(message)
            default:
                let message = extractErrorMessage(from: data)
                throw ConfluenceError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
        } catch let error as ConfluenceError {
            throw error
        } catch {
            throw ConfluenceError.networkError(error.localizedDescription)
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        // Confluence возвращает ошибки в JSON формате
        struct ErrorResponse: Decodable {
            let message: String?
            let reason: String?
        }
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return errorResponse.message ?? errorResponse.reason
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - URLSessionDelegate (Self-Signed Certificate Support)

extension ConfluenceClient: URLSessionDelegate {
    /// Обработка самоподписанных сертификатов для внутренних серверов
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Проверяем что это challenge для нашего сервера
        guard challenge.protectionSpace.host.contains("b2serv.local"),
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Принимаем самоподписанный сертификат для внутреннего сервера
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
}
