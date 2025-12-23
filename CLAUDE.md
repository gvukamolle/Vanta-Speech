# Vanta Speech - Meeting Recorder App

## Project Overview
iOS/macOS приложение для записи, транскрипции и саммаризации встреч.

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

### Recommended Pattern: MVVM + Clean Architecture
```
VantaSpeech/
├── App/                    # App entry point
├── Features/
│   ├── Recording/          # Audio recording feature
│   ├── Transcription/      # API integration for transcription
│   ├── Library/            # Recordings list & playback
│   └── Export/             # Integration with external services
├── Core/
│   ├── Audio/              # AVFoundation wrappers
│   ├── Network/            # API client
│   ├── Storage/            # SwiftData models
│   └── Extensions/         # Swift extensions
├── Shared/
│   ├── Components/         # Reusable UI components
│   └── Utils/              # Utilities
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

### Requirements
- Xcode 16.0+
- iOS 17.0+ / macOS 14.0+
- Swift 6.0+

### Commands
```bash
# Open in Xcode
open VantaSpeech.xcodeproj

# Build from command line
xcodebuild -scheme VantaSpeech -destination 'platform=iOS Simulator,name=iPhone 15'

# Run tests
xcodebuild test -scheme VantaSpeech -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Notes for Claude

### При работе над Swift кодом:
1. Проверяй актуальность API через swift-evolution proposals
2. Используй async/await для всех асинхронных операций
3. Помни о data-race safety в Swift 6
4. Для аудио операций используй AVAudioSession правильно (категории, режимы)

### Ссылки для актуализации:
- Swift Book: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/
- Swift Evolution: https://github.com/apple/swift-evolution/tree/main/proposals
- Apple Developer: https://developer.apple.com/documentation/
