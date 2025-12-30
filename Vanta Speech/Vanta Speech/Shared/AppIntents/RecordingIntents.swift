import ActivityKit
import AppIntents
import AudioToolbox
import Foundation
import UIKit

// MARK: - Live Activity Button Intents
// Optimistic UI updates: обновляем Activity сразу, не дожидаясь ответа от main app
// Haptic: используем AudioServicesPlaySystemSound как fallback для widget extension

// MARK: - Haptic Helper

private func playHaptic(style: HapticStyle) {
    // Логируем для диагностики
    let isMainApp = Bundle.main.bundleIdentifier?.contains("VantaSpeechWidgets") == false
    print("[Intent] playHaptic called, isMainApp: \(isMainApp), style: \(style)")

    // Пробуем UIKit haptic (работает только в main app)
    if isMainApp {
        switch style {
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }

    // AudioServices как fallback (работает везде)
    // 1519 = Peek, 1520 = Pop, 1521 = Cancelled, 1102 = короткий тап
    switch style {
    case .light:
        AudioServicesPlaySystemSound(1519)
    case .medium:
        AudioServicesPlaySystemSound(1520)
    case .warning:
        AudioServicesPlaySystemSound(1521)
    case .success:
        AudioServicesPlaySystemSound(1520)
    }
}

private enum HapticStyle {
    case light, medium, warning, success
}

// MARK: - Activity Helper

private func getCurrentActivity() -> Activity<RecordingActivityAttributes>? {
    let activities = Activity<RecordingActivityAttributes>.activities
    print("[Intent] Found \(activities.count) activities")
    if let activity = activities.first {
        print("[Intent] Activity state: \(activity.content.state.status), duration: \(activity.content.state.duration)")
        return activity
    }
    print("[Intent] No activity found!")
    return nil
}

/// Intent для паузы записи (из Live Activity)
struct PauseRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Пауза"
    static var description = IntentDescription("Ставит запись на паузу")

    @MainActor
    func perform() async throws -> some IntentResult {
        print("[PauseRecordingIntent] perform() called")

        // Haptic feedback
        playHaptic(style: .medium)

        // Optimistic UI update - мгновенное обновление виджета
        if let activity = getCurrentActivity() {
            let currentState = activity.content.state
            let newState = RecordingActivityAttributes.ContentState(
                status: .paused,
                timerReferenceDate: nil,
                duration: currentState.duration,
                audioLevel: 0,
                transcriptionProgress: nil,
                audioFileURL: currentState.audioFileURL
            )
            await activity.update(ActivityContent(state: newState, staleDate: nil))
            print("[PauseRecordingIntent] Optimistic update sent")
        }

        // Darwin notification для фактической обработки в main app
        DarwinNotificationCenter.shared.postPauseRecording()
        print("[PauseRecordingIntent] Darwin notification sent")

        return .result()
    }
}

/// Intent для возобновления записи (из Live Activity)
struct ResumeRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Продолжить"
    static var description = IntentDescription("Продолжает запись после паузы")

    @MainActor
    func perform() async throws -> some IntentResult {
        print("[ResumeRecordingIntent] perform() called")

        // Haptic feedback
        playHaptic(style: .medium)

        // Optimistic UI update - мгновенное обновление виджета
        if let activity = getCurrentActivity() {
            let currentState = activity.content.state
            let timerReferenceDate = Date().addingTimeInterval(-currentState.duration)
            let newState = RecordingActivityAttributes.ContentState(
                status: .recording,
                timerReferenceDate: timerReferenceDate,
                duration: currentState.duration,
                audioLevel: 0,
                transcriptionProgress: nil,
                audioFileURL: currentState.audioFileURL
            )
            await activity.update(ActivityContent(state: newState, staleDate: nil))
            print("[ResumeRecordingIntent] Optimistic update sent")
        }

        // Darwin notification для фактической обработки в main app
        DarwinNotificationCenter.shared.postResumeRecording()
        print("[ResumeRecordingIntent] Darwin notification sent")

        return .result()
    }
}

