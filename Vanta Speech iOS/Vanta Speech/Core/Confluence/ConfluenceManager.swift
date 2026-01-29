import Foundation
import Combine

/// Manager для Confluence операций
@MainActor
final class ConfluenceManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ConfluenceManager()

    // MARK: - Published State

    @Published private(set) var isLoading = false
    @Published private(set) var spaces: [ConfluenceSpace] = []
    @Published private(set) var lastError: ConfluenceError?
    @Published private(set) var isConnected = false

    // MARK: - Export Settings

    /// Выбранный Space key для экспорта по умолчанию
    @Published var defaultSpaceKey: String? {
        didSet { saveExportSettings() }
    }

    /// Выбранный Parent Page ID для экспорта по умолчанию
    @Published var defaultParentPageId: String? {
        didSet { saveExportSettings() }
    }

    /// Название выбранной папки для отображения
    @Published var defaultParentPageTitle: String? {
        didSet { saveExportSettings() }
    }

    // MARK: - Private Properties

    private let client: ConfluenceClient
    private let keychainManager: KeychainManager

    // MARK: - Computed Properties

    /// Доступна ли интеграция (есть ли credentials)
    var isAvailable: Bool {
        client.hasCredentials
    }

    // MARK: - Initialization

    private init(
        client: ConfluenceClient = ConfluenceClient(),
        keychainManager: KeychainManager = .shared
    ) {
        self.client = client
        self.keychainManager = keychainManager
        loadExportSettings()
        
        // Проверяем состояние подключения при инициализации
        isConnected = client.hasCredentials
    }

    // MARK: - Public API - Connection
    
    /// Подключиться к Confluence с указанными credentials
    /// - Parameters:
    ///   - username: Логин пользователя (без домена)
    ///   - password: Пароль
    /// - Returns: true если подключение успешно
    func connect(username: String, password: String) async -> Bool {
        isLoading = true
        lastError = nil
        
        do {
            // Сохраняем credentials
            try client.saveCredentials(username: username, password: password)
            
            // Тестируем соединение (загружаем пространства)
            let spacesResponse = try await client.getSpaces(limit: 1)
            
            isConnected = true
            isLoading = false
            
            // Загружаем все пространства для кеширования
            await loadSpaces()
            
            debugLog("Confluence connected successfully, found \(spacesResponse.results.count) spaces", module: "Confluence", level: .info)
            
            return true
            
        } catch let error as ConfluenceError {
            lastError = error
            isConnected = false
            isLoading = false
            
            // Очищаем credentials при ошибке аутентификации
            if case .authenticationFailed = error {
                client.clearCredentials()
            }
            
            debugLog("Confluence connection failed: \(error.localizedDescription)", module: "Confluence", level: .error)
            return false
            
        } catch {
            lastError = .networkError(error.localizedDescription)
            isConnected = false
            isLoading = false
            
            debugLog("Confluence connection failed with unknown error: \(error.localizedDescription)", module: "Confluence", level: .error)
            return false
        }
    }
    
    /// Отключиться от Confluence и очистить credentials
    func disconnect() {
        client.clearCredentials()
        spaces = []
        isConnected = false
        lastError = nil
        
        // Очищаем настройки экспорта
        clearExportSettings()
        
        debugLog("Confluence disconnected", module: "Confluence", level: .info)
    }

    // MARK: - Public API - Spaces & Pages

    /// Загрузить пространства
    func loadSpaces() async {
        guard isAvailable else {
            lastError = .notAuthenticated
            return
        }

        isLoading = true
        lastError = nil

        do {
            let response = try await client.getSpaces()
            spaces = response.results
        } catch let error as ConfluenceError {
            lastError = error
            debugLog("Confluence loadSpaces error: \(error.localizedDescription)", module: "Confluence", level: .error)
        } catch {
            lastError = .networkError(error.localizedDescription)
        }

        isLoading = false
    }

    /// Получить корневые страницы пространства
    func getRootPages(spaceKey: String) async throws -> [ConfluencePage] {
        let response = try await client.getRootPages(spaceKey: spaceKey)
        return response.results
    }

    /// Получить дочерние страницы
    func getChildPages(pageId: String) async throws -> [ConfluencePage] {
        let response = try await client.getChildPages(pageId: pageId)
        return response.results
    }

    /// Получить страницу по ID
    func getPage(pageId: String) async throws -> ConfluencePage {
        try await client.getPage(pageId: pageId)
    }

    // MARK: - Public API - Export

    /// Экспортировать саммари в Confluence
    func exportMeeting(
        recording: Recording,
        title: String,
        spaceKey: String,
        parentPageId: String?
    ) async throws -> ConfluencePage {
        guard isAvailable else {
            throw ConfluenceError.notAuthenticated
        }

        // Форматируем страницу
        let content = MeetingPageFormatter.format(recording: recording)

        // Создаём страницу
        let page = try await client.createPage(
            spaceKey: spaceKey,
            title: title,
            content: content,
            parentPageId: parentPageId
        )

        debugLog("Confluence page created: \(page.id)", module: "Confluence", level: .info)

        return page
    }

    /// Обновить существующую страницу (с автоматическим retry при конфликте версий)
    func updateMeeting(
        recording: Recording,
        pageId: String,
        title: String
    ) async throws -> ConfluencePage {
        guard isAvailable else {
            throw ConfluenceError.notAuthenticated
        }

        // Форматируем страницу
        let content = MeetingPageFormatter.format(recording: recording)

        // Обновляем с retry при конфликте версий
        let page = try await client.updatePageWithRetry(
            pageId: pageId,
            title: title,
            content: content
        )

        debugLog("Confluence page updated: \(page.id) (version \(page.version?.number ?? 0))", module: "Confluence", level: .info)

        return page
    }

    /// Save default export location preferences
    func saveDefaults(spaceKey: String, parentPageId: String?, parentPageTitle: String?) {
        UserDefaults.standard.set(spaceKey, forKey: "ConfluenceDefaultSpaceKey")
        if let pageId = parentPageId {
            UserDefaults.standard.set(pageId, forKey: "ConfluenceDefaultParentPageId")
        } else {
            UserDefaults.standard.removeObject(forKey: "ConfluenceDefaultParentPageId")
        }
        
        if let pageTitle = parentPageTitle {
            UserDefaults.standard.set(pageTitle, forKey: "ConfluenceDefaultParentPageTitle")
        } else {
            UserDefaults.standard.removeObject(forKey: "ConfluenceDefaultParentPageTitle")
        }
    }
    
    // MARK: - Private Methods

    // MARK: - Export Settings Persistence

    private func saveExportSettings() {
        UserDefaults.standard.set(defaultSpaceKey, forKey: "confluence_default_space")
        UserDefaults.standard.set(defaultParentPageId, forKey: "confluence_default_page_id")
        UserDefaults.standard.set(defaultParentPageTitle, forKey: "confluence_default_page_title")
    }

    private func loadExportSettings() {
        defaultSpaceKey = UserDefaults.standard.string(forKey: "confluence_default_space")
        defaultParentPageId = UserDefaults.standard.string(forKey: "confluence_default_page_id")
        defaultParentPageTitle = UserDefaults.standard.string(forKey: "confluence_default_page_title")
    }
    
    /// Очистить настройки экспорта
    private func clearExportSettings() {
        defaultSpaceKey = nil
        defaultParentPageId = nil
        defaultParentPageTitle = nil
        
        UserDefaults.standard.removeObject(forKey: "ConfluenceDefaultSpaceKey")
        UserDefaults.standard.removeObject(forKey: "ConfluenceDefaultParentPageId")
        UserDefaults.standard.removeObject(forKey: "ConfluenceDefaultParentPageTitle")
        UserDefaults.standard.removeObject(forKey: "confluence_default_space")
        UserDefaults.standard.removeObject(forKey: "confluence_default_page_id")
        UserDefaults.standard.removeObject(forKey: "confluence_default_page_title")
    }

    /// Сохранить настройки экспорта по умолчанию
    func saveDefaultExportLocation(spaceKey: String, pageId: String?, pageTitle: String?) {
        defaultSpaceKey = spaceKey
        defaultParentPageId = pageId
        defaultParentPageTitle = pageTitle
    }
}
