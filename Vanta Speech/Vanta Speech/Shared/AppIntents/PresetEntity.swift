import AppIntents
import Foundation

/// Entity для шаблонов записи, используется в параметрах Shortcut
struct PresetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Шаблон записи")
    }

    static var defaultQuery = PresetEntityQuery()

    var id: String
    var displayName: String
    var icon: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: displayName),
            subtitle: nil,
            image: .init(systemName: icon)
        )
    }

    init(id: String, displayName: String, icon: String) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
    }
}

// MARK: - PresetEntityQuery

/// Query для получения списка шаблонов в Shortcuts
struct PresetEntityQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [PresetEntity] {
        return getAllPresets().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        let disabledRaw = defaults?.stringArray(forKey: AppGroupConstants.disabledPresetsKey) ?? []
        let disabledSet = Set(disabledRaw)

        return getAllPresets().filter { !disabledSet.contains($0.id) }
    }

    func defaultResult() async -> PresetEntity? {
        // Дефолтный шаблон - Project Meeting
        return PresetEntity(
            id: "project_meeting",
            displayName: "Project Meeting",
            icon: "folder.fill"
        )
    }

    // MARK: - Private

    private func getAllPresets() -> [PresetEntity] {
        return [
            PresetEntity(
                id: "sales_call",
                displayName: "Sales",
                icon: "phone.arrow.up.right"
            ),
            PresetEntity(
                id: "project_meeting",
                displayName: "Project Meeting",
                icon: "folder.fill"
            ),
            PresetEntity(
                id: "daily_standup",
                displayName: "Daily",
                icon: "sun.max.fill"
            ),
            PresetEntity(
                id: "interview",
                displayName: "Интервью",
                icon: "person.badge.plus"
            ),
            PresetEntity(
                id: "fast_idea",
                displayName: "Быстрая заметка",
                icon: "bolt.fill"
            )
        ]
    }
}

// MARK: - PresetEntity + RecordingPreset Conversion

extension PresetEntity {
    /// Создаёт PresetEntity из RecordingPreset
    /// Используется только в Main App target
    init(from preset: RecordingPreset) {
        self.id = preset.rawValue
        self.displayName = preset.displayName
        self.icon = preset.icon
    }

    /// Конвертирует обратно в RecordingPreset
    /// Возвращает nil если preset не найден
    var asRecordingPreset: RecordingPreset? {
        RecordingPreset(rawValue: id)
    }
}
