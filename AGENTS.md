# Vanta Speech — AGENTS.md

Версия: 3.0
Дата: 28 января 2026
Статус: ОБЯЗАТЕЛЬНО К ИСПОЛНЕНИЮ

---

## Project Overview

Vanta Speech — кросс-платформенное мобильное приложение (iOS + Android) для записи, транскрипции и саммаризации встреч. Интегрируется с корпоративной инфраструктурой (Exchange ActiveSync, Microsoft Graph) для синхронизации с календарями и отправки саммари по email.

### Key Features
- **Audio Recording** — локальная запись аудио с поддержкой фоновой записи
- **Realtime Transcription** — потоковая транскрипция во время записи
- **Summarization** — AI-генерация саммари встречи с поддержкой пресетов
- **Calendar Integration** — синхронизация с Exchange/Outlook календарем
- **Email Summary** — отправка HTML-саммари участникам встречи
- **Library Management** — управление записями с поиском и фильтрацией
- **Confluence Export** — экспорт саммари в Confluence

---

## Project Structure

```
Vanta-Speech/
├── Vanta Speech iOS/              # iOS приложение
│   ├── Vanta Speech/
│   │   ├── App/                   # Точка входа, навигация
│   │   ├── Features/              # Фичи: Recording, Library, Settings, Auth, Confluence
│   │   ├── Core/                  # Сервисы: Audio, Network, Storage, Auth, EAS
│   │   └── Shared/                # UI компоненты, AppIntents, Live Activities
│   ├── VantaSpeechWidgets/        # Widget Extension + Live Activities
│   └── Vanta Speech.xcodeproj/
│
├── Vanta Sppech Android/          # Android приложение (NOTE: опечатка в названии папки)
│   ├── app/src/main/java/com/vanta/speech/
│   │   ├── core/                  # Domain, data, audio, auth, calendar, eas, di
│   │   ├── feature/               # recording, realtime, library, settings, auth
│   │   ├── ui/                    # components, navigation, theme
│   │   └── service/               # RecordingService (foreground service)
│   ├── build.gradle.kts
│   └── settings.gradle.kts
│
└── vanta-speech-design-system.md  # Design System (colors, typography, glassmorphism)
```

### Documentation Files

| File | Description |
|------|-------------|
| `vanta-speech-design-system.md` | Design System (colors, typography, glassmorphism) |
| `Vanta Speech iOS/EAS_CALENDAR_SYNC.md` | **EAS Calendar Sync** — detailed technical documentation for Exchange ActiveSync integration, recurring events handling, and series grouping algorithm |

---

## Technology Stack

### iOS
| Component | Technology |
|-----------|------------|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI |
| Persistence | SwiftData (App Groups для sharing с Widget) |
| Audio | AVFoundation, FFmpegKit (OGG/Opus conversion) |
| Networking | URLSession (async/await) |
| Authentication | MSAL (Microsoft), LDAP (корпоративный) |
| Calendar | Exchange ActiveSync (WBXML), Microsoft Graph |
| Build System | Xcode 16.0+, iOS 17.0+ |

### Android
| Component | Technology |
|-----------|------------|
| Language | Kotlin 2.0+ |
| UI Framework | Jetpack Compose (BOM 2024.02.00) |
| Architecture | MVVM + Clean Architecture |
| DI | Hilt 2.50 |
| Persistence | Room 2.6.1, DataStore |
| Audio | MediaRecorder, Media3 (ExoPlayer) |
| Networking | Retrofit 2.9, OkHttp 4.12 |
| Authentication | MSAL 4.9.0, LDAP |
| Calendar | Exchange Web Services (EWS), Microsoft Graph |
| Min SDK | 26 (Android 8.0) |
| Target SDK | 34 (Android 14) |

---

## Build and Test Commands

### iOS (`Vanta Speech iOS/`)

```bash
# Build
cd "Vanta Speech iOS" && xcodebuild -scheme "Vanta Speech" build

# Test
cd "Vanta Speech iOS" && xcodebuild -scheme "Vanta Speech" test

# Single test
cd "Vanta Speech iOS" && xcodebuild test -only-testing:VantaSpeechTests/ClassName/testName
```

### Android (`Vanta Sppech Android/`)

```bash
# Build debug
cd "Vanta Sppech Android" && ./gradlew assembleDebug

# Build release
cd "Vanta Sppech Android" && ./gradlew assembleRelease

# Run tests
cd "Vanta Sppech Android" && ./gradlew test

# Single test
cd "Vanta Sppech Android" && ./gradlew test --tests ClassName.testName

# Lint
cd "Vanta Sppech Android" && ./gradlew lintDebug
```

---

## Code Style Guidelines

### General
- Форматирование: Kotlin — официальный стиль (`kotlin.code.style=official`), Swift — Xcode defaults
- Имена файлов: PascalCase для классов (Kotlin) и типов (Swift)
- Секреты: только через `local.properties` / Keychain, **никогда не коммитить**

