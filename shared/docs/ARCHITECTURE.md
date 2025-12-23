# Vanta Speech - Multiplatform Architecture

## Overview

Vanta Speech is a meeting recorder application with AI-powered transcription, available on multiple platforms:

- **iOS** - Swift/SwiftUI (primary development platform)
- **macOS** - Swift/SwiftUI (native desktop experience)
- **Android** - Kotlin/Jetpack Compose
- **Windows** - C#/WinUI 3

## Development Strategy

### iOS-First Approach

1. New features are developed and tested on iOS first
2. Features are then ported to other platforms
3. Platform-specific adaptations are made as needed

### Shared Components

While each platform has its own native implementation, the following are consistent:

- **Data Models** - Same structure across platforms
- **API Contract** - Identical server communication
- **UI/UX Patterns** - Similar user experience
- **Business Logic** - Equivalent algorithms

## Platform Structure

```
Vanta-Speach/
├── VantaSpeech/              # iOS/macOS shared Swift code
├── VantaSpeech-Android/      # Android Kotlin project
├── VantaSpeech-Windows/      # Windows C#/.NET project
├── VantaSpeech-macOS/        # macOS-specific Swift code
└── shared/                   # Cross-platform resources
    ├── icons/                # App icon sources
    ├── localization/         # Translation files
    └── docs/                 # Documentation
```

## Technology Stack

### iOS (VantaSpeech/)
- **Language**: Swift 6.0+
- **UI**: SwiftUI
- **Storage**: SwiftData
- **Audio**: AVFoundation + FFmpegKit
- **Networking**: URLSession (async/await)
- **Architecture**: MVVM + Clean Architecture

### macOS (VantaSpeech-macOS/)
- **Language**: Swift 6.0+
- **UI**: SwiftUI (macOS-optimized)
- **Storage**: SwiftData
- **Audio**: AVFoundation
- **Features**: Menu bar extra, keyboard shortcuts
- **Architecture**: MVVM

### Android (VantaSpeech-Android/)
- **Language**: Kotlin 2.0+
- **UI**: Jetpack Compose
- **Storage**: Room Database
- **Audio**: MediaRecorder + ExoPlayer
- **Networking**: Retrofit + OkHttp
- **DI**: Hilt
- **Architecture**: MVVM + Clean Architecture

### Windows (VantaSpeech-Windows/)
- **Language**: C# 12 / .NET 8
- **UI**: WinUI 3
- **Storage**: Entity Framework Core (SQLite)
- **Audio**: NAudio + Concentus (Opus)
- **Networking**: HttpClient
- **DI**: Microsoft.Extensions.DependencyInjection
- **Architecture**: MVVM

## Core Features

### 1. Audio Recording
- High-quality voice recording (44.1kHz, AAC)
- Background recording support
- Pause/Resume functionality
- Audio level visualization
- Automatic file management

### 2. Transcription
- Server-side AI transcription
- Multiple audio format support (M4A, OGG, MP3, WAV)
- Progress indication
- Error handling with retry

### 3. Library Management
- Searchable recording list
- Recording metadata (title, date, duration)
- Delete/Rename operations
- Recent recordings highlight

### 4. Audio Playback
- Standard controls (play, pause, stop)
- Seek functionality
- Skip forward/backward (15s)
- Progress visualization

### 5. Settings
- Server URL configuration
- Auto-transcribe toggle
- Audio quality selection
- Integration settings (future)

## API Contract

### Transcription Endpoint

```
POST /transcribe
Content-Type: multipart/form-data

Request:
- file: audio file (M4A, OGG, MP3, WAV)

Response:
{
  "transcription": "Full text...",
  "summary": "Summary text...",
  "language": "en",
  "duration": 125.5
}
```

## Data Model

### Recording

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| title | String | Recording name |
| createdAt | DateTime | Creation timestamp |
| duration | TimeInterval | Recording length (seconds) |
| audioFilePath | String | Local file path |
| transcriptionText | String? | Full transcription |
| summaryText | String? | AI summary |
| isTranscribed | Boolean | Transcription status |
| isUploading | Boolean | Upload progress flag |

## Audio Quality Levels

| Level | Bitrate | Use Case |
|-------|---------|----------|
| Low | 64 kbps | Smaller files, basic quality |
| Medium | 96 kbps | Balanced quality/size |
| High | 128 kbps | Best quality |

## Future Integrations

- Confluence API
- Notion API
- Google Docs API
- Apple Notes (iOS/macOS share extension)
