# Integrations reference (Vanta Speech Android)

## MSAL / Microsoft Graph (Outlook)
- MSAL manager: `Vanta Sppech Android/app/src/main/java/com/vanta/speech/core/calendar/MSALAuthManager.kt`
- Outlook calendar manager: `Vanta Sppech Android/app/src/main/java/com/vanta/speech/core/calendar/OutlookCalendarManager.kt`
- Graph API service: `Vanta Sppech Android/app/src/main/java/com/vanta/speech/core/calendar/GraphCalendarService.kt`
- DI: `Vanta Sppech Android/app/src/main/java/com/vanta/speech/core/di/CalendarModule.kt`

Notes:
- MSAL uses `R.raw.msal_config` for configuration.
- Current code uses `Log.d`/`Log.e` inside MSAL manager. Prefer Timber if/when available.

## Exchange / EAS (on-prem)
- Manager: `Vanta Sppech Android/app/src/main/java/com/vanta/speech/core/eas/EASCalendarManager.kt`
- Client: `Vanta Sppech Android/app/src/main/java/com/vanta/speech/core/eas/api/EASClient.kt`
- Models/errors: `Vanta Sppech Android/app/src/main/java/com/vanta/speech/core/eas/model/*`
- Credentials storage: `Vanta Sppech Android/app/src/main/java/com/vanta/speech/core/auth/SecurePreferencesManager.kt`

## Network stack
- Retrofit/OkHttp providers: `Vanta Sppech Android/app/src/main/java/com/vanta/speech/core/di/NetworkModule.kt`
- API interfaces: `core/data/remote/api/*`
- DTOs: `core/data/remote/dto/*`

## Confluence
No Confluence client is implemented in the Android module yet (only a disabled settings item). If adding integration, create a Retrofit API + repository and wire through Hilt, mirroring the iOS Confluence flow.

## Secure storage
- EncryptedSharedPreferences: `SecurePreferencesManager.kt`
- DataStore (non-sensitive): `core/data/local/prefs/PreferencesManager.kt`
- Room DB: `core/data/local/db/*`
