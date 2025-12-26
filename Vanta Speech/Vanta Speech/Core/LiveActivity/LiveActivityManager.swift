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

    // MARK: - Private Properties

    private let appGroupDefaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
    private var actionObserver: Timer?

    // MARK: - Computed Properties

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Init

    private init() {
        restoreActivityIfNeeded()
        setupActionObserver()
    }

    deinit {
        actionObserver?.invalidate()
    }

    // MARK: - Public API

    /// Запуск Live Activity при начале записи
    func startActivity(
        recordingId: UUID,
        preset: RecordingPreset
    ) throws {
        print("[LiveActivityManager] Attempting to start activity...")
        print("[LiveActivityManager] areActivitiesEnabled: \(areActivitiesEnabled)")

        guard areActivitiesEnabled else {
            print("[LiveActivityManager] ERROR: Live Activities are NOT enabled on this device")
            throw LiveActivityError.notEnabled
        }

        // Завершаем предыдущую активность
        if currentActivity != nil {
            print("[LiveActivityManager] Ending previous activity first...")
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
            duration: 0,
            audioLevel: 0,
            transcriptionProgress: nil,
            audioFileURL: nil
        )

        let content = ActivityContent(
            state: initialState,
            staleDate: nil
        )

        print("[LiveActivityManager] Requesting activity with preset: \(preset.displayName)")

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            isActivityRunning = true
            print("[LiveActivityManager] SUCCESS! Activity started: \(currentActivity?.id ?? "unknown")")
        } catch {
            print("[LiveActivityManager] FAILED to start activity: \(error)")
            print("[LiveActivityManager] Error details: \(error.localizedDescription)")
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

        await updateState(
            status: .recording,
            duration: duration,
            audioLevel: audioLevel
        )
    }

    /// Переключение на паузу
    func updatePaused(duration: TimeInterval) async {
        await updateState(
            status: .paused,
            duration: duration,
            audioLevel: 0
        )
    }

    /// Переключение на состояние "остановлено" (показать кнопку саммари)
    func updateStopped(duration: TimeInterval, audioFileURL: String) async {
        await updateState(
            status: .stopped,
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
        print("[LiveActivityManager] Activity ended with completion")
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
        print("[LiveActivityManager] Activity ended immediately")
    }

    // MARK: - Private Methods

    private func updateState(
        status: RecordingActivityStatus,
        duration: TimeInterval,
        audioLevel: Float,
        transcriptionProgress: Double? = nil,
        audioFileURL: String? = nil
    ) async {
        guard let activity = currentActivity else { return }

        let newState = RecordingActivityAttributes.ContentState(
            status: status,
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
            print("[LiveActivityManager] Restored activity: \(existing.id)")
        }
    }

    /// Polling для действий из Live Activity кнопок (когда приложение в background)
    private func setupActionObserver() {
        actionObserver = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForActions()
            }
        }
    }

    private func checkForActions() {
        guard let action = appGroupDefaults?.string(forKey: AppGroupConstants.recordingActionKey) else { return }

        print("[LiveActivityManager] Received action from Live Activity: \(action)")

        // Очищаем action
        appGroupDefaults?.removeObject(forKey: AppGroupConstants.recordingActionKey)
        appGroupDefaults?.synchronize()

        // Публикуем соответствующий notification
        switch action {
        case "pause":
            NotificationCenter.default.post(name: .pauseRecordingFromLiveActivity, object: nil)
        case "resume":
            NotificationCenter.default.post(name: .resumeRecordingFromLiveActivity, object: nil)
        case "stop":
            NotificationCenter.default.post(name: .stopRecordingFromLiveActivity, object: nil)
        case "transcribe":
            print("[LiveActivityManager] Posting startTranscriptionFromLiveActivity notification")
            NotificationCenter.default.post(name: .startTranscriptionFromLiveActivity, object: nil)
        case "dismiss":
            NotificationCenter.default.post(name: .dismissActivityFromLiveActivity, object: nil)
        case "hide":
            NotificationCenter.default.post(name: .hideActivityFromLiveActivity, object: nil)
        default:
            print("[LiveActivityManager] Unknown action: \(action)")
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
