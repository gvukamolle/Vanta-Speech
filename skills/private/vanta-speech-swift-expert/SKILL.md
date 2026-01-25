---
name: vanta-speech-swift-expert
description: Expert assistant for maintaining, refactoring, and extending the Vanta Speech iOS app (SwiftUI). Use when working in this repo on Swift/SwiftUI screens, MVVM + Coordinator navigation, recording/transcription/summarization, Exchange/EAS or Confluence integrations, authentication/storage, performance fixes, or security/privacy-sensitive changes.
---

# Vanta Speech Swift Expert

## Quick start
- Read `AGENTS.md` and follow its mandatory constraints.
- Identify impacted feature/module and follow existing patterns (minimal changes, no new dependencies).
- Confirm UX requirements: SwiftUI-only, minimal design, adaptive layout, full Dark Mode, Dynamic Type, SF Symbols, and accent color constraints.
- Use async/await + actors only; avoid completion handlers and blocking calls.
- Route secrets through Keychain or local-only config; never log audio/transcripts.

## Architecture and navigation
- Follow MVVM + Coordinator pattern; keep navigation logic inside coordinators.
- Prefer `@StateObject` for ViewModels and inject via environment when needed.
- Keep shared state in singletons only where already used (for example, `RecordingCoordinator.shared`).
- Avoid UIKit except for existing legacy wrappers; do not add new UIKit dependencies.

## UI and design guardrails
- Use SwiftUI and system typography with Dynamic Type; avoid custom fonts unless already in use.
- Keep layouts airy: generous spacing, clear hierarchy, minimal chrome.
- Support Compact/Regular size classes; use `NavigationSplitView` for iPad and `TabView` on iPhone.
- Use neutral palette with one accent color. Prefer the project palette in `Core/Theme/VantaColors.swift`; confirm any switch to corporate accent `#0052CC` before changing existing styling.
- Prefer SF Symbols; if custom symbols exist, follow assets list in `assets/CustomSFSymbols.md`.
- Keep animations subtle and meaningful; avoid decorative motion.

## Concurrency, networking, and storage
- Use `async/await` and `actor` for async services (see `Core/Network/TranscriptionService.swift`).
- Centralize network calls where possible; if a shared `NetworkManager` is introduced, keep it minimal and only wire new code to it unless refactoring is explicitly requested.
- Apply timeouts and retry/backoff for network calls handling conflicts or transient errors.
- Store credentials/tokens in Keychain (`Core/Auth/KeychainManager.swift`); use `UserDefaults` only for non-sensitive preferences.

## Security and privacy
- Never log or persist raw audio/transcripts outside approved APIs.
- Check microphone permissions before recording; handle denial paths cleanly.
- Keep data within allowed endpoints (Whisper/transcription API, Exchange/EAS, Confluence).

## Logging and error handling
- Avoid `print()`; prefer a centralized logger (OSLog/Logger). If the app still uses `debugLog`, keep behavior consistent and do not add new raw prints.
- Use typed errors (`enum: LocalizedError`) and surface user-friendly messages.

## Testing
- Add unit tests for any new/changed ViewModel using XCTest.
- If the test target is missing, ask before creating one; keep tests fast and deterministic.

## Project map (iOS)
- `App/` entry points and adaptive navigation.
- `Features/` feature screens (Recording, Library, Settings, Auth, Confluence).
- `Core/` services (Audio, Network, Storage, Auth, EAS, Confluence).
- `Shared/` reusable components, AppIntents, Live Activities.
- Design tokens and styles: `Core/Theme/*` and `vanta-speech-design-system.md`.

## Resources
- Read `references/apple-hig.md` for HIG typography/layout/color/navigation links.
- Read `references/swiftui-components.md` for reusable components/modifiers in this codebase.
- Read `references/integrations.md` for Exchange/EAS, Confluence, and MSAL snippets.
- Use `assets/ColorPalette.swift` and `assets/CustomSFSymbols.md` as design assets.
- Run `scripts/generate_changelog.py` to produce release notes from git history.
