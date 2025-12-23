# Vanta Speech - Meeting Recorder App

## Project Overview
Мультиплатформенное приложение для записи, транскрипции и саммаризации встреч.

### Supported Platforms
- **iOS** - Swift/SwiftUI (основная платформа разработки)
- **macOS** - Swift/SwiftUI (нативный десктоп)
- **Android** - Kotlin/Jetpack Compose
- **Windows** - C#/WinUI 3 (.NET 8)

### Development Strategy
Разработка ведётся по принципу "iOS-first":
1. Новые фичи разрабатываются и тестируются на iOS
2. Затем портируются на остальные платформы
3. Платформо-специфичные адаптации делаются по необходимости

### Core Features
1. Локальная запись аудио в формате OGG
2. Отправка на сервер для транскрипции
3. Получение транскрипции и саммари
4. Интеграция с Confluence/Notion/Google Docs/Notes
5. Локальное хранение и отображение записей
6. Воспроизведение записей

## Swift Resources for Актуализации

### Official Documentation
- **Swift Book**: https://github.com/swiftlang/swift-book
  - Официальная документация языка Swift
  - Обновляется с каждым релизом
  - Локальная сборка: `xcrun docc preview TSPL.docc`

- **Swift Evolution**: https://github.com/apple/swift-evolution
  - Отслеживание развития языка Swift
  - Proposals для новых фич
  - Release timeline для версий Swift

### Swift 6.x Key Features (для использования в проекте)

#### Concurrency (важно для async аудио операций)
- SE-0296: Async/await
- SE-0304: Structured concurrency
- SE-0306: Actors
- SE-0413: Typed throws
- SE-0461: Async function isolation
- SE-0466: Control default actor isolation

#### Memory & Performance
- SE-0426: Bitwise copyable
- SE-0430: Transferring parameters and results

#### Macros
- SE-0382: Expression macros
- SE-0389: Attached macros

## Technology Stack

### Frameworks
- **SwiftUI** - UI framework
- **AVFoundation** - Audio recording & playback
- **SwiftData** - Local storage (или Core Data для совместимости)
- **URLSession** - Network requests (async/await)
- **FFmpegKit** - Audio conversion to OGG/Opus

### Target Platforms
- iOS 17.0+
- macOS 14.0+ (Sonoma)
- Swift 6.0+ (Swift Tools Version 6.0)

## Architecture

### Project Structure (Multiplatform)
```
Vanta-Speach/
├── VantaSpeech/              # iOS Swift code (SPM package)
│   ├── App/                  # App entry point
│   ├── Features/             # Feature modules
│   ├── Core/                 # Core services (Audio, Network, Storage)
│   └── Shared/               # Reusable UI components
│
├── VantaSpeech-macOS/        # macOS native app
│   └── VantaSpeech/
│       ├── App/              # macOS app entry (menu bar, window)
│       ├── Views/            # macOS-optimized SwiftUI views
│       ├── Services/         # Audio, Network services
│       └── Models/           # SwiftData models
│
├── VantaSpeech-Android/      # Android Kotlin project
│   └── app/src/main/
│       ├── java/com/vantaspeech/
│       │   ├── ui/           # Jetpack Compose screens
│       │   ├── data/         # Room DB, Repositories
│       │   ├── audio/        # MediaRecorder, ExoPlayer
│       │   └── di/           # Hilt DI modules
│       └── res/              # Android resources
│
├── VantaSpeech-Windows/      # Windows WinUI 3 project
│   └── VantaSpeech/
│       ├── Views/            # XAML pages
│       ├── ViewModels/       # MVVM ViewModels
│       ├── Services/         # Audio (NAudio), Network
│       ├── Models/           # EF Core entities
│       └── Styles/           # XAML resources
│
└── shared/                   # Cross-platform resources
    ├── icons/                # App icon sources
    ├── localization/         # Translation JSON files
    └── docs/                 # Architecture documentation
```

### Recommended Pattern: MVVM + Clean Architecture
```
[Platform]/
├── App/                    # App entry point
├── Features/Views/         # UI layer (SwiftUI/Compose/WinUI)
├── ViewModels/             # Presentation logic
├── Services/               # Business logic & data access
├── Models/                 # Data models
└── Resources/              # Assets, Localizations
```

## Coding Conventions

### Swift Style
- Use Swift 6 strict concurrency checking
- Prefer `async/await` over completion handlers
- Use `actor` for shared mutable state
- Apply `@MainActor` for UI-related code
- Use `Sendable` protocol for cross-actor data

