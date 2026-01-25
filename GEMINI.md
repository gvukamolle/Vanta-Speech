# Vanta Speech Project Context

## Project Overview
Vanta Speech is a cross-platform mobile application (iOS and Android) designed for recording, transcribing, and summarizing meetings. It integrates with corporate infrastructure (Exchange ActiveSync) to sync with calendars and send meeting summaries via email. The project is split into two native client applications.

## Architecture & Tech Stack

### iOS Client (`Vanta Speech iOS`)
*   **Language:** Swift
*   **UI Framework:** SwiftUI
*   **Persistence:** SwiftData
*   **Audio:** AVFoundation, FFmpegKit (for OGG/Opus conversion)
*   **Networking:** URLSession (async/await)
*   **Key Modules:**
    *   `App/`: Entry point and navigation.
    *   `Features/`: Functional modules (Recording, Library, Settings, Auth, Confluence).
    *   `Core/`: Foundation services (Audio, Network, Storage, EAS).
    *   `Shared/`: UI components and shared logic.

### Android Client (`Vanta Sppech Android`)
*   **Language:** Kotlin
*   **UI Framework:** Jetpack Compose
*   **Architecture:** MVVM with Clean Architecture principles
*   **DI:** Hilt
*   **Async:** Coroutines & Flow
*   **Key Packages:**
    *   `core/`: Domain, data, audio, auth, calendar.
    *   `feature/`: Recording, realtime, library, settings.
    *   `ui/`: Components, navigation, theme.

## Build & Test Commands

### iOS
*   **Directory:** `Vanta Speech iOS`
*   **Build:** `xcodebuild -scheme "Vanta Speech" build`
*   **Test:** `xcodebuild -scheme "Vanta Speech" test`
*   **Single Test:** `xcodebuild test -only-testing:VantaSpeechTests/ClassName/testName`

### Android
*   **Directory:** `Vanta Sppech Android` (Note the directory name typo)
*   **Build:** `./gradlew assembleDebug`
*   **Test:** `./gradlew test`
*   **Lint:** `./gradlew lintDebug`
*   **Single Test:** `./gradlew test --tests ClassName.testName`

## Development Guidelines

### General
*   **Formatting:** Follow official style guides (Kotlin official, Xcode defaults).
*   **Secrets:** Never commit secrets. Use `local.properties` or Keychain.
*   **Conventions:**
    *   **Kotlin:** PascalCase for classes, camelCase for variables/functions.
    *   **Swift:** PascalCase for types, camelCase for properties.

### Android Specifics
*   **Imports:** `stdlib` -> `Android` -> `Project`, alphabetically.
*   **Composables:** PascalCase, camelCase arguments.
*   **ViewModels:** Suffix `ViewModel`, utilize `MutableStateFlow`.
*   **Constants:** `object Consts` with `UPPER_SNAKE_CASE`.

### iOS Specifics
*   **Imports:** Group `Foundation`, `SwiftUI`, `SwiftData`, `AVFoundation` together.
*   **Models:** `@Model` classes should be `final`.
*   **Views:** Suffix `View`, use `@State` or `@StateObject`.
*   **Error Handling:** Use `enum` with String descriptions and `localizedDescription`.

## Key Features
*   **Audio Recording:** Local recording with background support.
*   **Transcription:** Server-side AI transcription (POST `/transcribe`).
*   **Summarization:** Automated meeting summaries.
*   **Calendar Integration:** Exchange ActiveSync (EAS) for calendar syncing.
*   **Email Reports:** HTML summary emails sent via EAS.
*   **Export:** Planned integration with Confluence.
