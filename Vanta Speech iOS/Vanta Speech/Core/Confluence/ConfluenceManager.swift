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

    /// Сохранить настройки экспорта по умолчанию
    func saveDefaultExportLocation(spaceKey: String, pageId: String?, pageTitle: String?) {
        defaultSpaceKey = spaceKey
        defaultParentPageId = pageId
        defaultParentPageTitle = pageTitle
    }

    /// Очистить настройки экспорта
    func clearExportSettings() {
        defaultSpaceKey = nil
        defaultParentPageId = nil
        defaultParentPageTitle = nil
    }
}
