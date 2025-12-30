import ActivityKit
import Combine
import Foundation

/// Менеджер для управления Live Activity записи
@MainActor
final class LiveActivityManager: ObservableObject {

    static let shared = LiveActivityManager()

    // MARK: - Published Properties

    @Published private(set) var currentActivity: Activity<RecordingActivityAttributes>?
    @Published private(set) var isActivityRunning = false

    // MARK: - Computed Properties

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Init

    private init() {
        restoreActivityIfNeeded()
    }

    // MARK: - Public API

    /// Запуск Live Activity при начале записи
    func startActivity(
        recordingId: UUID,
        preset: RecordingPreset
    ) throws {
        debugLog("Attempting to start activity...", module: "LiveActivityManager")
        debugLog("areActivitiesEnabled: \(areActivitiesEnabled)", module: "LiveActivityManager")

        guard areActivitiesEnabled else {
            debugLog("ERROR: Live Activities are NOT enabled on this device", module: "LiveActivityManager", level: .error)
            throw LiveActivityError.notEnabled
        }

        // Завершаем предыдущую активность
        if currentActivity != nil {
            debugLog("Ending previous activity first...", module: "LiveActivityManager")
            Task {
                await endActivityImmediately()
            }
        }

        let attributes = RecordingActivityAttributes(
            recordingId: recordingId,
            presetName: preset.displayName,
            presetIcon: preset.icon,
            startTime: Date()
        )

        let initialState = RecordingActivityAttributes.ContentState(
            status: .recording,
            timerReferenceDate: Date(),  // Автономный таймер начинается с текущего момента
            duration: 0,
            audioLevel: 0,
            transcriptionProgress: nil,
            audioFileURL: nil
        )

        let content = ActivityContent(
            state: initialState,
            staleDate: nil
        )

        debugLog("Requesting activity with preset: \(preset.displayName)", module: "LiveActivityManager")

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            isActivityRunning = true
            debugLog("SUCCESS! Activity started: \(currentActivity?.id ?? "unknown")", module: "LiveActivityManager")
        } catch {
            debugLog("FAILED to start activity: \(error)", module: "LiveActivityManager", level: .error)
            debugLog("Error details: \(error.localizedDescription)", module: "LiveActivityManager", level: .error)
            debugCaptureError(error, context: "Starting Live Activity")
            throw error
        }
    }

    /// Обновление состояния при записи
    func updateRecording(duration: TimeInterval, audioLevel: Float) async {
        // Не обновляем если уже в другом состоянии (stopped, transcribing, completed)
        guard let activity = currentActivity,
              activity.content.state.status == .recording || activity.content.state.status == .paused else {
            return
        }

        // Рассчитываем timerReferenceDate так, чтобы автономный таймер показывал правильное время
        let timerReferenceDate = Date().addingTimeInterval(-duration)

        await updateState(
            status: .recording,
            timerReferenceDate: timerReferenceDate,
            duration: duration,
            audioLevel: audioLevel
        )
    }

    /// Переключение на паузу
    func updatePaused(duration: TimeInterval) async {
        await updateState(
            status: .paused,
            timerReferenceDate: nil,  // Останавливаем автономный таймер
            duration: duration,
            audioLevel: 0
        )
    }

    /// Переключение на состояние "остановлено" (показать кнопку саммари)
    func updateStopped(duration: TimeInterval, audioFileURL: String) async {
        await updateState(
            status: .stopped,
            timerReferenceDate: nil,  // Таймер остановлен
            duration: duration,
            audioLevel: 0,
            audioFileURL: audioFileURL
        )
    }

    /// Переключение на транскрипцию
    func updateTranscribing(progress: Double) async {
        guard let activity = currentActivity else { return }

        let newState = RecordingActivityAttributes.ContentState(
            status: .transcribing,
            timerReferenceDate: nil,  // Таймер остановлен
            duration: activity.content.state.duration,
            audioLevel: 0,
            transcriptionProgress: progress,
            audioFileURL: activity.content.state.audioFileURL
        )

        await activity.update(ActivityContent(state: newState, staleDate: nil))
    }

    /// Завершение с показом результата
    func endWithCompletion(recordingId: UUID) async {
        guard let activity = currentActivity else { return }

        let finalState = RecordingActivityAttributes.ContentState(
            status: .completed,
            timerReferenceDate: nil,  // Таймер остановлен
            duration: activity.content.state.duration,
            audioLevel: 0,
            transcriptionProgress: 1.0,
            audioFileURL: activity.content.state.audioFileURL
        )

        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(10))
        )

        currentActivity = nil
        isActivityRunning = false
        debugLog("Activity ended with completion", module: "LiveActivityManager")
    }

    /// Немедленное завершение
    func endActivityImmediately() async {
        guard let activity = currentActivity else { return }

        await activity.end(
            activity.content,
            dismissalPolicy: .immediate
        )

        currentActivity = nil
        isActivityRunning = false
        debugLog("Activity ended immediately", module: "LiveActivityManager")
    }

    // MARK: - Private Methods

    private func updateState(
        status: RecordingActivityStatus,
        timerReferenceDate: Date?,
        duration: TimeInterval,
        audioLevel: Float,
        transcriptionProgress: Double? = nil,
        audioFileURL: String? = nil
    ) async {
        guard let activity = currentActivity else { return }

        let newState = RecordingActivityAttributes.ContentState(
            status: status,
            timerReferenceDate: timerReferenceDate,
            duration: duration,
            audioLevel: audioLevel,
            transcriptionProgress: transcriptionProgress,
            audioFileURL: audioFileURL ?? activity.content.state.audioFileURL
        )

        await activity.update(ActivityContent(state: newState, staleDate: nil))
    }

    private func restoreActivityIfNeeded() {
        let activities = Activity<RecordingActivityAttributes>.activities
        if let existing = activities.first {
            currentActivity = existing
            isActivityRunning = true
            debugLog("Restored activity: \(existing.id)", module: "LiveActivityManager")
        }
    }
}

// MARK: - Errors

enum LiveActivityError: LocalizedError {
    case notEnabled
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "Live Activities отключены на этом устройстве"
        case .alreadyRunning:
            return "Live Activity уже запущена"
        }
    }
}
