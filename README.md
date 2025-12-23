# Vanta Speech

iOS приложение для записи, транскрипции и саммаризации встреч.

## Features

- **Audio Recording** - Локальная запись аудио встреч с поддержкой фоновой записи
- **Transcription** - Отправка на сервер для распознавания речи (AI-powered)
- **Summarization** - Автоматическое создание саммари встречи
- **Playback** - Воспроизведение записей с удобным плеером
- **Library** - Управление записями с поиском и фильтрацией
- **Export** - Интеграция с Confluence, Notion, Google Docs (planned)

## Quick Start

```bash
# Requirements: Xcode 16.0+, iOS 17.0+

# Open project
open VantaSpeech.xcodeproj

# Or build via CLI
xcodebuild -scheme VantaSpeech -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Project Structure

```
VantaSpeech/
├── App/                  # Entry point
├── Features/             # Feature modules
├── Core/                 # Audio, Network, Storage services
└── Shared/               # Reusable UI components
```

## Tech Stack

- **SwiftUI** - User interface
- **SwiftData** - Local persistence
- **AVFoundation** - Audio recording & playback
- **FFmpegKit** - OGG/Opus conversion
- **URLSession** - Async networking

## Configuration

### Server Setup

Configure your transcription server URL in the app settings:

```
Settings → Server URL → https://your-server.com
```

### API Endpoint

The app expects a transcription server with the following endpoint:

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

## Permissions

- Microphone access
- Background audio

## Contributing

See [CLAUDE.md](CLAUDE.md) for development guidelines and architecture details.

## License

Proprietary - Internal use only