### Kotlin / Android
- Пакеты: `com.vanta.speech.{feature,core,ui}.{module}`
- Импорты: сначала stdlib, потом Android, потом проект, alphabetically
- Composable: PascalCase, аргументы camelCase
- ViewModel: суффикс `ViewModel`, `MutableStateFlow` для состояния
- DI: Hilt модули в `core/di/@{Feature}Module.kt`
- Error handling: sealed classes, `Result<T>`
- Константы: `object Consts`, `UPPER_SNAKE_CASE`

```kotlin
// Пример структуры ViewModel
@HiltViewModel
class RecordingViewModel @Inject constructor(
    private val recordingRepository: RecordingRepository,
    private val audioRecorder: AudioRecorder
) : ViewModel() {
    private val _state = MutableStateFlow<RecordingState>(RecordingState.Idle)
    val state: StateFlow<RecordingState> = _state.asStateFlow()
    
    fun startRecording() { /* ... */ }
}
```

### Swift / iOS
- Импорты: Foundation, SwiftUI, SwiftData, AVFoundation вместе
- `@Model` классы для SwiftData, `final class`
- Именование: camelCase для свойств, PascalCase для типов
- View: суффикс `View`, `@State`/`@StateObject` для состояния
- Async/await для networking, `Result<T>` для ошибок
- Error: enum с String описаниями, `localizedDescription`

```swift
// Пример структуры View
struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View { /* ... */ }
}
```

---

## Architecture Patterns

### Android (Clean Architecture)
```
feature/
├── RecordingScreen.kt          # UI (Compose)
└── RecordingViewModel.kt       # Presentation logic

core/
├── domain/
│   ├── model/                  # Domain models (Recording, RecordingState)
│   └── repository/             # Repository interfaces
├── data/
│   ├── local/                  # Room, DataStore
│   ├── remote/                 # API interfaces
│   └── repository/             # Repository implementations
└── di/                         # Hilt modules
```

### iOS (MVVM + SwiftData)
```
Features/
├── Recording/
│   ├── RecordingView.swift     # SwiftUI View
│   └── RecordingViewModel.swift # ViewModel

Core/
├── Storage/
│   └── Recording.swift         # @Model SwiftData
├── Audio/
│   ├── AudioRecorder.swift
│   └── AudioPlayer.swift
└── Network/
    └── TranscriptionService.swift
```

---

## Configuration & Secrets

### Android (`local.properties`)
```properties
API_BASE_URL=http://your-server:8000/v1/
API_KEY=your_api_key
AZURE_CLIENT_ID=your_msal_client_id
```

**Важно**: `local.properties` добавлен в `.gitignore` и никогда не коммитится.

### iOS
- Секреты хранятся в Keychain через `KeychainManager`
- Конфигурация сервера настраивается в приложении через Settings
- `Env.swift` добавлен в `.gitignore`

---

## API Integration

### Transcription Server
```
POST /transcribe
Content-Type: multipart/form-data

Request: file (audio/m4a, audio/ogg, audio/mp3, audio/wav)

Response:
{
  "transcription": "Full transcription text...",
  "summary": "Meeting summary...",
  "language": "en",
  "duration": 125.5
}
```

### Exchange ActiveSync (EAS)
- WBXML протокол для синхронизации календаря
- SendMail для отправки саммари
- Автоматическая привязка записей к событиям календаря

### Microsoft Graph
- OAuth 2.0 через MSAL
- Calendar API для событий
- SendMail для отправки саммари

---

## Security Considerations

1. **Никогда не коммитьте**:
   - `local.properties`
   - `Env.swift`
   - API keys, passwords, tokens

2. **Хранение данных**:
   - Android: EncryptedSharedPreferences для секретов
   - iOS: Keychain для чувствительных данных

3. **Permissions**:
   - Microphone access (NSMicrophoneUsageDescription)
   - Background audio
   - Internet

---

## Testing Strategy

### Unit Tests
- Android: JUnit 4, MockK для моков
- iOS: XCTest

### Integration Tests
- Android: Espresso для UI tests
- iOS: XCUITest

### Manual Testing Checklist
- [ ] Запись аудио в фоне
- [ ] Realtime транскрипция
- [ ] Синхронизация с Exchange календарем
- [ ] Отправка саммари по email
- [ ] Экспорт в Confluence
- [ ] Работа offline

---

## Deployment

### iOS
- Xcode → Product → Archive
- App Store Connect для distribution

### Android
```bash
# Generate release APK
cd "Vanta Sppech Android" && ./gradlew assembleRelease

# Or App Bundle for Play Store
cd "Vanta Sppech Android" && ./gradlew bundleRelease
```

---

## Skills Available

- `vanta-speech-swift-expert` — для работы с iOS кодом (SwiftUI, SwiftData, EAS)
- `vanta-speech-kotlin-expert` — для работы с Android кодом (Compose, Hilt, Room)
- `vanta-speech-quality-engineer` — для code review и тестирования

---

## Notes

- Директория Android имеет опечатку: `Vanta Sppech Android` (вместо `Vanta Speech Android`)
- Используйте `AGENTS.md` как единственный источник truth для команд и архитектуры
- Обновляйте этот файл при изменении структуры проекта или добавлении новых зависимостей