### Naming
- Types: PascalCase (`RecordingManager`)
- Variables/Functions: camelCase (`startRecording()`)
- Constants: camelCase (`maxRecordingDuration`)

### File Organization
- One type per file (exceptions for small related types)
- Group by feature, not by layer

## API Integration

### Backend Server
Сервер транскрипции уже реализован. Эндпоинты:
- `POST /transcribe` - отправка аудио файла
- Response: JSON с транскрипцией и саммари

### Audio Format
- Recording: M4A/AAC (iOS native) → converted to OGG/Opus
- iOS нативно не поддерживает OGG запись
- Конвертация выполняется локально через FFmpegKit после записи

### OGG Conversion Pipeline
```
[AVAudioRecorder] → M4A/AAC → [FFmpegKit] → OGG/Opus → [Upload to Server]
```

**Параметры конвертации (AudioConverter.swift):**
- Codec: libopus (оптимален для голоса)
- Bitrate: **64 kbps** (фиксировано, оптимально для голоса)
- Sample rate: 48000 Hz
- Channels: 1 (mono, достаточно для встреч)
- Application: voip (оптимизация для голоса)
- VBR: on (variable bitrate для лучшего качества)
- ~480 KB/min (примерный размер файла)

**FFmpegKit SPM Package:**
```swift
.package(url: "https://github.com/arthenica/ffmpeg-kit-spm.git", from: "6.0.0")
```

## External Integrations

### Planned
- Confluence API
- Notion API
- Google Docs API
- Apple Notes (share extension)

## Build & Run

### iOS/macOS Requirements
- Xcode 16.0+
- iOS 17.0+ / macOS 14.0+
- Swift 6.0+

### iOS/macOS Commands
```bash
# Open in Xcode
open VantaSpeech.xcodeproj

# Build from command line
xcodebuild -scheme VantaSpeech -destination 'platform=iOS Simulator,name=iPhone 15'

# Run tests
xcodebuild test -scheme VantaSpeech -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Android Requirements
- Android Studio Ladybug (2024.2+)
- JDK 17+
- Android SDK 35 (target), SDK 26 (min)
- Kotlin 2.0+

### Android Commands
```bash
cd VantaSpeech-Android

# Build debug APK
./gradlew assembleDebug

# Run on connected device
./gradlew installDebug

# Run tests
./gradlew test
```

### Windows Requirements
- Visual Studio 2022 (17.8+)
- .NET 8.0 SDK
- Windows App SDK 1.5+
- Windows 10 (build 17763+) or Windows 11

### Windows Commands
```bash
cd VantaSpeech-Windows

# Build
dotnet build

# Run
dotnet run --project VantaSpeech

# Publish
dotnet publish -c Release -r win-x64
```

## Notes for Claude

### Multiplatform Development Strategy
1. **iOS-first**: Все новые фичи сначала реализуются на iOS
2. **Port, don't rewrite**: При портировании сохраняй логику, адаптируй UI
3. **Shared resources**: Используй `/shared/` для локализации и иконок
4. **API parity**: Все платформы должны поддерживать одинаковый API контракт
5. **Platform-native UX**: Каждая платформа должна чувствоваться нативной

### При работе над Swift кодом (iOS/macOS):
1. Проверяй актуальность API через swift-evolution proposals
2. Используй async/await для всех асинхронных операций
3. Помни о data-race safety в Swift 6
4. Для аудио операций используй AVAudioSession правильно (категории, режимы)

### При работе над Kotlin кодом (Android):
1. Используй Jetpack Compose для UI
2. Kotlin Coroutines для асинхронности
3. Hilt для dependency injection
4. Room для локального хранения
5. Media3/ExoPlayer для воспроизведения

### При работе над C# кодом (Windows):
1. WinUI 3 для UI (не WPF, не UWP)
2. CommunityToolkit.Mvvm для MVVM
3. Entity Framework Core для SQLite
4. NAudio для аудио операций
5. Async/await для асинхронности

### Ссылки для актуализации:
- Swift Book: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/
- Swift Evolution: https://github.com/apple/swift-evolution/tree/main/proposals
- Apple Developer: https://developer.apple.com/documentation/
- Android Developers: https://developer.android.com/develop
- Jetpack Compose: https://developer.android.com/jetpack/compose
- WinUI 3: https://learn.microsoft.com/en-us/windows/apps/winui/winui3/
- .NET 8: https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-8
