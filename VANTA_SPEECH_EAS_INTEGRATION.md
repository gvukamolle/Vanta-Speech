# Vanta Speech — Exchange ActiveSync Integration

## Technical Specification for Claude Code

**Version:** 1.0  
**Date:** January 2026  
**Target Platforms:** iOS, Android  
**Exchange Protocol:** ActiveSync (EAS) with Basic Authentication  
**Architecture:** Variant C — Local Credential Storage

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Exchange ActiveSync Protocol](#3-exchange-activesync-protocol)
4. [Credential Storage](#4-credential-storage)
5. [iOS Implementation](#5-ios-implementation)
6. [Android Implementation](#6-android-implementation)
7. [Calendar Operations](#7-calendar-operations)
8. [Meeting Attendees](#8-meeting-attendees)
9. [Creating Events (Meeting Summary)](#9-creating-events-meeting-summary)
10. [Error Handling](#10-error-handling)
11. [Security Considerations](#11-security-considerations)
12. [Testing](#12-testing)

---

## 1. Executive Summary

### Project Goal

Integrate Vanta Speech mobile application with corporate Microsoft Exchange Server to:
- Authenticate users via corporate AD credentials
- Read calendar events and attendees
- Create calendar events with meeting summaries after user approval

### Key Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Protocol | ActiveSync (EAS) | On-premise Exchange, no Azure AD hybrid |
| Auth method | Basic Authentication | OAuth not configured on Exchange |
| Credential storage | Local device only | Security — no server-side password storage |
| Offline handling | Return network error | No background sync without user presence |
| Backend involvement | None for Exchange | Direct device-to-Exchange communication |

### Constraints

- Exchange Server is on-premise with Basic Auth enabled
- No OAuth/Modern Auth available
- Credentials must never leave the device
- Offline operations not supported — immediate error response required

---

## 2. Architecture Overview

### System Architecture (Variant C)

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER DEVICE                               │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    VANTA SPEECH APP                       │   │
│  │                                                           │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌──────────────┐  │   │
│  │  │   UI Layer  │───►│  Calendar   │───►│    EAS       │  │   │
│  │  │             │    │  Service    │    │   Client     │  │   │
│  │  └─────────────┘    └─────────────┘    └──────┬───────┘  │   │
│  │                                               │           │   │
│  │                     ┌─────────────────────────┴────────┐  │   │
│  │                     │      Credential Manager          │  │   │
│  │                     │  ┌─────────────────────────────┐ │  │   │
│  │                     │  │  iOS: Keychain Services     │ │  │   │
│  │                     │  │  Android: EncryptedShared   │ │  │   │
│  │                     │  │           Preferences +     │ │  │   │
│  │                     │  │           Android Keystore  │ │  │   │
│  │                     │  └─────────────────────────────┘ │  │   │
│  │                     └─────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                    │                             │
└────────────────────────────────────┼─────────────────────────────┘
                                     │ HTTPS + Basic Auth
                                     ▼
                    ┌────────────────────────────────┐
                    │      CORPORATE NETWORK         │
                    │  ┌──────────────────────────┐  │
                    │  │    Exchange Server       │  │
                    │  │    (On-Premise)          │  │
                    │  │                          │  │
                    │  │  ┌────────────────────┐  │  │
                    │  │  │   ActiveSync       │  │  │
                    │  │  │   /Microsoft-Server │  │  │
                    │  │  │   -ActiveSync      │  │  │
                    │  │  └────────────────────┘  │  │
                    │  │           │              │  │
                    │  │           ▼              │  │
                    │  │  ┌────────────────────┐  │  │
                    │  │  │  Active Directory  │  │  │
                    │  │  │  (Authentication)  │  │  │
                    │  │  └────────────────────┘  │  │
                    │  └──────────────────────────┘  │
                    └────────────────────────────────┘
```

### Data Flow

```
┌─────────┐     ┌─────────────┐     ┌─────────────┐     ┌──────────┐
│  User   │────►│  Enter      │────►│  Store in   │────►│  EAS     │
│  Login  │     │  Credentials│     │  Keychain/  │     │  Request │
│         │     │             │     │  Keystore   │     │          │
└─────────┘     └─────────────┘     └─────────────┘     └────┬─────┘
                                                              │
     ┌────────────────────────────────────────────────────────┘
     │
     ▼
┌──────────┐     ┌─────────────┐     ┌─────────────┐     ┌──────────┐
│ Exchange │────►│  Parse      │────►│  Display    │────►│  User    │
│ Response │     │  WBXML      │     │  Calendar   │     │  Views   │
│          │     │             │     │  Events     │     │  Events  │
└──────────┘     └─────────────┘     └─────────────┘     └──────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| UI Layer | Login form, calendar display, event details |
| Calendar Service | Business logic, data transformation, caching |
| EAS Client | Protocol implementation, WBXML encoding/decoding |
| Credential Manager | Secure storage and retrieval of credentials |

---

## 3. Exchange ActiveSync Protocol

### Protocol Overview

Exchange ActiveSync (EAS) is a synchronization protocol developed by Microsoft. For calendar operations, it uses:

- **Transport:** HTTPS
- **Authentication:** Basic Auth (Base64 encoded `domain\user:password`)
- **Content-Type:** `application/vnd.ms-sync.wbxml` (WBXML — WAP Binary XML)
- **Request Method:** POST
- **Endpoint:** `https://{server}/Microsoft-Server-ActiveSync`

### Required EAS Commands

| Command | Purpose | When Used |
|---------|---------|-----------|
| `OPTIONS` | Discover server capabilities and EAS version | Initial setup |
| `FolderSync` | Get folder hierarchy (find Calendar folder) | Initial sync |
| `Sync` | Get/create/update calendar items | Read events, create summary |
| `Ping` | Long-polling for changes (optional) | Real-time updates |
| `GetItemEstimate` | Get count of changes (optional) | Before large sync |

### EAS Version

Target **EAS Protocol Version 14.1** (Exchange 2010 SP1+). This version supports:
- Calendar with full attendee information
- Rich HTML body content
- Recurrence patterns
- Meeting responses

### URL Structure

```
POST /Microsoft-Server-ActiveSync?Cmd={Command}&User={Username}&DeviceId={DeviceId}&DeviceType={DeviceType}
```

**Query Parameters:**

| Parameter | Description | Example |
|-----------|-------------|---------|
| `Cmd` | EAS command name | `Sync`, `FolderSync`, `Ping` |
| `User` | Username (UPN or domain\user) | `user@company.com` |
| `DeviceId` | Unique device identifier | `VantaSpeech_{UUID}` |
| `DeviceType` | Device type string | `VantaSpeech` |

### WBXML Format

EAS uses WBXML — a binary XML format. You'll need a WBXML encoder/decoder.

**Libraries:**

- **iOS:** Custom implementation or port (no native support)
- **Android:** Custom implementation or use `libwbxml` via JNI

**Alternative:** Some EAS implementations accept `Content-Type: text/xml` with plain XML for debugging, but production should use WBXML for efficiency.

### Basic Auth Header

```
Authorization: Basic {base64(domain\username:password)}
```

**Example:**

```
Username: CORP\john.doe
Password: SecretPass123

Base64("CORP\john.doe:SecretPass123") = "Q09SUFxqb2huLmRvZTpTZWNyZXRQYXNzMTIz"

Header: Authorization: Basic Q09SUFxqb2huLmRvZTpTZWNyZXRQYXNzMTIz
```

### Common Request Headers

```http
POST /Microsoft-Server-ActiveSync?Cmd=Sync&User=john.doe&DeviceId=VantaSpeech_abc123&DeviceType=VantaSpeech HTTP/1.1
Host: mail.company.com
Authorization: Basic Q09SUFxqb2huLmRvZTpTZWNyZXRQYXNzMTIz
Content-Type: application/vnd.ms-sync.wbxml
MS-ASProtocolVersion: 14.1
X-MS-PolicyKey: 0
User-Agent: VantaSpeech/1.0
Content-Length: {length}
```

---

## 4. Credential Storage

### Security Requirements

1. **Encryption at rest** — credentials must be encrypted when stored
2. **Hardware-backed keys** — use Secure Enclave (iOS) / TEE (Android) when available
3. **No plaintext logging** — never log credentials
4. **Memory protection** — zero-out credential variables after use
5. **No export** — credentials cannot be backed up or transferred

### Storage Keys

Define consistent keys for credential storage:

```
KEYCHAIN_SERVICE = "com.vantaspeech.exchange"
KEY_USERNAME = "exchange_username"      // e.g., "CORP\john.doe"
KEY_PASSWORD = "exchange_password"      // user's AD password
KEY_SERVER_URL = "exchange_server_url"  // e.g., "https://mail.company.com"
KEY_DEVICE_ID = "exchange_device_id"    // generated UUID, persisted
```

### iOS: Keychain Services

**Configuration:**

```swift
// Keychain query dictionary
let baseQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.vantaspeech.exchange",
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    // Prevent backup/sync
    kSecAttrSynchronizable as String: false
]
```

**Access Control (recommended for password):**

```swift
// Require biometric or passcode to access
let accessControl = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    .userPresence,  // Require Face ID / Touch ID / Passcode
    nil
)

let passwordQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.vantaspeech.exchange",
    kSecAttrAccount as String: KEY_PASSWORD,
    kSecAttrAccessControl as String: accessControl as Any,
    kSecValueData as String: passwordData
]
```

### Android: EncryptedSharedPreferences + Keystore

**Configuration:**

```kotlin
// Master key backed by Android Keystore
val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .setUserAuthenticationRequired(true)  // Require biometric/PIN
    .setUserAuthenticationValidityDurationSeconds(300)  // 5 min validity
    .build()

val encryptedPrefs = EncryptedSharedPreferences.create(
    context,
    "vantaspeech_exchange_prefs",
    masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
)
```

### Credential Manager Interface

Define a common interface for both platforms:

```
interface CredentialManager {
    // Store credentials after successful login
    fun saveCredentials(username: String, password: String, serverUrl: String): Result<Unit>
    
    // Retrieve credentials for EAS request
    fun getCredentials(): Result<ExchangeCredentials>
    
    // Check if credentials exist
    fun hasCredentials(): Boolean
    
    // Clear credentials on logout
    fun clearCredentials(): Result<Unit>
    
    // Get or generate device ID (persisted)
    fun getDeviceId(): String
}

data class ExchangeCredentials(
    val username: String,
    val password: String,
    val serverUrl: String
)
```

---

## 5. iOS Implementation

### Project Structure

```
VantaSpeech/
├── Exchange/
│   ├── EASClient.swift              // Main EAS client
│   ├── EASCommands/
│   │   ├── FolderSyncCommand.swift  // FolderSync implementation
│   │   ├── SyncCommand.swift        // Sync implementation  
│   │   └── OptionsCommand.swift     // OPTIONS implementation
│   ├── WBXML/
│   │   ├── WBXMLEncoder.swift       // XML to WBXML
│   │   └── WBXMLDecoder.swift       // WBXML to XML
│   ├── Models/
│   │   ├── CalendarEvent.swift      // Calendar event model
│   │   ├── Attendee.swift           // Attendee model
│   │   └── SyncState.swift          // Sync key storage
│   └── CredentialManager.swift      // Keychain wrapper
├── Services/
│   └── CalendarService.swift        // Business logic
└── UI/
    ├── LoginView.swift
    └── CalendarView.swift
```

### CredentialManager.swift

```swift
import Foundation
import Security

enum CredentialError: Error {
    case encodingError
    case keychainError(OSStatus)
    case notFound
    case accessDenied
}

final class CredentialManager {
    
    static let shared = CredentialManager()
    
    private let service = "com.vantaspeech.exchange"
    
    private init() {}
    
    // MARK: - Public Interface
    
    func saveCredentials(username: String, password: String, serverUrl: String) throws {
        try save(key: "username", value: username)
        try save(key: "password", value: password, requireAuth: true)
        try save(key: "serverUrl", value: serverUrl)
        
        // Generate device ID if not exists
        if getDeviceId() == nil {
            let deviceId = "VantaSpeech_\(UUID().uuidString)"
            try save(key: "deviceId", value: deviceId)
        }
    }
    
    func getCredentials() throws -> ExchangeCredentials {
        guard let username = try? retrieve(key: "username"),
              let password = try? retrieve(key: "password"),
              let serverUrl = try? retrieve(key: "serverUrl") else {
            throw CredentialError.notFound
        }
        
        return ExchangeCredentials(
            username: username,
            password: password,
            serverUrl: serverUrl
        )
    }
    
    func hasCredentials() -> Bool {
        return (try? retrieve(key: "username")) != nil
    }
    
    func clearCredentials() throws {
        try delete(key: "username")
        try delete(key: "password")
        try delete(key: "serverUrl")
        // Keep deviceId for re-login
    }
    
    func getDeviceId() -> String? {
        return try? retrieve(key: "deviceId")
    }
    
    // MARK: - Private Keychain Operations
    
    private func save(key: String, value: String, requireAuth: Bool = false) throws {
        guard let data = value.data(using: .utf8) else {
            throw CredentialError.encodingError
        }
        
        // Delete existing item first
        try? delete(key: key)
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: false
        ]
        
        if requireAuth {
            // Require biometric or passcode for password
            var error: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                &error
            ) else {
                throw CredentialError.keychainError(-1)
            }
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
    }
    
    private func retrieve(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                throw CredentialError.notFound
            } else if status == errSecUserCanceled || status == errSecAuthFailed {
                throw CredentialError.accessDenied
            }
            throw CredentialError.keychainError(status)
        }
        
        return value
    }
    
    private func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychainError(status)
        }
    }
}

struct ExchangeCredentials {
    let username: String
    let password: String
    let serverUrl: String
    
    var basicAuthHeader: String {
        let credentials = "\(username):\(password)"
        let data = credentials.data(using: .utf8)!
        return "Basic \(data.base64EncodedString())"
    }
}
```

### EASClient.swift

```swift
import Foundation

enum EASError: Error {
    case noCredentials
    case networkError(Error)
    case serverError(Int, String?)
    case parseError(String)
    case folderNotFound
    case offline
}

final class EASClient {
    
    private let session: URLSession
    private let credentialManager: CredentialManager
    private let wbxmlEncoder: WBXMLEncoder
    private let wbxmlDecoder: WBXMLDecoder
    
    // Cached folder IDs
    private var calendarFolderId: String?
    private var syncKey: String = "0"  // Initial sync key
    
    init(
        credentialManager: CredentialManager = .shared,
        session: URLSession = .shared
    ) {
        self.credentialManager = credentialManager
        self.session = session
        self.wbxmlEncoder = WBXMLEncoder()
        self.wbxmlDecoder = WBXMLDecoder()
    }
    
    // MARK: - Public API
    
    /// Test connection and credentials
    func testConnection() async throws -> Bool {
        let response = try await sendCommand(.options)
        return response.statusCode == 200
    }
    
    /// Get calendar folder ID (required before sync)
    func discoverCalendarFolder() async throws -> String {
        if let cached = calendarFolderId {
            return cached
        }
        
        let folderId = try await performFolderSync()
        calendarFolderId = folderId
        return folderId
    }
    
    /// Get calendar events
    func getCalendarEvents() async throws -> [CalendarEvent] {
        let folderId = try await discoverCalendarFolder()
        return try await performSync(folderId: folderId, getChanges: true)
    }
    
    /// Create calendar event (for meeting summary)
    func createCalendarEvent(_ event: CalendarEvent) async throws -> String {
        let folderId = try await discoverCalendarFolder()
        return try await performSync(folderId: folderId, addItem: event)
    }
    
    // MARK: - EAS Commands
    
    private enum Command {
        case options
        case folderSync(syncKey: String)
        case sync(folderId: String, syncKey: String, changes: Bool, addItem: CalendarEvent?)
    }
    
    private func sendCommand(_ command: Command) async throws -> (statusCode: Int, data: Data) {
        // Check network availability
        guard NetworkMonitor.shared.isConnected else {
            throw EASError.offline
        }
        
        // Get credentials
        let credentials: ExchangeCredentials
        do {
            credentials = try credentialManager.getCredentials()
        } catch {
            throw EASError.noCredentials
        }
        
        // Build request
        let request = try buildRequest(command: command, credentials: credentials)
        
        // Execute
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw EASError.serverError(0, "Invalid response")
            }
            
            // Handle HTTP errors
            switch httpResponse.statusCode {
            case 200:
                return (200, data)
            case 401:
                throw EASError.serverError(401, "Authentication failed")
            case 403:
                throw EASError.serverError(403, "Access denied")
            case 503:
                throw EASError.serverError(503, "Server unavailable")
            default:
                throw EASError.serverError(httpResponse.statusCode, nil)
            }
        } catch let error as EASError {
            throw error
        } catch {
            throw EASError.networkError(error)
        }
    }
    
    private func buildRequest(command: Command, credentials: ExchangeCredentials) throws -> URLRequest {
        let deviceId = credentialManager.getDeviceId() ?? "VantaSpeech_Unknown"
        
        // Build URL
        var components = URLComponents(string: credentials.serverUrl)!
        components.path = "/Microsoft-Server-ActiveSync"
        
        let cmdName: String
        var body: Data?
        
        switch command {
        case .options:
            cmdName = "OPTIONS"
            
        case .folderSync(let syncKey):
            cmdName = "FolderSync"
            body = try buildFolderSyncBody(syncKey: syncKey)
            
        case .sync(let folderId, let syncKey, let getChanges, let addItem):
            cmdName = "Sync"
            body = try buildSyncBody(
                folderId: folderId,
                syncKey: syncKey,
                getChanges: getChanges,
                addItem: addItem
            )
        }
        
        components.queryItems = [
            URLQueryItem(name: "Cmd", value: cmdName),
            URLQueryItem(name: "User", value: credentials.username),
            URLQueryItem(name: "DeviceId", value: deviceId),
            URLQueryItem(name: "DeviceType", value: "VantaSpeech")
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = command.isOptions ? "OPTIONS" : "POST"
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        request.setValue("14.1", forHTTPHeaderField: "MS-ASProtocolVersion")
        request.setValue("0", forHTTPHeaderField: "X-MS-PolicyKey")
        request.setValue("VantaSpeech/1.0", forHTTPHeaderField: "User-Agent")
        
        if let body = body {
            request.setValue("application/vnd.ms-sync.wbxml", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        
        return request
    }
    
    // MARK: - FolderSync
    
    private func performFolderSync() async throws -> String {
        let response = try await sendCommand(.folderSync(syncKey: "0"))
        
        // Parse WBXML response
        let xml = try wbxmlDecoder.decode(response.data)
        
        // Find Calendar folder (type 8 = Calendar)
        // XML structure: FolderSync > Changes > Add > ServerId, Type
        guard let calendarFolder = xml.findFolder(type: 8) else {
            throw EASError.folderNotFound
        }
        
        return calendarFolder.serverId
    }
    
    private func buildFolderSyncBody(syncKey: String) throws -> Data {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <FolderSync xmlns="FolderHierarchy">
            <SyncKey>\(syncKey)</SyncKey>
        </FolderSync>
        """
        return try wbxmlEncoder.encode(xml)
    }
    
    // MARK: - Sync
    
    private func performSync(
        folderId: String,
        getChanges: Bool = true,
        addItem: CalendarEvent? = nil
    ) async throws -> [CalendarEvent] {
        
        let response = try await sendCommand(.sync(
            folderId: folderId,
            syncKey: syncKey,
            getChanges: getChanges,
            addItem: addItem
        ))
        
        // Parse response
        let xml = try wbxmlDecoder.decode(response.data)
        
        // Update sync key for next request
        if let newSyncKey = xml.extractSyncKey() {
            syncKey = newSyncKey
        }
        
        // Parse calendar events
        return xml.parseCalendarEvents()
    }
    
    private func buildSyncBody(
        folderId: String,
        syncKey: String,
        getChanges: Bool,
        addItem: CalendarEvent?
    ) throws -> Data {
        
        var commandsXml = ""
        
        if let event = addItem {
            commandsXml = """
            <Commands>
                <Add>
                    <ClientId>\(UUID().uuidString)</ClientId>
                    <ApplicationData>
                        \(event.toEASXml())
                    </ApplicationData>
                </Add>
            </Commands>
            """
        }
        
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <Sync xmlns="AirSync" xmlns:calendar="Calendar">
            <Collections>
                <Collection>
                    <SyncKey>\(syncKey)</SyncKey>
                    <CollectionId>\(folderId)</CollectionId>
                    <GetChanges>\(getChanges ? "1" : "0")</GetChanges>
                    <WindowSize>100</WindowSize>
                    <Options>
                        <BodyPreference xmlns="AirSyncBase">
                            <Type>2</Type>
                            <TruncationSize>51200</TruncationSize>
                        </BodyPreference>
                    </Options>
                    \(commandsXml)
                </Collection>
            </Collections>
        </Sync>
        """
        
        return try wbxmlEncoder.encode(xml)
    }
}

extension EASClient.Command {
    var isOptions: Bool {
        if case .options = self { return true }
        return false
    }
}
```

### CalendarEvent.swift

```swift
import Foundation

struct CalendarEvent: Identifiable, Codable {
    let id: String           // ServerId from Exchange
    let subject: String
    let startTime: Date
    let endTime: Date
    let location: String?
    let body: String?        // HTML content
    let organizer: Attendee?
    let attendees: [Attendee]
    let isAllDay: Bool
    let recurrence: Recurrence?
    
    // For creating new events
    var clientId: String?    // Client-generated ID for new items
    
    /// Convert to EAS XML format for Sync command
    func toEASXml() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        var xml = """
        <calendar:Subject>\(subject.xmlEscaped)</calendar:Subject>
        <calendar:StartTime>\(dateFormatter.string(from: startTime))</calendar:StartTime>
        <calendar:EndTime>\(dateFormatter.string(from: endTime))</calendar:EndTime>
        <calendar:AllDayEvent>\(isAllDay ? "1" : "0")</calendar:AllDayEvent>
        """
        
        if let location = location {
            xml += "<calendar:Location>\(location.xmlEscaped)</calendar:Location>"
        }
        
        if let body = body {
            xml += """
            <Body xmlns="AirSyncBase">
                <Type>2</Type>
                <Data>\(body.xmlEscaped)</Data>
            </Body>
            """
        }
        
        // Add attendees
        if !attendees.isEmpty {
            xml += "<calendar:Attendees>"
            for attendee in attendees {
                xml += """
                <calendar:Attendee>
                    <calendar:Email>\(attendee.email.xmlEscaped)</calendar:Email>
                    <calendar:Name>\(attendee.name.xmlEscaped)</calendar:Name>
                    <calendar:AttendeeType>\(attendee.type.rawValue)</calendar:AttendeeType>
                </calendar:Attendee>
                """
            }
            xml += "</calendar:Attendees>"
        }
        
        return xml
    }
}

struct Attendee: Codable, Identifiable {
    var id: String { email }
    let email: String
    let name: String
    let type: AttendeeType
    let status: ResponseStatus?
}

enum AttendeeType: Int, Codable {
    case required = 1
    case optional = 2
    case resource = 3
}

enum ResponseStatus: Int, Codable {
    case none = 0
    case organizer = 1
    case tentative = 2
    case accepted = 3
    case declined = 4
    case notResponded = 5
}

struct Recurrence: Codable {
    let type: RecurrenceType
    let interval: Int
    let dayOfWeek: Int?
    let dayOfMonth: Int?
    let until: Date?
}

enum RecurrenceType: Int, Codable {
    case daily = 0
    case weekly = 1
    case monthly = 2
    case yearly = 5
}

extension String {
    var xmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

### NetworkMonitor.swift

```swift
import Network

final class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    private(set) var isConnected = false
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
        }
        monitor.start(queue: queue)
    }
}
```

---

## 6. Android Implementation

### Project Structure

```
app/src/main/java/com/vantaspeech/
├── exchange/
│   ├── EASClient.kt                 // Main EAS client
│   ├── commands/
│   │   ├── FolderSyncCommand.kt
│   │   ├── SyncCommand.kt
│   │   └── OptionsCommand.kt
│   ├── wbxml/
│   │   ├── WBXMLEncoder.kt
│   │   └── WBXMLDecoder.kt
│   ├── models/
│   │   ├── CalendarEvent.kt
│   │   ├── Attendee.kt
│   │   └── SyncState.kt
│   └── CredentialManager.kt
├── services/
│   └── CalendarService.kt
└── ui/
    ├── LoginActivity.kt
    └── CalendarFragment.kt
```

### build.gradle dependencies

```groovy
dependencies {
    // Encrypted SharedPreferences
    implementation "androidx.security:security-crypto:1.1.0-alpha06"
    
    // Biometric
    implementation "androidx.biometric:biometric:1.1.0"
    
    // Network
    implementation "com.squareup.okhttp3:okhttp:4.12.0"
    
    // Coroutines
    implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3"
}
```

### CredentialManager.kt

```kotlin
package com.vantaspeech.exchange

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.util.UUID
import android.util.Base64

sealed class CredentialResult<out T> {
    data class Success<T>(val data: T) : CredentialResult<T>()
    data class Error(val exception: Exception) : CredentialResult<Nothing>()
}

data class ExchangeCredentials(
    val username: String,
    val password: String,
    val serverUrl: String
) {
    val basicAuthHeader: String
        get() {
            val credentials = "$username:$password"
            val encoded = Base64.encodeToString(
                credentials.toByteArray(Charsets.UTF_8),
                Base64.NO_WRAP
            )
            return "Basic $encoded"
        }
}

class CredentialManager(context: Context) {
    
    companion object {
        private const val PREFS_NAME = "vantaspeech_exchange_prefs"
        private const val KEY_USERNAME = "exchange_username"
        private const val KEY_PASSWORD = "exchange_password"
        private const val KEY_SERVER_URL = "exchange_server_url"
        private const val KEY_DEVICE_ID = "exchange_device_id"
        
        @Volatile
        private var instance: CredentialManager? = null
        
        fun getInstance(context: Context): CredentialManager {
            return instance ?: synchronized(this) {
                instance ?: CredentialManager(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }
    
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()
    
    private val encryptedPrefs = EncryptedSharedPreferences.create(
        context,
        PREFS_NAME,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )
    
    fun saveCredentials(
        username: String,
        password: String,
        serverUrl: String
    ): CredentialResult<Unit> {
        return try {
            encryptedPrefs.edit().apply {
                putString(KEY_USERNAME, username)
                putString(KEY_PASSWORD, password)
                putString(KEY_SERVER_URL, serverUrl)
                
                // Generate device ID if not exists
                if (!encryptedPrefs.contains(KEY_DEVICE_ID)) {
                    putString(KEY_DEVICE_ID, "VantaSpeech_${UUID.randomUUID()}")
                }
                
                apply()
            }
            CredentialResult.Success(Unit)
        } catch (e: Exception) {
            CredentialResult.Error(e)
        }
    }
    
    fun getCredentials(): CredentialResult<ExchangeCredentials> {
        return try {
            val username = encryptedPrefs.getString(KEY_USERNAME, null)
            val password = encryptedPrefs.getString(KEY_PASSWORD, null)
            val serverUrl = encryptedPrefs.getString(KEY_SERVER_URL, null)
            
            if (username == null || password == null || serverUrl == null) {
                CredentialResult.Error(IllegalStateException("Credentials not found"))
            } else {
                CredentialResult.Success(
                    ExchangeCredentials(username, password, serverUrl)
                )
            }
        } catch (e: Exception) {
            CredentialResult.Error(e)
        }
    }
    
    fun hasCredentials(): Boolean {
        return encryptedPrefs.contains(KEY_USERNAME) &&
               encryptedPrefs.contains(KEY_PASSWORD) &&
               encryptedPrefs.contains(KEY_SERVER_URL)
    }
    
    fun clearCredentials(): CredentialResult<Unit> {
        return try {
            encryptedPrefs.edit().apply {
                remove(KEY_USERNAME)
                remove(KEY_PASSWORD)
                remove(KEY_SERVER_URL)
                // Keep device ID for re-login
                apply()
            }
            CredentialResult.Success(Unit)
        } catch (e: Exception) {
            CredentialResult.Error(e)
        }
    }
    
    fun getDeviceId(): String {
        return encryptedPrefs.getString(KEY_DEVICE_ID, null)
            ?: "VantaSpeech_${UUID.randomUUID()}".also {
                encryptedPrefs.edit().putString(KEY_DEVICE_ID, it).apply()
            }
    }
}
```

### EASClient.kt

```kotlin
package com.vantaspeech.exchange

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.InetAddress
import java.util.concurrent.TimeUnit

sealed class EASResult<out T> {
    data class Success<T>(val data: T) : EASResult<T>()
    data class Error(val error: EASError) : EASResult<Nothing>()
}

sealed class EASError {
    object NoCredentials : EASError()
    object Offline : EASError()
    data class NetworkError(val cause: Throwable) : EASError()
    data class ServerError(val code: Int, val message: String?) : EASError()
    data class ParseError(val message: String) : EASError()
    object FolderNotFound : EASError()
    object AuthenticationFailed : EASError()
}

class EASClient(
    private val credentialManager: CredentialManager
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()
    
    private val wbxmlEncoder = WBXMLEncoder()
    private val wbxmlDecoder = WBXMLDecoder()
    
    private var calendarFolderId: String? = null
    private var syncKey: String = "0"
    
    // MARK: - Public API
    
    suspend fun testConnection(): EASResult<Boolean> = withContext(Dispatchers.IO) {
        if (!isNetworkAvailable()) {
            return@withContext EASResult.Error(EASError.Offline)
        }
        
        when (val result = sendOptionsRequest()) {
            is EASResult.Success -> EASResult.Success(true)
            is EASResult.Error -> result
        }
    }
    
    suspend fun getCalendarEvents(): EASResult<List<CalendarEvent>> = withContext(Dispatchers.IO) {
        if (!isNetworkAvailable()) {
            return@withContext EASResult.Error(EASError.Offline)
        }
        
        // First, get calendar folder ID
        val folderId = when (val result = discoverCalendarFolder()) {
            is EASResult.Success -> result.data
            is EASResult.Error -> return@withContext result
        }
        
        // Then sync events
        performSync(folderId, getChanges = true, addItem = null)
    }
    
    suspend fun createCalendarEvent(event: CalendarEvent): EASResult<String> = withContext(Dispatchers.IO) {
        if (!isNetworkAvailable()) {
            return@withContext EASResult.Error(EASError.Offline)
        }
        
        val folderId = when (val result = discoverCalendarFolder()) {
            is EASResult.Success -> result.data
            is EASResult.Error -> return@withContext result
        }
        
        when (val result = performSync(folderId, getChanges = false, addItem = event)) {
            is EASResult.Success -> EASResult.Success(event.clientId ?: "")
            is EASResult.Error -> result
        }
    }
    
    // MARK: - Private Methods
    
    private suspend fun discoverCalendarFolder(): EASResult<String> {
        calendarFolderId?.let { return EASResult.Success(it) }
        
        return when (val result = performFolderSync()) {
            is EASResult.Success -> {
                calendarFolderId = result.data
                EASResult.Success(result.data)
            }
            is EASResult.Error -> result
        }
    }
    
    private suspend fun sendOptionsRequest(): EASResult<Unit> {
        val credentials = when (val result = credentialManager.getCredentials()) {
            is CredentialResult.Success -> result.data
            is CredentialResult.Error -> return EASResult.Error(EASError.NoCredentials)
        }
        
        val url = buildUrl(credentials, "OPTIONS")
        
        val request = Request.Builder()
            .url(url)
            .method("OPTIONS", null)
            .header("Authorization", credentials.basicAuthHeader)
            .header("MS-ASProtocolVersion", "14.1")
            .header("User-Agent", "VantaSpeech/1.0")
            .build()
        
        return try {
            val response = client.newCall(request).execute()
            when (response.code) {
                200 -> EASResult.Success(Unit)
                401 -> EASResult.Error(EASError.AuthenticationFailed)
                else -> EASResult.Error(EASError.ServerError(response.code, response.message))
            }
        } catch (e: IOException) {
            EASResult.Error(EASError.NetworkError(e))
        }
    }
    
    private suspend fun performFolderSync(): EASResult<String> {
        val credentials = when (val result = credentialManager.getCredentials()) {
            is CredentialResult.Success -> result.data
            is CredentialResult.Error -> return EASResult.Error(EASError.NoCredentials)
        }
        
        val xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <FolderSync xmlns="FolderHierarchy">
                <SyncKey>0</SyncKey>
            </FolderSync>
        """.trimIndent()
        
        val body = wbxmlEncoder.encode(xml)
        val url = buildUrl(credentials, "FolderSync")
        
        val request = Request.Builder()
            .url(url)
            .post(body.toRequestBody(WBXML_MEDIA_TYPE))
            .header("Authorization", credentials.basicAuthHeader)
            .header("MS-ASProtocolVersion", "14.1")
            .header("User-Agent", "VantaSpeech/1.0")
            .build()
        
        return try {
            val response = client.newCall(request).execute()
            
            when (response.code) {
                200 -> {
                    val responseBody = response.body?.bytes() ?: return EASResult.Error(
                        EASError.ParseError("Empty response")
                    )
                    val responseXml = wbxmlDecoder.decode(responseBody)
                    
                    // Find Calendar folder (Type = 8)
                    val folderId = responseXml.findFolderByType(8)
                        ?: return EASResult.Error(EASError.FolderNotFound)
                    
                    EASResult.Success(folderId)
                }
                401 -> EASResult.Error(EASError.AuthenticationFailed)
                else -> EASResult.Error(EASError.ServerError(response.code, response.message))
            }
        } catch (e: IOException) {
            EASResult.Error(EASError.NetworkError(e))
        }
    }
    
    private suspend fun performSync(
        folderId: String,
        getChanges: Boolean,
        addItem: CalendarEvent?
    ): EASResult<List<CalendarEvent>> {
        val credentials = when (val result = credentialManager.getCredentials()) {
            is CredentialResult.Success -> result.data
            is CredentialResult.Error -> return EASResult.Error(EASError.NoCredentials)
        }
        
        val commandsXml = addItem?.let {
            """
            <Commands>
                <Add>
                    <ClientId>${java.util.UUID.randomUUID()}</ClientId>
                    <ApplicationData>
                        ${it.toEASXml()}
                    </ApplicationData>
                </Add>
            </Commands>
            """.trimIndent()
        } ?: ""
        
        val xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <Sync xmlns="AirSync" xmlns:calendar="Calendar">
                <Collections>
                    <Collection>
                        <SyncKey>$syncKey</SyncKey>
                        <CollectionId>$folderId</CollectionId>
                        <GetChanges>${if (getChanges) "1" else "0"}</GetChanges>
                        <WindowSize>100</WindowSize>
                        <Options>
                            <BodyPreference xmlns="AirSyncBase">
                                <Type>2</Type>
                                <TruncationSize>51200</TruncationSize>
                            </BodyPreference>
                        </Options>
                        $commandsXml
                    </Collection>
                </Collections>
            </Sync>
        """.trimIndent()
        
        val body = wbxmlEncoder.encode(xml)
        val url = buildUrl(credentials, "Sync")
        
        val request = Request.Builder()
            .url(url)
            .post(body.toRequestBody(WBXML_MEDIA_TYPE))
            .header("Authorization", credentials.basicAuthHeader)
            .header("MS-ASProtocolVersion", "14.1")
            .header("User-Agent", "VantaSpeech/1.0")
            .build()
        
        return try {
            val response = client.newCall(request).execute()
            
            when (response.code) {
                200 -> {
                    val responseBody = response.body?.bytes() ?: return EASResult.Error(
                        EASError.ParseError("Empty response")
                    )
                    val responseXml = wbxmlDecoder.decode(responseBody)
                    
                    // Update sync key
                    responseXml.extractSyncKey()?.let { syncKey = it }
                    
                    // Parse events
                    val events = responseXml.parseCalendarEvents()
                    EASResult.Success(events)
                }
                401 -> EASResult.Error(EASError.AuthenticationFailed)
                else -> EASResult.Error(EASError.ServerError(response.code, response.message))
            }
        } catch (e: IOException) {
            EASResult.Error(EASError.NetworkError(e))
        }
    }
    
    private fun buildUrl(credentials: ExchangeCredentials, command: String): String {
        val deviceId = credentialManager.getDeviceId()
        val username = credentials.username.substringAfter("\\", credentials.username)
        
        return "${credentials.serverUrl}/Microsoft-Server-ActiveSync" +
               "?Cmd=$command" +
               "&User=$username" +
               "&DeviceId=$deviceId" +
               "&DeviceType=VantaSpeech"
    }
    
    private fun isNetworkAvailable(): Boolean {
        return try {
            val address = InetAddress.getByName("8.8.8.8")
            !address.equals("")
        } catch (e: Exception) {
            false
        }
    }
    
    companion object {
        private val WBXML_MEDIA_TYPE = "application/vnd.ms-sync.wbxml".toMediaType()
    }
}
```

### CalendarEvent.kt

```kotlin
package com.vantaspeech.exchange.models

import java.text.SimpleDateFormat
import java.util.*

data class CalendarEvent(
    val id: String,
    val subject: String,
    val startTime: Date,
    val endTime: Date,
    val location: String? = null,
    val body: String? = null,
    val organizer: Attendee? = null,
    val attendees: List<Attendee> = emptyList(),
    val isAllDay: Boolean = false,
    val clientId: String? = null  // For new events
) {
    fun toEASXml(): String {
        val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        
        val sb = StringBuilder()
        
        sb.append("<calendar:Subject>${subject.xmlEscape()}</calendar:Subject>")
        sb.append("<calendar:StartTime>${dateFormat.format(startTime)}</calendar:StartTime>")
        sb.append("<calendar:EndTime>${dateFormat.format(endTime)}</calendar:EndTime>")
        sb.append("<calendar:AllDayEvent>${if (isAllDay) "1" else "0"}</calendar:AllDayEvent>")
        
        location?.let {
            sb.append("<calendar:Location>${it.xmlEscape()}</calendar:Location>")
        }
        
        body?.let {
            sb.append("""
                <Body xmlns="AirSyncBase">
                    <Type>2</Type>
                    <Data>${it.xmlEscape()}</Data>
                </Body>
            """.trimIndent())
        }
        
        if (attendees.isNotEmpty()) {
            sb.append("<calendar:Attendees>")
            attendees.forEach { attendee ->
                sb.append("""
                    <calendar:Attendee>
                        <calendar:Email>${attendee.email.xmlEscape()}</calendar:Email>
                        <calendar:Name>${attendee.name.xmlEscape()}</calendar:Name>
                        <calendar:AttendeeType>${attendee.type.value}</calendar:AttendeeType>
                    </calendar:Attendee>
                """.trimIndent())
            }
            sb.append("</calendar:Attendees>")
        }
        
        return sb.toString()
    }
}

data class Attendee(
    val email: String,
    val name: String,
    val type: AttendeeType = AttendeeType.REQUIRED,
    val status: ResponseStatus? = null
)

enum class AttendeeType(val value: Int) {
    REQUIRED(1),
    OPTIONAL(2),
    RESOURCE(3)
}

enum class ResponseStatus(val value: Int) {
    NONE(0),
    ORGANIZER(1),
    TENTATIVE(2),
    ACCEPTED(3),
    DECLINED(4),
    NOT_RESPONDED(5)
}

private fun String.xmlEscape(): String {
    return this
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("'", "&apos;")
        .replace("\"", "&quot;")
}
```

---

## 7. Calendar Operations

### Reading Calendar Events

**Flow:**

```
1. User opens calendar view
2. App checks credentials exist
3. If not → redirect to login
4. If yes → call EASClient.getCalendarEvents()
5. Handle result:
   - Success → display events
   - Offline → show cached events (if any) + offline message
   - Auth error → redirect to login
   - Other error → show error message
```

**Code (iOS):**

```swift
final class CalendarService: ObservableObject {
    
    @Published var events: [CalendarEvent] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let easClient: EASClient
    
    init(easClient: EASClient = EASClient()) {
        self.easClient = easClient
    }
    
    @MainActor
    func loadEvents() async {
        isLoading = true
        error = nil
        
        do {
            events = try await easClient.getCalendarEvents()
        } catch EASError.offline {
            error = "Нет подключения к сети. Проверьте интернет-соединение."
        } catch EASError.noCredentials {
            error = "Требуется авторизация"
            // Navigate to login
        } catch EASError.serverError(401, _) {
            error = "Неверные учётные данные"
            // Clear credentials and navigate to login
            try? CredentialManager.shared.clearCredentials()
        } catch {
            self.error = "Ошибка загрузки: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}
```

---

## 8. Meeting Attendees

### Data Structure

Attendees are part of the CalendarEvent from the Sync response:

```xml
<calendar:Attendees>
    <calendar:Attendee>
        <calendar:Email>john@company.com</calendar:Email>
        <calendar:Name>John Doe</calendar:Name>
        <calendar:AttendeeType>1</calendar:AttendeeType>
        <calendar:AttendeeStatus>3</calendar:AttendeeStatus>
    </calendar:Attendee>
</calendar:Attendees>
```

### Attendee Types

| Type | Value | Description |
|------|-------|-------------|
| Required | 1 | Must attend |
| Optional | 2 | May attend |
| Resource | 3 | Room/equipment |

### Response Status

| Status | Value | Description |
|--------|-------|-------------|
| None | 0 | No response |
| Organizer | 1 | Is the organizer |
| Tentative | 2 | Might attend |
| Accepted | 3 | Will attend |
| Declined | 4 | Won't attend |
| NotResponded | 5 | Hasn't responded |

### Usage in Vanta Speech

```swift
// Get attendees for a specific event
let event = events.first { $0.id == selectedEventId }
let attendees = event?.attendees ?? []

// Filter for actual people (not resources)
let people = attendees.filter { $0.type != .resource }

// Get email list for meeting summary
let emailList = people.map { $0.email }
```

---

## 9. Creating Events (Meeting Summary)

### Use Case

After a meeting, Vanta Speech needs to:
1. Generate meeting summary (from transcription)
2. Show summary to user for approval
3. On approval → create calendar event with summary
4. Event should include all original attendees

### Implementation

```swift
extension CalendarService {
    
    @MainActor
    func createMeetingSummary(
        originalEvent: CalendarEvent,
        summaryHtml: String
    ) async throws -> String {
        
        // Build summary event
        let summaryEvent = CalendarEvent(
            id: "",  // Will be assigned by server
            subject: "📝 Meeting Summary: \(originalEvent.subject)",
            startTime: Date().addingTimeInterval(3600),  // 1 hour from now
            endTime: Date().addingTimeInterval(4500),    // 15 min duration
            location: nil,
            body: summaryHtml,
            organizer: nil,
            attendees: originalEvent.attendees.filter { $0.type != .resource },
            isAllDay: false,
            clientId: UUID().uuidString
        )
        
        // Create via EAS
        return try await easClient.createCalendarEvent(summaryEvent)
    }
}
```

### Summary HTML Template

```swift
func buildSummaryHtml(
    meetingTitle: String,
    date: Date,
    attendees: [String],
    keyPoints: [String],
    actionItems: [ActionItem],
    transcriptExcerpt: String?
) -> String {
    
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .long
    dateFormatter.timeStyle = .short
    
    var html = """
    <html>
    <body style="font-family: -apple-system, sans-serif; padding: 16px;">
    <h2>📋 Meeting Summary</h2>
    <p><strong>Meeting:</strong> \(meetingTitle)</p>
    <p><strong>Date:</strong> \(dateFormatter.string(from: date))</p>
    <p><strong>Participants:</strong> \(attendees.joined(separator: ", "))</p>
    
    <h3>Key Points</h3>
    <ul>
    """
    
    for point in keyPoints {
        html += "<li>\(point)</li>"
    }
    
    html += """
    </ul>
    
    <h3>Action Items</h3>
    <ul>
    """
    
    for item in actionItems {
        html += "<li><strong>\(item.assignee):</strong> \(item.task) (Due: \(item.dueDate))</li>"
    }
    
    html += """
    </ul>
    """
    
    if let excerpt = transcriptExcerpt {
        html += """
        <h3>Transcript Excerpt</h3>
        <p style="color: #666; font-size: 14px;">\(excerpt)</p>
        """
    }
    
    html += """
    <hr>
    <p style="color: #999; font-size: 12px;">Generated by Vanta Speech</p>
    </body>
    </html>
    """
    
    return html
}

struct ActionItem {
    let assignee: String
    let task: String
    let dueDate: String
}
```

---

## 10. Error Handling

### Error Types and User Messages

| Error | User Message (RU) | Action |
|-------|-------------------|--------|
| `Offline` | "Нет подключения к сети" | Show retry button |
| `NoCredentials` | "Требуется вход в аккаунт" | Navigate to login |
| `AuthenticationFailed` | "Неверный логин или пароль" | Clear creds, show login |
| `ServerError(401)` | "Сессия истекла" | Clear creds, show login |
| `ServerError(403)` | "Доступ запрещён" | Contact admin |
| `ServerError(503)` | "Сервер недоступен" | Retry later |
| `FolderNotFound` | "Календарь не найден" | Contact admin |
| `ParseError` | "Ошибка обработки данных" | Retry |
| `NetworkError` | "Ошибка сети" | Check connection, retry |

### Error Handling Pattern (iOS)

```swift
enum AppError: LocalizedError {
    case offline
    case authRequired
    case invalidCredentials
    case accessDenied
    case serverUnavailable
    case calendarNotFound
    case parseError
    case networkError(Error)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .offline:
            return "Нет подключения к сети. Проверьте интернет-соединение."
        case .authRequired:
            return "Требуется вход в аккаунт"
        case .invalidCredentials:
            return "Неверный логин или пароль"
        case .accessDenied:
            return "Доступ запрещён. Обратитесь к администратору."
        case .serverUnavailable:
            return "Сервер временно недоступен. Попробуйте позже."
        case .calendarNotFound:
            return "Календарь не найден. Обратитесь к администратору."
        case .parseError:
            return "Ошибка обработки данных. Попробуйте ещё раз."
        case .networkError:
            return "Ошибка сети. Проверьте подключение."
        case .unknown:
            return "Произошла ошибка. Попробуйте ещё раз."
        }
    }
    
    var recoverySuggestion: RecoveryAction {
        switch self {
        case .offline, .networkError, .serverUnavailable, .parseError:
            return .retry
        case .authRequired, .invalidCredentials:
            return .login
        case .accessDenied, .calendarNotFound:
            return .contactAdmin
        case .unknown:
            return .retry
        }
    }
}

enum RecoveryAction {
    case retry
    case login
    case contactAdmin
}

// Convert EASError to AppError
extension EASError {
    var asAppError: AppError {
        switch self {
        case .offline:
            return .offline
        case .noCredentials:
            return .authRequired
        case .serverError(401, _):
            return .invalidCredentials
        case .serverError(403, _):
            return .accessDenied
        case .serverError(503, _):
            return .serverUnavailable
        case .folderNotFound:
            return .calendarNotFound
        case .parseError:
            return .parseError
        case .networkError(let error):
            return .networkError(error)
        }
    }
}
```

### Offline Mode Specification

**Behavior when offline:**

1. **Calendar Read:** Return error immediately with message "Нет подключения к сети"
2. **Create Event:** Return error immediately, do not queue
3. **Login:** Return error immediately
4. **No caching:** We do not cache events for offline viewing
5. **No retry queue:** We do not queue failed requests

**Rationale:**
- Simplicity — no complex sync state management
- Security — no sensitive data cached on device
- User expectation — corporate calendars expect real-time data

---

## 11. Security Considerations

### Credential Security

| Aspect | Implementation |
|--------|----------------|
| Storage | iOS Keychain / Android EncryptedSharedPreferences |
| Encryption | AES-256-GCM (Android), Secure Enclave (iOS) |
| Access | Require biometric/passcode (optional, recommended) |
| Backup | Disabled (kSecAttrSynchronizable = false) |
| Memory | Zero-out password after use |
| Logging | Never log credentials |

### Network Security

| Aspect | Implementation |
|--------|----------------|
| Transport | HTTPS only |
| Certificate | Validate server certificate (no pinning for Exchange) |
| Auth header | Basic Auth over TLS |
| Timeout | 30s connect, 60s read |

### Data Security

| Aspect | Implementation |
|--------|----------------|
| Calendar data | Not cached persistently |
| Sync keys | Stored in memory only |
| Event bodies | Not logged |

### Security Checklist

Before release, verify:

- [ ] Credentials only stored in Keychain/EncryptedSharedPreferences
- [ ] No credentials in logs (check all log statements)
- [ ] No credentials in crash reports
- [ ] HTTPS certificate validation enabled
- [ ] Password zeroed after creating Basic Auth header
- [ ] Biometric/passcode protection enabled (recommended)
- [ ] No backup of credentials (iCloud/Google backup disabled for cred storage)
- [ ] App Transport Security configured (iOS)
- [ ] Network security config present (Android)

---

## 12. Testing

### Unit Tests

**CredentialManager:**

```swift
class CredentialManagerTests: XCTestCase {
    
    var sut: CredentialManager!
    
    override func setUp() {
        sut = CredentialManager.shared
        try? sut.clearCredentials()
    }
    
    func testSaveAndRetrieveCredentials() throws {
        // Given
        let username = "CORP\\testuser"
        let password = "testpass123"
        let serverUrl = "https://mail.test.com"
        
        // When
        try sut.saveCredentials(username: username, password: password, serverUrl: serverUrl)
        let retrieved = try sut.getCredentials()
        
        // Then
        XCTAssertEqual(retrieved.username, username)
        XCTAssertEqual(retrieved.password, password)
        XCTAssertEqual(retrieved.serverUrl, serverUrl)
    }
    
    func testBasicAuthHeader() throws {
        // Given
        try sut.saveCredentials(
            username: "CORP\\user",
            password: "pass",
            serverUrl: "https://mail.test.com"
        )
        
        // When
        let creds = try sut.getCredentials()
        
        // Then
        // Base64("CORP\user:pass") = "Q09SUFx1c2VyOnBhc3M="
        XCTAssertEqual(creds.basicAuthHeader, "Basic Q09SUFx1c2VyOnBhc3M=")
    }
    
    func testClearCredentials() throws {
        // Given
        try sut.saveCredentials(username: "test", password: "test", serverUrl: "https://test.com")
        
        // When
        try sut.clearCredentials()
        
        // Then
        XCTAssertFalse(sut.hasCredentials())
    }
    
    func testDeviceIdPersistence() throws {
        // Given
        let deviceId1 = sut.getDeviceId()
        
        // When
        try sut.clearCredentials()
        let deviceId2 = sut.getDeviceId()
        
        // Then - device ID should persist after clear
        XCTAssertEqual(deviceId1, deviceId2)
    }
}
```

### Integration Tests

**Against Test Exchange Server:**

```swift
class EASClientIntegrationTests: XCTestCase {
    
    var sut: EASClient!
    
    override func setUp() async throws {
        sut = EASClient()
        
        // Setup test credentials (from environment or test config)
        try CredentialManager.shared.saveCredentials(
            username: ProcessInfo.processInfo.environment["TEST_EAS_USER"] ?? "",
            password: ProcessInfo.processInfo.environment["TEST_EAS_PASS"] ?? "",
            serverUrl: ProcessInfo.processInfo.environment["TEST_EAS_URL"] ?? ""
        )
    }
    
    func testConnectionWithValidCredentials() async throws {
        let result = try await sut.testConnection()
        XCTAssertTrue(result)
    }
    
    func testFolderSync() async throws {
        let folderId = try await sut.discoverCalendarFolder()
        XCTAssertFalse(folderId.isEmpty)
    }
    
    func testGetCalendarEvents() async throws {
        let events = try await sut.getCalendarEvents()
        // At least verify no crash; actual events depend on test account
        XCTAssertNotNil(events)
    }
}
```

### Manual Test Checklist

**Login Flow:**

- [ ] Successful login with valid credentials
- [ ] Error shown for invalid credentials
- [ ] Error shown for invalid server URL
- [ ] Error shown when offline
- [ ] Credentials persist after app restart
- [ ] Logout clears credentials

**Calendar:**

- [ ] Events load after login
- [ ] Event details show correctly (subject, time, location)
- [ ] Attendees list shows correctly
- [ ] Pull-to-refresh works
- [ ] Error shown when offline
- [ ] Error shown when credentials expired

**Meeting Summary:**

- [ ] Summary preview shows correctly
- [ ] Attendees pre-populated from original event
- [ ] Create sends to Exchange
- [ ] Created event appears in Outlook
- [ ] Error shown when offline

---

## Appendix A: WBXML Implementation Notes

WBXML encoding/decoding is complex. Options:

1. **Use existing library** — search for "WBXML Swift" or "WBXML Kotlin"
2. **Port from Python** — python-eas or similar
3. **Build minimal encoder** — only for commands you use

For testing, Exchange may accept plain XML with `Content-Type: text/xml` — use this for development, switch to WBXML for production.

**WBXML Code Pages for EAS:**

| Page | Namespace |
|------|-----------|
| 0 | AirSync |
| 1 | Contacts |
| 2 | Email |
| 4 | Calendar |
| 7 | FolderHierarchy |
| ... | ... |

---

## Appendix B: Exchange Admin Requirements

**For IT Admin:**

1. ActiveSync must be enabled for user mailboxes
2. Basic Auth must be enabled on ActiveSync virtual directory
3. Device ID pattern `VantaSpeech_*` should be allowed (if device restrictions exist)
4. User must have calendar access in Exchange

**PowerShell commands to verify:**

```powershell
# Check ActiveSync is enabled for user
Get-CASMailbox -Identity user@company.com | Select ActiveSyncEnabled

# Check ActiveSync virtual directory settings
Get-ActiveSyncVirtualDirectory | FL Name, *Auth*

# Check device access rules
Get-ActiveSyncDeviceAccessRule
```

---

## Appendix C: References

- [MS-ASCMD: Exchange ActiveSync Command Reference](https://docs.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-ascmd)
- [MS-ASCAL: Exchange ActiveSync Calendar Class](https://docs.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-ascal)
- [MS-ASWBXML: WAP Binary XML](https://docs.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-aswbxml)
- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain_services)
- [Android EncryptedSharedPreferences](https://developer.android.com/reference/androidx/security/crypto/EncryptedSharedPreferences)

---

*Document maintained by Vanta Speech development team. Last updated: January 2026.*
