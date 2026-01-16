# iOS: App Intents (Shortcuts) & Dynamic Island (Live Activities)

> Гайд по интеграции с приложением "Команды" и Dynamic Island для iOS-приложений.  
> Актуально для iOS 16.1+ / Xcode 14.1+ / Swift 5.7+

---

## Содержание

1. [Требования и Apple Developer Account](#требования-и-apple-developer-account)
2. [App Intents (Shortcuts)](#app-intents-shortcuts)
   - [Базовая структура](#базовая-структура)
   - [App Shortcuts Provider](#app-shortcuts-provider)
   - [Параметры и Entity](#параметры-и-entity)
   - [Foreground vs Background](#foreground-vs-background)
3. [Live Activities & Dynamic Island](#live-activities--dynamic-island)
   - [Подготовка проекта](#подготовка-проекта)
   - [ActivityAttributes модель](#activityattributes-модель)
   - [Widget Configuration](#widget-configuration)
   - [Управление Activity](#управление-activity)
   - [Push Notifications для Live Activities](#push-notifications-для-live-activities)
4. [Haptic Feedback и Dynamic Island](#haptic-feedback-и-dynamic-island)
   - [Системный контроль хаптиков](#системный-контроль-хаптиков)
   - [Ограничения Widget Extension](#ограничения-widget-extension)
   - [Как добавить Haptic через App Intents](#как-добавить-haptic-feedback-через-app-intents-ios-17)
   - [Типы Haptic Feedback](#типы-haptic-feedback)
   - [SwiftUI sensoryFeedback](#swiftui-sensoryfeedback-ios-17)
5. [Референсные репозитории](#референсные-репозитории)
6. [Чеклист интеграции](#чеклист-интеграции)

---

## Требования и Apple Developer Account

### Минимальные требования

| Компонент | App Intents | Live Activities | Dynamic Island |
|-----------|-------------|-----------------|----------------|
| iOS | 16.0+ | 16.1+ | 16.1+ |
| Xcode | 14.0+ | 14.1+ | 14.1+ |
| Swift | 5.7+ | 5.7+ | 5.7+ |
| Устройство | Любой iPhone | Любой iPhone | iPhone 14 Pro+ |

### Что можно без платного аккаунта ($99/год)

| Функциональность | Бесплатный Apple ID | Платный аккаунт |
|------------------|---------------------|-----------------|
| Разработка + симулятор | ✅ | ✅ |
| Тестирование на устройстве | ✅ (7 дней, до 3 устройств) | ✅ |
| App Intents / Shortcuts | ✅ | ✅ |
| Live Activities (локально) | ✅ | ✅ |
| Dynamic Island (локально) | ✅ | ✅ |
| Push Notifications | ❌ | ✅ |
| Push-to-Start Live Activities | ❌ | ✅ |
| Remote Update Live Activities | ❌ | ✅ |
| TestFlight | ❌ | ✅ |
| App Store публикация | ❌ | ✅ |

**Вывод:** Для локальной разработки и тестирования хватит бесплатного аккаунта. Для Push-обновлений Live Activities и публикации — нужен платный.

---

## App Intents (Shortcuts)

App Intents — современный Swift-native фреймворк (iOS 16+), заменивший SiriKit/INIntent. Позволяет интегрировать функции приложения с Shortcuts.app, Siri, Spotlight, Widgets.

### Базовая структура

```swift
import AppIntents

/// Простой Intent без параметров
struct StartRecordingIntent: AppIntent {
    
    // MARK: - Metadata
    
    /// Название, отображаемое в Shortcuts.app
    static var title: LocalizedStringResource = "Start Recording"
    
    /// Описание действия
    static var description = IntentDescription("Starts a new recording session in Vanta Speech")
    
    /// Открывать ли приложение при выполнении
    /// - true: Intent выполняется в foreground, приложение открывается
    /// - false: Intent выполняется в background
    static var openAppWhenRun: Bool = true
    
    // MARK: - Perform
    
    /// Основная логика выполнения
    @MainActor
    func perform() async throws -> some IntentResult {
        // Твоя логика запуска записи
        RecordingManager.shared.startRecording()
        
        return .result()
    }
}
```

### App Shortcuts Provider

Автоматически добавляет Shortcuts в приложение "Команды" без действий пользователя.

```swift
import AppIntents

struct VantaSpeechShortcuts: AppShortcutsProvider {
    
    /// Shortcuts, автоматически добавляемые в Shortcuts.app
    static var appShortcuts: [AppShortcut] {
        
        // Shortcut для начала записи
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Begin recording with \(.applicationName)",
                "Record meeting in \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "record.circle"
        )
        
        // Shortcut для остановки записи
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop recording in \(.applicationName)",
                "End recording in \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.circle"
        )
    }
}
```

**Важно:** После добавления `AppShortcutsProvider` вызови в `@main` App:

```swift
@main
struct VantaSpeechApp: App {
    
    init() {
        // Обновляет shortcuts при запуске
        VantaSpeechShortcuts.updateAppShortcutParameters()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Параметры и Entity

Для Intent с параметрами используй `@Parameter` и `AppEntity`.

```swift
import AppIntents

/// Intent с параметрами
struct TranscribeFileIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Transcribe Audio File"
    static var description = IntentDescription("Transcribes selected audio file")
    
    // MARK: - Parameters
    
    /// Параметр с выбором языка
    @Parameter(title: "Language", default: .english)
    var language: TranscriptionLanguage
    
    /// Опциональный параметр
    @Parameter(title: "Include Timestamps")
    var includeTimestamps: Bool?
    
    // MARK: - Parameter Summary
    
    /// Как отображается в Shortcuts.app
    static var parameterSummary: some ParameterSummary {
        Summary("Transcribe in \(\.$language)") {
            \.$includeTimestamps
        }
    }
    
    // MARK: - Perform
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let timestamps = includeTimestamps ?? false
        let result = await TranscriptionService.transcribe(language: language, timestamps: timestamps)
        
        return .result(value: result)
    }
}

/// Enum для параметра
enum TranscriptionLanguage: String, AppEnum {
    case english = "en"
    case russian = "ru"
    case spanish = "es"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Language")
    }
    
    static var caseDisplayRepresentations: [TranscriptionLanguage: DisplayRepresentation] {
        [
            .english: DisplayRepresentation(title: "English"),
            .russian: DisplayRepresentation(title: "Russian"),
            .spanish: DisplayRepresentation(title: "Spanish")
        ]
    }
}
```

### Foreground vs Background

```swift
/// Background Intent — выполняется без открытия приложения
struct QuickTranscribeIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Transcribe"
    static var openAppWhenRun: Bool = false  // ← Background
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await TranscriptionService.transcribeLast()
        
        // Возвращаем диалог, который покажет Siri
        return .result(dialog: "Transcription complete: \(result)")
    }
}

/// Foreground Intent — открывает приложение
struct OpenRecordingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Recordings"
    static var openAppWhenRun: Bool = true  // ← Foreground
    
    func perform() async throws -> some IntentResult {
        // Навигация внутри приложения через Environment или NotificationCenter
        NotificationCenter.default.post(name: .navigateToRecordings, object: nil)
        
        return .result()
    }
}
```

---

## Live Activities & Dynamic Island

Live Activities позволяют отображать актуальную информацию на Lock Screen и в Dynamic Island.

### Подготовка проекта

#### 1. Добавить Widget Extension

`File → New → Target → Widget Extension`

- Имя: `VantaSpeechWidgets`
- Убрать галочку "Include Configuration App Intent" (если не нужны настраиваемые виджеты)
- Убрать галочку "Include Live Activity" — добавим вручную для контроля

#### 2. Info.plist основного приложения

```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

#### 3. Shared Framework (опционально, но рекомендуется)

Для шаринга кода между App и Widget Extension создай Shared Framework или используй App Groups.

**App Groups:**
1. `Signing & Capabilities → + Capability → App Groups`
2. Добавь группу: `group.com.yourcompany.vantaspeech`
3. Добавь ту же группу в Widget Extension target

### ActivityAttributes модель

Создай файл в Shared коде (доступном и App, и Widget Extension).

```swift
import ActivityKit
import Foundation

/// Модель данных для Live Activity
struct RecordingActivityAttributes: ActivityAttributes {
    
    // MARK: - Static Properties (неизменяемые после старта)
    
    /// Название сессии записи
    var sessionName: String
    
    /// Время начала записи
    var startTime: Date
    
    // MARK: - Content State (динамические, обновляемые)
    
    public struct ContentState: Codable, Hashable {
        /// Текущая длительность записи
        var duration: TimeInterval
        
        /// Статус записи
        var status: RecordingStatus
        
        /// Текущий уровень громкости (0.0 - 1.0)
        var audioLevel: Float
        
        /// Статус транскрипции
        var transcriptionProgress: Double?
    }
}

/// Статусы записи
enum RecordingStatus: String, Codable {
    case recording
    case paused
    case processing
    case completed
    
    var displayName: String {
        switch self {
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .processing: return "Processing"
        case .completed: return "Completed"
        }
    }
    
    var systemImage: String {
        switch self {
        case .recording: return "waveform"
        case .paused: return "pause.fill"
        case .processing: return "gear"
        case .completed: return "checkmark.circle.fill"
        }
    }
}
```

### Widget Configuration

Файл в Widget Extension target.

```swift
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VantaSpeechWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Обычные виджеты (если есть)
        // VantaSpeechWidget()
        
        // Live Activity Widget
        RecordingLiveActivityWidget()
    }
}

struct RecordingLiveActivityWidget: Widget {
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // MARK: - Lock Screen / Banner View
            LockScreenView(context: context)
            
        } dynamicIsland: { context in
            // MARK: - Dynamic Island
            DynamicIsland {
                // Expanded View (при долгом нажатии)
                expandedView(context: context)
            } compactLeading: {
                // Левая часть compact view
                compactLeadingView(context: context)
            } compactTrailing: {
                // Правая часть compact view
                compactTrailingView(context: context)
            } minimal: {
                // Minimal view (когда есть другие активности)
                minimalView(context: context)
            }
        }
    }
    
    // MARK: - Dynamic Island Expanded Regions
    
    @DynamicIslandExpandedContentBuilder
    private func expandedView(context: ActivityViewContext<RecordingActivityAttributes>) -> DynamicIslandExpandedContent<some View> {
        
        DynamicIslandExpandedRegion(.leading) {
            HStack {
                Image(systemName: context.state.status.systemImage)
                    .foregroundColor(context.state.status == .recording ? .red : .secondary)
                VStack(alignment: .leading) {
                    Text(context.state.status.displayName)
                        .font(.caption)
                        .bold()
                    Text(context.attributes.sessionName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        
        DynamicIslandExpandedRegion(.trailing) {
            VStack(alignment: .trailing) {
                Text(formatDuration(context.state.duration))
                    .font(.title2)
                    .bold()
                    .monospacedDigit()
                Text("Duration")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        
        DynamicIslandExpandedRegion(.bottom) {
            // Audio Level Indicator
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: index, level: context.state.audioLevel))
                        .frame(width: 8, height: 16)
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Compact Views
    
    @ViewBuilder
    private func compactLeadingView(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        Image(systemName: context.state.status.systemImage)
            .foregroundColor(context.state.status == .recording ? .red : .white)
    }
    
    @ViewBuilder
    private func compactTrailingView(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        Text(formatDuration(context.state.duration))
            .font(.caption)
            .bold()
            .monospacedDigit()
    }
    
    @ViewBuilder
    private func minimalView(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        Image(systemName: "waveform")
            .foregroundColor(.red)
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func barColor(for index: Int, level: Float) -> Color {
        let threshold = Float(index) / 20.0
        return level > threshold ? .red : .gray.opacity(0.3)
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>
    
    var body: some View {
        HStack {
            // Left: Status Icon
            Image(systemName: context.state.status.systemImage)
                .font(.title)
                .foregroundColor(context.state.status == .recording ? .red : .secondary)
                .frame(width: 50)
            
            // Center: Session Info
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.sessionName)
                    .font(.headline)
                Text(context.state.status.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Right: Duration
            VStack(alignment: .trailing) {
                Text(formatDuration(context.state.duration))
                    .font(.title2)
                    .bold()
                    .monospacedDigit()
                
                if let progress = context.state.transcriptionProgress {
                    ProgressView(value: progress)
                        .frame(width: 60)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
```

### Управление Activity

Менеджер в основном приложении.

```swift
import ActivityKit
import Foundation

@MainActor
class LiveActivityManager: ObservableObject {
    
    static let shared = LiveActivityManager()
    
    /// Текущая активная Live Activity
    @Published private(set) var currentActivity: Activity<RecordingActivityAttributes>?
    
    /// Проверка поддержки Live Activities
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    // MARK: - Start Activity
    
    /// Запуск Live Activity
    func startActivity(sessionName: String) throws {
        guard areActivitiesEnabled else {
            throw LiveActivityError.notEnabled
        }
        
        // Завершаем предыдущую активность, если есть
        Task {
            await endActivity()
        }
        
        // Создаём атрибуты
        let attributes = RecordingActivityAttributes(
            sessionName: sessionName,
            startTime: Date()
        )
        
        // Начальное состояние
        let initialState = RecordingActivityAttributes.ContentState(
            duration: 0,
            status: .recording,
            audioLevel: 0
        )
        
        // Создаём контент
        let content = ActivityContent(
            state: initialState,
            staleDate: nil  // nil = никогда не становится stale
        )
        
        // Запускаем Activity
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil  // Для Push-обновлений: .token
            )
            print("✅ Live Activity started: \(currentActivity?.id ?? "unknown")")
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
            throw error
        }
    }
    
    // MARK: - Update Activity
    
    /// Обновление состояния Live Activity
    func updateActivity(
        duration: TimeInterval,
        status: RecordingStatus,
        audioLevel: Float,
        transcriptionProgress: Double? = nil
    ) async {
        guard let activity = currentActivity else {
            print("⚠️ No active Live Activity to update")
            return
        }
        
        let newState = RecordingActivityAttributes.ContentState(
            duration: duration,
            status: status,
            audioLevel: audioLevel,
            transcriptionProgress: transcriptionProgress
        )
        
        let content = ActivityContent(
            state: newState,
            staleDate: nil
        )
        
        await activity.update(content)
    }
    
    // MARK: - End Activity
    
    /// Завершение Live Activity
    func endActivity(
        finalStatus: RecordingStatus = .completed,
        finalDuration: TimeInterval? = nil
    ) async {
        guard let activity = currentActivity else { return }
        
        // Финальное состояние (опционально показать перед закрытием)
        let finalState = RecordingActivityAttributes.ContentState(
            duration: finalDuration ?? 0,
            status: finalStatus,
            audioLevel: 0,
            transcriptionProgress: finalStatus == .completed ? 1.0 : nil
        )
        
        let finalContent = ActivityContent(
            state: finalState,
            staleDate: nil
        )
        
        // Варианты закрытия:
        // .immediate — закрыть сразу
        // .after(Date) — закрыть после указанной даты
        // .default — система решает сама
        await activity.end(
            finalContent,
            dismissalPolicy: .after(Date().addingTimeInterval(5))  // Показать финал 5 сек
        )
        
        currentActivity = nil
        print("✅ Live Activity ended")
    }
    
    // MARK: - Observe Activities
    
    /// Восстановление активности после перезапуска приложения
    func restoreActivity() {
        // Получаем все активные Live Activities этого типа
        let activities = Activity<RecordingActivityAttributes>.activities
        
        if let existingActivity = activities.first {
            currentActivity = existingActivity
            print("✅ Restored Live Activity: \(existingActivity.id)")
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
            return "Live Activities are not enabled on this device"
        case .alreadyRunning:
            return "A Live Activity is already running"
        }
    }
}
```

### Использование в Recording Manager

```swift
class RecordingManager: ObservableObject {
    
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    
    private var timer: Timer?
    
    func startRecording(sessionName: String) {
        isRecording = true
        duration = 0
        
        // Запускаем Live Activity
        Task { @MainActor in
            try? LiveActivityManager.shared.startActivity(sessionName: sessionName)
        }
        
        // Таймер для обновления
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.duration += 1
            
            Task { @MainActor in
                await LiveActivityManager.shared.updateActivity(
                    duration: self.duration,
                    status: .recording,
                    audioLevel: self.currentAudioLevel
                )
            }
        }
    }
    
    func stopRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil
        
        // Завершаем Live Activity
        Task { @MainActor in
            await LiveActivityManager.shared.endActivity(
                finalStatus: .completed,
                finalDuration: duration
            )
        }
    }
    
    var currentAudioLevel: Float {
        // Получение текущего уровня аудио
        return 0.5  // Placeholder
    }
}
```

### Push Notifications для Live Activities

> ⚠️ Требует платный Apple Developer Account

#### 1. Получение Push Token

```swift
func startActivityWithPush(sessionName: String) async throws {
    let attributes = RecordingActivityAttributes(
        sessionName: sessionName,
        startTime: Date()
    )
    
    let initialState = RecordingActivityAttributes.ContentState(
        duration: 0,
        status: .recording,
        audioLevel: 0
    )
    
    let content = ActivityContent(state: initialState, staleDate: nil)
    
    // Запрос с поддержкой Push
    let activity = try Activity.request(
        attributes: attributes,
        content: content,
        pushType: .token  // ← Включает Push-обновления
    )
    
    // Получаем Push Token
    for await pushToken in activity.pushTokenUpdates {
        let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
        print("📱 Push Token: \(tokenString)")
        
        // Отправляем токен на свой сервер
        await sendTokenToServer(tokenString)
    }
}
```

#### 2. Серверная часть (пример payload)

```json
{
  "aps": {
    "timestamp": 1234567890,
    "event": "update",
    "content-state": {
      "duration": 120,
      "status": "recording",
      "audioLevel": 0.7
    }
  }
}
```

---

## Haptic Feedback и Dynamic Island

### Системный контроль хаптиков

Haptic feedback при взаимодействии с Dynamic Island — **полностью системное поведение**. Разработчики не могут напрямую контролировать хаптики при long press, tap или свайпе.

| Действие пользователя | Haptic | Кто контролирует |
|-----------------------|--------|------------------|
| Long press для раскрытия Expanded view | ✅ Системный | Apple |
| Tap на compact/minimal view | ✅ Системный | Apple |
| Свайп для dismiss | ✅ Системный | Apple |
| Переключение между двумя активностями | ✅ Системный | Apple |

### Ограничения Widget Extension

Live Activities работают внутри Widget Extension, который имеет жёсткие ограничения:

```swift
// ❌ НЕ работает в Widget Extension — игнорируется системой
let generator = UIImpactFeedbackGenerator(style: .medium)
generator.impactOccurred()

// ❌ НЕ работает — нет сетевого доступа
AsyncImage(url: imageURL)

// ❌ sensoryFeedback модификатор — тоже не работает
Text("Hello")
    .sensoryFeedback(.impact, trigger: someValue)
```

**Причина ограничения:** Apple специально блокирует haptics в background-контексте, чтобы пользователь всегда понимал, какое приложение вызвало вибрацию. `UIFeedbackGenerator` требует foreground app state.

### Как добавить Haptic Feedback через App Intents (iOS 17+)

Единственный способ — использовать интерактивные кнопки с App Intents. Intent выполняется в контексте main app, где haptics доступны.

#### 1. Создать Intent с haptic feedback

```swift
import AppIntents
import UIKit

struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Recording"
    
    // false = выполняется в background, не открывая приложение
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult {
        // ✅ Haptic работает — мы в контексте main app
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        // Логика переключения записи
        if RecordingManager.shared.isRecording {
            RecordingManager.shared.pause()
        } else {
            RecordingManager.shared.resume()
        }
        
        return .result()
    }
}
```

#### 2. Использовать Button в Live Activity

```swift
// В Expanded Region Dynamic Island
DynamicIslandExpandedRegion(.bottom) {
    HStack {
        // Кнопка с Intent — при нажатии выполнится perform() с haptic
        Button(intent: ToggleRecordingIntent()) {
            Label(
                context.state.isRecording ? "Pause" : "Resume",
                systemImage: context.state.isRecording ? "pause.fill" : "record.circle"
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(context.state.isRecording ? .orange : .red)
        
        Button(intent: StopRecordingIntent()) {
            Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
    }
}
```

#### 3. Пример Intent с разными типами haptic

```swift
struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult {
        // Success haptic — для завершения важного действия
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        await RecordingManager.shared.stopAndSave()
        
        // Завершаем Live Activity
        await LiveActivityManager.shared.endActivity(
            finalStatus: .completed
        )
        
        return .result()
    }
}

struct ErrorIntent: AppIntent {
    static var title: LocalizedStringResource = "Handle Error"
    static var openAppWhenRun: Bool = true // Открыть app для показа ошибки
    
    @MainActor
    func perform() async throws -> some IntentResult {
        // Error haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        
        return .result()
    }
}
```

### Типы Haptic Feedback

#### UINotificationFeedbackGenerator (для событий)

```swift
let generator = UINotificationFeedbackGenerator()

generator.notificationOccurred(.success)  // Успешное действие
generator.notificationOccurred(.warning)  // Предупреждение
generator.notificationOccurred(.error)    // Ошибка
```

#### UIImpactFeedbackGenerator (для физических взаимодействий)

```swift
// По весу
UIImpactFeedbackGenerator(style: .light).impactOccurred()
UIImpactFeedbackGenerator(style: .medium).impactOccurred()
UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

// По жёсткости (iOS 13+)
UIImpactFeedbackGenerator(style: .soft).impactOccurred()
UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

// С интенсивностью
let generator = UIImpactFeedbackGenerator(style: .medium)
generator.impactOccurred(intensity: 0.7) // 0.0 - 1.0
```

#### UISelectionFeedbackGenerator (для выбора)

```swift
let generator = UISelectionFeedbackGenerator()
generator.selectionChanged() // Лёгкий тик при смене выбора
```

### SwiftUI: sensoryFeedback (iOS 17+)

В main app (не в Widget Extension) можно использовать декларативный подход:

```swift
struct RecordingControlView: View {
    @State private var isRecording = false
    
    var body: some View {
        Button(isRecording ? "Stop" : "Start") {
            isRecording.toggle()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
    }
}

// Разные haptics в зависимости от значения
struct CounterView: View {
    @State private var count = 0
    
    var body: some View {
        Stepper("Count: \(count)", value: $count)
            .sensoryFeedback(trigger: count) { oldValue, newValue in
                newValue > oldValue ? .increase : .decrease
            }
    }
}
```

### Ограничения анимаций в Live Activities

```swift
// ✅ Работает — системные переходы
Text("\(context.state.duration)")
    .contentTransition(.numericText())
    .animation(.spring(duration: 0.2), value: context.state.duration)

// ✅ Работает — базовые transitions
Image(systemName: iconName)
    .transition(.opacity)
    .animation(.easeInOut, value: iconName)
```

**Ограничения:**
- Максимальная длительность анимации: **2 секунды**
- На Always-On Display: анимации **отключены** (используй `isLuminanceReduced`)
- iOS 16: только системные анимации (`.move`, `.slide`, `.opacity`)
- `withAnimation` блоки игнорируются в iOS 16

```swift
// Проверка Always-On Display
struct LiveActivityView: View {
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    
    var body: some View {
        if isLuminanceReduced {
            // Статичный контент для Always-On
            StaticContentView()
        } else {
            // Анимированный контент
            AnimatedContentView()
        }
    }
}
```

### Рекомендации для Vanta Speech

1. **Полагайся на системные haptics** — они уже качественные для UX при long press и tap

2. **Добавь интерактивные кнопки в Expanded view:**
   - Pause/Resume с `.impact(weight: .medium)`
   - Stop с `.success` notification
   
3. **Используй анимации для визуального feedback:**
   - `.contentTransition(.numericText())` для таймера
   - Пульсация для индикатора записи

4. **Не пытайся вызывать haptics из Widget Extension кода** — это не сработает

---

## Референсные репозитории

### App Intents

| Репозиторий | Описание | Ссылка |
|-------------|----------|--------|
| **mralexhay/Booky** | Самый полный demo. 5 actions, Entity queries, Snippets | [GitHub](https://github.com/mralexhay/Booky) |
| **Jc-hammond/AppIntents-Examples** | Современный пример с voice commands, widgets | [GitHub](https://github.com/Jc-hammond/AppIntents-Examples) |
| **prash5t/integrate-siri-ios-apps** | Интеграция Siri + LLM backend | [GitHub](https://github.com/prash5t/integrate-siri-ios-apps) |
| **bobh/AppIntentBasic** | Минимальный demo + YouTube | [GitHub](https://github.com/bobh/AppIntentBasic) |

### Live Activities / Dynamic Island

| Репозиторий | Описание | Ссылка |
|-------------|----------|--------|
| **sparrowcode/live-activity-example** | Чистый пример + туториал | [GitHub](https://github.com/sparrowcode/live-activity-example) |
| **1998code/iOS16-Live-Activities** | Pizza Delivery demo | [GitHub](https://github.com/1998code/iOS16-Live-Activities) |
| **barisozgenn/DynamicIsland** | Food Delivery + Taxi сценарии | [GitHub](https://github.com/barisozgenn/DynamicIsland) |
| **simonberner/ladi-simulator** | Basketball game Live Score | [GitHub](https://github.com/simonberner/ladi-simulator) |
| **tigi44/LiveActivitiesExample** | Минималистичный пример | [GitHub](https://github.com/tigi44/LiveActivitiesExample) |

### Официальная документация Apple

- [App Intents](https://developer.apple.com/documentation/appintents)
- [ActivityKit](https://developer.apple.com/documentation/activitykit)
- [Displaying Live Data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [WWDC22: Dive Into App Intents](https://developer.apple.com/videos/play/wwdc2022/10032/)
- [WWDC23: Design Dynamic Live Activities](https://developer.apple.com/videos/play/wwdc2023/10194/)

---

## Чеклист интеграции

### App Intents

- [ ] Создать Intent структуру с `AppIntent` протоколом
- [ ] Определить `title`, `description`, `openAppWhenRun`
- [ ] Реализовать `perform()` метод
- [ ] Добавить `@Parameter` для входных данных (если нужно)
- [ ] Создать `AppShortcutsProvider` для автоматических shortcuts
- [ ] Вызвать `updateAppShortcutParameters()` в `@main` App
- [ ] Протестировать в Shortcuts.app и через Siri

### Live Activities

- [ ] Добавить Widget Extension target
- [ ] Добавить `NSSupportsLiveActivities = true` в Info.plist
- [ ] Создать `ActivityAttributes` модель
- [ ] Реализовать `ActivityConfiguration` с Lock Screen и Dynamic Island views
- [ ] Создать `LiveActivityManager` для управления
- [ ] Реализовать start/update/end логику
- [ ] Настроить App Groups для шаринга данных (если нужно)
- [ ] Протестировать на реальном устройстве (симулятор ограничен)

### Haptic Feedback в Live Activities (iOS 17+)

- [ ] Создать App Intents для интерактивных действий (Pause, Stop, и т.д.)
- [ ] Добавить `UIFeedbackGenerator` вызовы в `perform()` методы Intents
- [ ] Использовать `Button(intent:)` в Expanded view Dynamic Island
- [ ] Выбрать подходящие типы haptic для каждого действия:
  - `.impact` — для toggle-действий
  - `.success` — для успешного завершения
  - `.error` — для ошибок
- [ ] НЕ пытаться вызывать haptics напрямую из Widget Extension кода
- [ ] Добавить анимации `.contentTransition()` для визуального feedback

### Для Push-обновлений (платный аккаунт)

- [ ] Включить Push Notifications capability
- [ ] Использовать `pushType: .token` при создании Activity
- [ ] Обработать `pushTokenUpdates`
- [ ] Настроить серверную отправку APNs

---

## Troubleshooting

### App Intents не появляются в Shortcuts.app

1. Проверить, что `xcode-select` указывает на правильный Xcode:
   ```bash
   xcode-select -p
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. Удалить приложение с устройства и переустановить

3. Для Release builds: пометить все Intent как `public`:
   ```swift
   public struct MyIntent: AppIntent { ... }
   ```

### Live Activity не обновляется

1. Проверить, что обновление вызывается на `@MainActor`
2. Убедиться, что `Activity.activities` возвращает активную activity
3. Проверить лимиты: максимум ~4 обновления в час от push

### Dynamic Island не отображается

1. Проверить устройство: только iPhone 14 Pro и новее
2. iOS версия: минимум 16.1
3. Проверить, что приложение не в foreground (DI показывается только в background)

### Haptic Feedback не работает

1. **В Widget Extension:** Это ожидаемое поведение — haptics недоступны в widget context
2. **В App Intent:** Убедиться, что `@MainActor` указан перед `perform()`
3. **На симуляторе:** Haptics не работают — только на реальном устройстве
4. **Решение:** Использовать `Button(intent:)` и вызывать haptics внутри Intent

```swift
// ❌ Не работает — Widget Extension context
struct MyLiveActivityView: View {
    var body: some View {
        Button("Tap") {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

// ✅ Работает — Intent выполняется в main app context
struct MyIntent: AppIntent {
    @MainActor
    func perform() async throws -> some IntentResult {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return .result()
    }
}
```

---

*Последнее обновление: Декабрь 2025*  
*Добавлено: Haptic Feedback и ограничения Widget Extension*