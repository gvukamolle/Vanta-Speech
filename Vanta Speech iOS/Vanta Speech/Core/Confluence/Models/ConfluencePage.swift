import Foundation

/// Confluence Page
struct ConfluencePage: Codable, Identifiable, Equatable, Hashable {
    /// ID страницы (строка, хотя на самом деле число)
    let id: String

    /// Тип контента (page)
    let type: String

    /// Статус (current, draft)
    let status: String

    /// Заголовок страницы
    let title: String

    /// Версия страницы
    let version: PageVersion?

    /// Информация о пространстве
    let space: SpaceInfo?

    /// Ссылки
    let _links: PageLinks?

    struct PageVersion: Codable, Equatable, Hashable {
        let number: Int
        let message: String?
        let minorEdit: Bool?
    }

    struct SpaceInfo: Codable, Equatable, Hashable {
        let key: String
        let name: String?
    }

    struct PageLinks: Codable, Equatable, Hashable {
        let webui: String?
        let tinyui: String?
        let base: String?
    }

    /// Web URL для открытия страницы в браузере
    var webURL: URL? {
        guard let webui = _links?.webui,
              let base = _links?.base else { return nil }
        return URL(string: base + webui)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - API Responses

/// Ответ от GET /content/{id}/child/page
struct ChildPagesResponse: Codable {
    let results: [ConfluencePage]
    let start: Int
    let limit: Int
    let size: Int
    let _links: PaginationLinks?

    struct PaginationLinks: Codable {
        let base: String?
        let context: String?
        let next: String?
    }
}

// MARK: - API Requests

/// Запрос на создание страницы
struct CreatePageRequest: Encodable {
    let type: String = "page"
    let title: String
    let space: SpaceKey
    let ancestors: [Ancestor]?
    let body: PageBody

    struct SpaceKey: Encodable {
        let key: String
    }

    struct Ancestor: Encodable {
        let id: String
    }

    struct PageBody: Encodable {
        let storage: StorageFormat

        struct StorageFormat: Encodable {
            let value: String
            let representation: String = "storage"
        }
    }

    init(title: String, spaceKey: String, parentPageId: String?, content: String) {
        self.title = title
        self.space = SpaceKey(key: spaceKey)
        self.ancestors = parentPageId.map { [Ancestor(id: $0)] }
        self.body = PageBody(storage: PageBody.StorageFormat(value: content))
    }
}

/// Запрос на обновление страницы
struct UpdatePageRequest: Encodable {
    let type: String = "page"
    let title: String
    let version: Version
    let body: PageBody

    struct Version: Encodable {
        let number: Int
    }

    struct PageBody: Encodable {
        let storage: StorageFormat

        struct StorageFormat: Encodable {
            let value: String
            let representation: String = "storage"
        }
    }

    init(title: String, content: String, newVersion: Int) {
        self.title = title
        self.version = Version(number: newVersion)
        self.body = PageBody(storage: PageBody.StorageFormat(value: content))
    }
}