/// Intent для остановки записи (из Live Activity)
struct StopRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Стоп"
    static var description = IntentDescription("Останавливает запись")

    @MainActor
    func perform() async throws -> some IntentResult {
        print("[StopRecordingIntent] perform() called")

        // Haptic feedback - более сильный для важного действия
        playHaptic(style: .warning)

        // Optimistic UI update - мгновенное обновление виджета
        if let activity = getCurrentActivity() {
            let currentState = activity.content.state
            let newState = RecordingActivityAttributes.ContentState(
                status: .stopped,
                timerReferenceDate: nil,
                duration: currentState.duration,
                audioLevel: 0,
                transcriptionProgress: nil,
                audioFileURL: currentState.audioFileURL
            )
            await activity.update(ActivityContent(state: newState, staleDate: nil))
            print("[StopRecordingIntent] Optimistic update sent")
        }

        // Darwin notification для фактической обработки в main app
        DarwinNotificationCenter.shared.postStopRecording()
        print("[StopRecordingIntent] Darwin notification sent")

        return .result()
    }
}

/// Intent для начала транскрипции (из Live Activity после остановки)
struct StartTranscriptionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Сделать саммари"
    static var description = IntentDescription("Запускает транскрипцию и создание саммари")

    @MainActor
    func perform() async throws -> some IntentResult {
        print("[StartTranscriptionIntent] perform() called")

        // Haptic feedback
        playHaptic(style: .medium)

        // Optimistic UI update - мгновенное обновление виджета
        if let activity = getCurrentActivity() {
            let currentState = activity.content.state
            let newState = RecordingActivityAttributes.ContentState(
                status: .transcribing,
                timerReferenceDate: nil,
                duration: currentState.duration,
                audioLevel: 0,
                transcriptionProgress: 0,
                audioFileURL: currentState.audioFileURL
            )
            await activity.update(ActivityContent(state: newState, staleDate: nil))
            print("[StartTranscriptionIntent] Optimistic update sent")
        }

        // Darwin notification для фактической обработки в main app
        DarwinNotificationCenter.shared.postStartTranscription()
        print("[StartTranscriptionIntent] Darwin notification sent")

        return .result()
    }
}

/// Intent для открытия записи (из Live Activity после завершения)
struct OpenRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть запись"
    static var description = IntentDescription("Открывает приложение с записью")

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Recording ID")
    var recordingId: String?

    init() {}

    init(recordingId: String) {
        self.recordingId = recordingId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = recordingId {
            NotificationCenter.default.post(
                name: .openRecordingFromLiveActivity,
                object: nil,
                userInfo: ["recordingId": id]
            )
        }
        return .result()
    }
}

/// Intent для закрытия Live Activity без транскрипции ("Отлично")
struct DismissActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Отлично"
    static var description = IntentDescription("Закрывает Live Activity без транскрипции")

    @MainActor
    func perform() async throws -> some IntentResult {
        print("[DismissActivityIntent] perform() called")

        // Haptic feedback - успешное завершение
        playHaptic(style: .success)

        // Optimistic UI update - мгновенно закрываем Activity
        if let activity = getCurrentActivity() {
            let currentState = activity.content.state
            let finalState = RecordingActivityAttributes.ContentState(
                status: .completed,
                timerReferenceDate: nil,
                duration: currentState.duration,
                audioLevel: 0,
                transcriptionProgress: nil,
                audioFileURL: currentState.audioFileURL
            )
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            print("[DismissActivityIntent] Activity ended")
        }

        // Darwin notification для cleanup в main app
        DarwinNotificationCenter.shared.postDismissActivity()
        print("[DismissActivityIntent] Darwin notification sent")

        return .result()
    }
}

/// Intent для скрытия Live Activity во время транскрипции
struct HideActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Скрыть"
    static var description = IntentDescription("Скрывает Live Activity")

    @MainActor
    func perform() async throws -> some IntentResult {
        print("[HideActivityIntent] perform() called")

        // Haptic feedback - лёгкий
        playHaptic(style: .light)

        // Optimistic UI update - мгновенно скрываем Activity
        if let activity = getCurrentActivity() {
            await activity.end(
                activity.content,
                dismissalPolicy: .immediate
            )
            print("[HideActivityIntent] Activity ended")
        }

        // Darwin notification для cleanup в main app
        DarwinNotificationCenter.shared.postHideActivity()
        print("[HideActivityIntent] Darwin notification sent")

        return .result()
    }
}
