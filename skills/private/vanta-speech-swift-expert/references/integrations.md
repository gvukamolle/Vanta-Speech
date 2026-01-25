# Integrations reference (Vanta Speech iOS)

## Confluence
- Core client: `Vanta Speech iOS/Vanta Speech/Core/Confluence/API/ConfluenceClient.swift`
- Manager wrapper: `Vanta Speech iOS/Vanta Speech/Core/Confluence/ConfluenceManager.swift`
- Formatting: `Vanta Speech iOS/Vanta Speech/Core/Confluence/MeetingPageFormatter.swift`
- Markdown conversion: `Vanta Speech iOS/Vanta Speech/Core/Utils/MarkdownToConfluence.swift`

Key behaviors:
- Uses Basic Auth with credentials from Keychain (EAS credentials).
- Handles self-signed SSL via `URLSessionDelegate`.
- Implements retry on version conflicts when updating pages.

Example flow (simplified):
```
let manager = ConfluenceManager.shared
let page = try await manager.exportSummary(
    recording: recording,
    spaceKey: spaceKey,
    parentPageId: parentId
)
```

## Exchange / EAS
- Manager: `Vanta Speech iOS/Vanta Speech/Core/EAS/EASCalendarManager.swift`
- API client: `Vanta Speech iOS/Vanta Speech/Core/EAS/API/EASClient.swift`
- Models/errors: `Vanta Speech iOS/Vanta Speech/Core/EAS/Models/*`

Key behaviors:
- Credentials stored in Keychain; device ID persisted.
- Sync uses `EASSyncState` and supports full sync and incremental updates.
- Use `EASCalendarManager.shared` for calendar state and syncing.

## Authentication / Keychain
- Session/auth entry: `Vanta Speech iOS/Vanta Speech/Core/Auth/AuthenticationManager.swift`
- LDAP auth service: `Vanta Speech iOS/Vanta Speech/Core/Auth/LDAPAuthService.swift`
- Keychain storage: `Vanta Speech iOS/Vanta Speech/Core/Auth/KeychainManager.swift`

## Transcription / Summarization
- Actor-based service: `Vanta Speech iOS/Vanta Speech/Core/Network/TranscriptionService.swift`
- Uses `Env` config for base URL, API key, and model names.

## MSAL (placeholder)
No MSAL integration is present in this repo yet. If MSAL is introduced, keep it isolated in `Core/Auth` and wire through the existing auth flow. Prefer this high-level shape:
```
// Pseudocode only: adapt to MSAL APIs and app wiring
let app = MSALPublicClientApplication(config: msalConfig)
let params = MSALInteractiveTokenParameters(scopes: scopes)
let result = try await app.acquireToken(with: params)
try KeychainManager.shared.saveToken(result.accessToken)
```

Guidelines:
- Store tokens only in Keychain.
- Avoid logging raw tokens or PII.
- Use async/await wrappers around MSAL callbacks if needed.
