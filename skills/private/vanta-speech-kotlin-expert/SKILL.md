---
name: vanta-speech-kotlin-expert
description: Expert assistant for maintaining, refactoring, and extending the Vanta Speech Android app (Kotlin + Jetpack Compose). Use for changes to Compose UI, Clean Architecture/MVVM layers, recording/transcription/summarization, Exchange/EAS or MSAL integrations, Confluence export, networking, storage, or performance/security fixes in this repo.
---

# Vanta Speech Kotlin Expert

## Quick start
- Read `AGENTS.md` and follow its mandatory constraints.
- Identify affected module and follow existing patterns (Clean Architecture, MVVM, Hilt; minimal changes; no new deps without request).
- Confirm UX requirements: Compose-only UI, Material 3 minimalism, adaptive layout, Dynamic Color/Dark Mode, and corporate accent constraints.
- Use coroutines + StateFlow; avoid callbacks and RxJava.
- Keep secrets in secure storage and never log audio/transcripts.
- If ktlint/detekt configs are not present, follow the official Kotlin style and ask before introducing new lint configs.

## Architecture and navigation
- Follow Clean Architecture: `core/domain` (use cases, models), `core/data` (data sources), `core/di` (Hilt modules), `feature/*` (screens/ViewModels), `ui/*` (shared UI).
- ViewModels are Hilt-injected and expose `StateFlow` for UI state.
- Keep navigation consistent with existing setup; do not introduce new nav frameworks without request.

## UI and design guardrails
- Use Jetpack Compose and Material 3 components.
- Minimal layout: generous spacing, clear hierarchy, minimal chrome.
- Prefer Material Icons; only use custom vectors if they already exist.
- Support Dark Mode and Dynamic Color. If Dynamic Color isn’t wired yet, add it only when requested.
- Primary accent: corporate `#0052CC` only after confirming a palette change. Current app theme uses Vanta pink/blue accents.
- Keep animations subtle and meaningful (shared element transitions, `animate*AsState`, etc.).

## Concurrency, networking, and storage
- Use coroutines + `StateFlow`/`MutableStateFlow` for async state.
- Retrofit/OkHttp live in `core/di/NetworkModule.kt`; add APIs there and keep timeouts/retries consistent.
- Store sensitive data with `SecurePreferencesManager` (EncryptedSharedPreferences). Use DataStore for non-sensitive settings.
- Local DB uses Room (`core/data/local/db/*`).

## Security and privacy
- Never log raw audio/transcripts or tokens.
- Check `RECORD_AUDIO` permission with rationale before recording.
- Keep data within approved endpoints (transcription API, Exchange/EAS, Confluence).
- Maintain ProGuard/R8 rules when adding new SDKs.

## Logging and error handling
- Prefer Timber (if available). Avoid `Log.d`/`Log.e` in production code.
- Use sealed errors and user-friendly messages; surface failures in UI state.

## Testing
- Add unit tests for new/changed ViewModels and UseCases (JUnit + Turbine/MockK).
- If test targets are missing, ask before creating them.

## Project map (Android)
- `app/src/main/java/com/vanta/speech/core/` – domain, data, DI, audio, auth, calendar, eas.
- `app/src/main/java/com/vanta/speech/feature/` – recording, realtime, library, settings, auth.
- `app/src/main/java/com/vanta/speech/ui/` – components, navigation, theme.
- Services: `app/src/main/java/com/vanta/speech/service/` (recording service, notifications).

## Resources
- Read `references/material3-guidelines.md` for Material 3 typography/layout/color/motion/navigation links.
- Read `references/compose-components.md` for reusable components/modifiers in this codebase.
- Read `references/integrations.md` for MSAL/Exchange and network stack references.
- Use `assets/Color.kt` and `assets/Theme.kt` as palette/theme references.
- If custom icons are added, document them in `assets/CustomIcons.md`.
- Run `scripts/generate_changelog.py` to produce release notes from git history.
