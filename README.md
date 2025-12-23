# Vanta Speech

iOS/macOS приложение для записи, транскрипции и саммаризации встреч.

## Features

- **Audio Recording** - Локальная запись аудио встреч
- **Transcription** - Отправка на сервер для распознавания речи
- **Summarization** - Автоматическое создание саммари встречи
- **Playback** - Воспроизведение записей с удобным плеером
- **Export** - Интеграция с Confluence, Notion, Google Docs

## Requirements

- Xcode 16.0+
- iOS 17.0+ / macOS 14.0+
- Swift 6.0+

## Setup

### 1. Create Xcode Project

1. Open Xcode
2. File → New → Project
3. Choose "App" under iOS or Multiplatform
4. Product Name: `VantaSpeech`
5. Organization Identifier: `com.yourcompany`
6. Interface: SwiftUI
7. Language: Swift
8. Storage: SwiftData

### 2. Add Source Files

Copy all files from `VantaSpeech/` directory into your Xcode project:

```
VantaSpeech/
├── App/
│   ├── VantaSpeechApp.swift
│   └── ContentView.swift
├── Features/
│   ├── Recording/
│   ├── Library/
│   └── Export/
├── Core/
│   ├── Audio/
│   ├── Network/
│   └── Storage/
└── Resources/
    └── Info.plist
```

### 3. Configure Info.plist

Ensure these keys are added for microphone access and background audio:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Vanta Speech needs access to your microphone to record meetings.</string>
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### 4. Configure Server URL

In Settings tab, enter your transcription server URL.

## Architecture

The app follows MVVM + Clean Architecture pattern:

- **App/** - Entry point and root views
- **Features/** - Feature modules (Recording, Library, Export)
- **Core/** - Shared services (Audio, Network, Storage)
- **Shared/** - Reusable components
- **Resources/** - Assets and configurations

## Tech Stack

- **SwiftUI** - User interface
- **SwiftData** - Local persistence
- **AVFoundation** - Audio recording & playback
- **URLSession** - Network requests with async/await

## License

Proprietary - Internal use only
