import Foundation

/// Confluence Space (пространство)
struct ConfluenceSpace: Codable, Identifiable, Equatable, Hashable {
    /// ID пространства (число)
    let id: Int

    /// Ключ пространства (например, "DOCS")
    let key: String

    /// Название пространства
    let name: String

    /// Тип пространства (global, personal)
    let type: String

    /// Ссылки
    let _links: SpaceLinks?

    var identifiableId: String { key }

    struct SpaceLinks: Codable, Equatable, Hashable {
        let webui: String?
        let base: String?
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

// MARK: - API Response

/// Ответ от GET /rest/api/space
struct SpacesResponse: Codable {
    let results: [ConfluenceSpace]
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
