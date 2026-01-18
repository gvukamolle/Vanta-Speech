# Vanta Speech

iOS приложение для записи, транскрипции и саммаризации встреч.

## Features

- **Audio Recording** - Локальная запись аудио встреч с поддержкой фоновой записи
- **Transcription** - Отправка на сервер для распознавания речи (AI-powered)
- **Summarization** - Автоматическое создание саммари встречи
- **Calendar Integration** - Синхронизация с Exchange календарём (EAS), автоматическая привязка записей к встречам
- **Playback** - Воспроизведение записей с удобным плеером
- **Library** - Управление записями с поиском и фильтрацией
- **Export** - Интеграция с Confluence (planned)

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
- **Exchange ActiveSync** - Calendar sync (WBXML protocol)

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

### Calendar Setup

Для синхронизации с корпоративным календарём Exchange:

```
Настройки → Календарь → Подключить
```

Требуется:
- URL сервера Exchange (например: `https://mail.company.com/Microsoft-Server-ActiveSync`)
- Корпоративный логин и пароль

## Permissions

- Microphone access
- Background audio

## Contributing

See [CLAUDE.md](CLAUDE.md) for development guidelines and architecture details.

## License

Proprietary - Internal use only
