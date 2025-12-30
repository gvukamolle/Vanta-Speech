import ActivityKit
import Foundation

/// Модель данных для Live Activity записи
/// Этот файл должен быть добавлен в оба targets: Vanta Speech и VantaSpeechWidgets
struct RecordingActivityAttributes: ActivityAttributes {

    // MARK: - Static Properties (неизменяемые после старта)

    /// ID записи (для последующей идентификации)
    var recordingId: UUID

    /// Название шаблона записи
    var presetName: String

    /// Иконка шаблона (SF Symbol)
    var presetIcon: String

    /// Время начала записи
    var startTime: Date

    // MARK: - Content State (динамические данные)

    struct ContentState: Codable, Hashable {
        /// Текущий статус
        var status: RecordingActivityStatus

        /// Дата для автономного таймера (nil при паузе/остановке)
        /// Используется с Text(date, style: .timer) для обновления без main app
        var timerReferenceDate: Date?

        /// Длительность записи (для статического отображения при паузе)
        var duration: TimeInterval

        /// Уровень аудио (0.0 - 1.0)
        var audioLevel: Float

        /// Прогресс транскрипции (0.0 - 1.0, nil если не транскрибируется)
        var transcriptionProgress: Double?

        /// URL аудиофайла (после остановки)
        var audioFileURL: String?
    }
}

// MARK: - Recording Activity Status

/// Статусы Live Activity
enum RecordingActivityStatus: String, Codable, Hashable {
    case recording      // Идёт запись
    case paused         // Пауза
    case stopped        // Запись остановлена, ожидание действия
    case transcribing   // Транскрипция в процессе
    case completed      // Всё готово

    var displayName: String {
        switch self {
        case .recording: return "Запись"
        case .paused: return "Пауза"
        case .stopped: return "Остановлено"
        case .transcribing: return "Транскрипция..."
        case .completed: return "Готово"
        }
    }

    var systemImage: String {
        switch self {
        case .recording: return "waveform"
        case .paused: return "pause.fill"
        case .stopped: return "stop.fill"
        case .transcribing: return "sparkles"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

// MARK: - App Group Constants

enum AppGroupConstants {
    static let suiteName = "group.ru.poscredit.Vanta-Speech"
    static let recordingActionKey = "recording_action"
    static let disabledPresetsKey = "disabled_presets"
    static let presetOrderKey = "preset_order"
}

// MARK: - Notification Names

extension Notification.Name {
    static let startRecordingFromShortcut = Notification.Name("startRecordingFromShortcut")
    static let pauseRecordingFromLiveActivity = Notification.Name("pauseRecordingFromLiveActivity")
    static let resumeRecordingFromLiveActivity = Notification.Name("resumeRecordingFromLiveActivity")
    static let stopRecordingFromLiveActivity = Notification.Name("stopRecordingFromLiveActivity")
    static let startTranscriptionFromLiveActivity = Notification.Name("startTranscriptionFromLiveActivity")
    static let openRecordingFromLiveActivity = Notification.Name("openRecordingFromLiveActivity")
    static let dismissActivityFromLiveActivity = Notification.Name("dismissActivityFromLiveActivity")
    static let hideActivityFromLiveActivity = Notification.Name("hideActivityFromLiveActivity")
}
