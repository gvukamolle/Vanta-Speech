# Building Responsive iOS Live Activities with Timers and Controls

> Гайд по реализации отзывчивых Live Activity для приложений с таймерами и интерактивными кнопками (Vanta Speech use case)

## TL;DR

Три ключевых паттерна для устранения задержек и багов:

1. **Таймер** — используй `Text(timerInterval:)`, а не ручные обновления
2. **Кнопки** — `LiveActivityIntent` протокол, а не базовый `AppIntent`
3. **Архитектура** — Intent должен быть в обоих таргетах (app + widget extension)

---

## Лучшие репозитории для изучения

| Репозиторий | Stars | Что смотреть |
|-------------|-------|--------------|
| [pawello2222/WidgetExamples](https://github.com/pawello2222/WidgetExamples) | 1100+ | Interactive Widget, Live Activity с AppIntent |
| [1998code/iOS16-Live-Activities](https://github.com/1998code/iOS16-Live-Activities) | 400+ | SwiftPizza — полный CRUD lifecycle |
| [ceciliahollins/ActivityKit-laboratory](https://github.com/ceciliahollins/ActivityKit-laboratory) | — | Music player controls, чёткая документация |
| [rgommezz/timer-live-activity](https://github.com/rgommezz/timer-live-activity) | 244 | React Native bridge, bidirectional communication |

---

## Таймер без лагов

### Проблема
Ручное обновление таймера через `Activity.update()` — это:
- Расход лимита обновлений (ActivityKit budget)
- Задержки между обновлениями
- Таймер "дёргается"

### Решение
Делегируй рендеринг OS:

```swift
// OS сам обновляет каждую секунду — zero API calls
Text(timerInterval: context.state.recordingStarted...Date.distantFuture, countsDown: false)
    .monospacedDigit()
    .contentTransition(.numericText())
```

### Pause/Resume логика

```swift
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date?
        var pausedAt: Date?
        var isPaused: Bool
    }
}

// В View
@ViewBuilder
var timerView: some View {
    if context.state.isPaused, let pausedAt = context.state.pausedAt {
        // Показываем замороженное время
        Text(formatElapsedTime(from: context.state.startedAt, to: pausedAt))
            .monospacedDigit()
    } else if let startedAt = context.state.startedAt {
        // Живой таймер
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
    }
}

func formatElapsedTime(from start: Date?, to end: Date) -> String {
    guard let start = start else { return "00:00" }
    let interval = end.timeIntervalSince(start)
    let minutes = Int(interval) / 60
    let seconds = Int(interval) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}
```

### Фикс расширения Dynamic Island

Таймер может "раздувать" layout. Фикс:

```swift
Text(Date(), style: .timer)
    .frame(width: 50)  // Фиксированная ширина
    .monospacedDigit()
```

### ⚠️ iOS 18 баг

**НЕ ИСПОЛЬЗУЙ:**
```swift
// CRASH chronod service!
Date(timeInterval: .infinity, since: start)
```

**Используй:**
```swift
// Большое конечное значение
Date(timeInterval: 100000, since: start)
```

---

## Кнопки без задержек — Three-File Pattern

### Почему кнопки тормозят?

По умолчанию `AppIntent` выполняется в **widget extension process**, который:
- Не имеет доступа к `Activity.activities`
- Ограничен в ресурсах
- Не может обновить Live Activity

### Решение: LiveActivityIntent + Split Implementation

#### Файл 1: Shared Definition (оба таргета)

```swift
// File: RecordingIntents.swift
// Target Membership: ✅ App, ✅ Widget Extension

import AppIntents

struct ToggleRecordingIntent {
    static var title: LocalizedStringResource = "Toggle Recording"
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Activity ID")
    var activityId: String
    
    init() { }
    init(activityId: String) { self.activityId = activityId }
}

struct StopRecordingIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Activity ID")
    var activityId: String
    
    init() { }
    init(activityId: String) { self.activityId = activityId }
}
```

#### Файл 2: App Implementation (только main app)

```swift
// File: RecordingIntents+App.swift
// Target Membership: ✅ App, ❌ Widget Extension

import AppIntents
import ActivityKit

extension ToggleRecordingIntent: LiveActivityIntent {
    @MainActor
    func perform() async throws -> some IntentResult {
        // Твоя бизнес-логика
        RecordingManager.shared.toggle()
        
        // Обновляем Live Activity
        let newState = RecordingAttributes.ContentState(
            isPaused: RecordingManager.shared.isPaused,
            startedAt: RecordingManager.shared.startedAt,
            pausedAt: RecordingManager.shared.pausedAt
        )
        
        for activity in Activity<RecordingAttributes>.activities {
            await activity.update(
                ActivityContent(state: newState, staleDate: nil)
            )
        }
        
        return .result()
    }
}

extension StopRecordingIntent: LiveActivityIntent {
    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingManager.shared.stop()
        
        for activity in Activity<RecordingAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        
        return .result()
    }
}
```

#### Файл 3: Widget Stub (только widget extension)

```swift
// File: RecordingIntents+Widget.swift
// Target Membership: ❌ App, ✅ Widget Extension

import AppIntents

extension ToggleRecordingIntent: LiveActivityIntent {
    func perform() async throws -> some IntentResult {
        // Никогда не выполняется — система роутит в app process
        return .result()
    }
}

extension StopRecordingIntent: LiveActivityIntent {
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
```

### Почему это работает?

`LiveActivityIntent` протокол **гарантирует** выполнение в main app process. Система игнорирует widget extension implementation и всегда вызывает app-версию.

---

## Конфигурация проекта

### Info.plist (оба таргета)

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

### App Groups

```swift
// Для синхронизации состояния между app и extension
let sharedDefaults = UserDefaults(suiteName: "group.com.vantaspeech")
```

### Target Membership для ActivityAttributes

```swift
// File: RecordingAttributes.swift
// Target Membership: ✅ App, ✅ Widget Extension  <-- ОБЯЗАТЕЛЬНО ОБА!

import ActivityKit

struct RecordingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startedAt: Date?
        var pausedAt: Date?
        var isPaused: Bool
    }
    
    // Static data (не меняется после старта)
    var sessionId: String
}
```

### Ограничение размера данных

**Static + Dynamic data ≤ 4KB**

Превышение = silent failure, Live Activity не появится.

---

## Полный пример View

```swift
import SwiftUI
import WidgetKit
import ActivityKit

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            // MARK: - Lock Screen / Banner
            LockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded State
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Image(systemName: "waveform")
                            .foregroundColor(.red)
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    TimerView(context: context)
                        .font(.title2.monospacedDigit())
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 12) {
                        Button(intent: ToggleRecordingIntent(activityId: context.activityID)) {
                            Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        
                        Button(intent: StopRecordingIntent(activityId: context.activityID)) {
                            Image(systemName: "stop.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Recording in progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            } compactLeading: {
                // MARK: - Compact Leading
                HStack(spacing: 4) {
                    Circle()
                        .fill(context.state.isPaused ? .orange : .red)
                        .frame(width: 6, height: 6)
                    Image(systemName: "waveform")
                        .font(.caption)
                }
                
            } compactTrailing: {
                // MARK: - Compact Trailing
                TimerView(context: context)
                    .font(.caption.monospacedDigit())
                    .frame(width: 45)
                
            } minimal: {
                // MARK: - Minimal (when other Live Activity is expanded)
                Image(systemName: "waveform")
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Subviews

struct LockScreenView: View {
    let context: ActivityViewContext<RecordingAttributes>
    
    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(context.state.isPaused ? .orange : .red)
                    .frame(width: 10, height: 10)
                
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundColor(context.state.isPaused ? .orange : .red)
            }
            
            // Timer
            TimerView(context: context)
                .font(.title2.monospacedDigit().bold())
            
            Spacer()
            
            // Controls
            HStack(spacing: 16) {
                Button(intent: ToggleRecordingIntent(activityId: context.activityID)) {
                    Image(systemName: context.state.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button(intent: StopRecordingIntent(activityId: context.activityID)) {
                    Image(systemName: "stop.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

struct TimerView: View {
    let context: ActivityViewContext<RecordingAttributes>
    
    var body: some View {
        if context.state.isPaused, let pausedAt = context.state.pausedAt, let startedAt = context.state.startedAt {
            // Frozen time display
            Text(formatElapsed(from: startedAt, to: pausedAt))
                .foregroundColor(.orange)
        } else if let startedAt = context.state.startedAt {
            // Live timer — OS handles updates
            Text(timerInterval: startedAt...Date(timeIntervalSinceNow: 100000), countsDown: false)
                .foregroundColor(.white)
        } else {
            Text("00:00")
                .foregroundColor(.secondary)
        }
    }
    
    private func formatElapsed(from start: Date, to end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
```

---

## Troubleshooting

| Проблема | Причина | Решение |
|----------|---------|---------|
| Кнопка открывает приложение | Используется closure вместо intent | `Button(intent: MyIntent())` |
| Кнопка работает, но Activity не обновляется | Intent в widget process | Используй `LiveActivityIntent` протокол |
| "Could not find intent" error | Intent нет в app target | Добавь в оба таргета |
| Таймер застрял на 00:00 | Ручное обновление без background | `Text(timerInterval:)` |
| Live Activity не появляется (iOS 17) | `@Environment(\.isActivityFullscreen)` | Убери эту переменную |
| Серая пустая Live Activity | Данные > 4KB | Уменьши ContentState |
| Xcode 16 + iOS 17 не работает | Known compatibility bug | Собирай Xcode 15 для iOS 17 |

---

## Отладка

### Console.app фильтры

Фильтруй по bundle ID и смотри процессы:
- **springboardd** — рендеринг Dynamic Island / Lock Screen
- **liveactivitiesd** — lifecycle events
- **chronod** — timer rendering (iOS 18 crashes здесь)

### Проверка авторизации

```swift
func canStartActivity() -> Bool {
    let authInfo = ActivityAuthorizationInfo()
    
    guard authInfo.areActivitiesEnabled else {
        print("❌ Live Activities disabled by user")
        return false
    }
    
    // iOS 17.2+: check frequent updates
    if #available(iOS 17.2, *) {
        print("Frequent updates: \(authInfo.frequentPushesEnabled)")
    }
    
    return true
}
```

### Запуск Activity

```swift
func startRecordingActivity() {
    guard canStartActivity() else { return }
    
    let attributes = RecordingAttributes(sessionId: UUID().uuidString)
    let initialState = RecordingAttributes.ContentState(
        startedAt: Date(),
        pausedAt: nil,
        isPaused: false
    )
    
    let content = ActivityContent(state: initialState, staleDate: nil)
    
    do {
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil  // Локальные обновления
        )
        print("✅ Started activity: \(activity.id)")
    } catch {
        print("❌ Failed to start: \(error)")
    }
}
```

---

## Важные ограничения

1. **Background Audio НЕ даёт права на обновление Live Activity** — только APNs push или `Text(timerInterval:)`

2. **Симулятор ≠ Девайс** — тестируй на физическом устройстве, особенно background execution и intent routing

3. **Update budget** — ~15-30 обновлений в час, после чего система throttle'ит

4. **Stale date** — устанавливай, если данные имеют срок актуальности

---

## Ссылки

- [Apple: Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Apple: ActivityKit](https://developer.apple.com/documentation/activitykit)
- [WWDC22: Meet ActivityKit](https://developer.apple.com/videos/play/wwdc2022/10184/)
- [WWDC23: Update Live Activities with push notifications](https://developer.apple.com/videos/play/wwdc2023/10185/)
