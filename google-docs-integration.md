# Google Docs Integration for Vanta Speech (iOS, No Backend)

## Overview

Интеграция позволяет сохранять транскрипции встреч из Vanta Speech напрямую в Google Docs пользователя. Архитектура — полностью клиентская, без серверной части.

**Что делает интеграция:**
- Авторизация через Google аккаунт пользователя
- Создание нового Google Doc с названием встречи
- Добавление summary в тело документа
- Опционально: выбор папки для сохранения

**Tech stack:**
- Google Sign-In SDK 8.x
- Google Docs API v1
- Google Drive API v3 (для работы с папками)
- iOS 15+, Swift 5.9+

---

## 1. Настройка Google Cloud Console

### 1.1 Создание проекта

1. Перейди в [Google Cloud Console](https://console.cloud.google.com/)
2. Create Project → Name: `Vanta Speech`
3. Запомни Project ID

### 1.2 Включение APIs

В разделе **APIs & Services → Library** включи:
- Google Docs API
- Google Drive API

### 1.3 Настройка OAuth Consent Screen

**APIs & Services → OAuth consent screen:**

| Поле | Значение |
|------|----------|
| User Type | External |
| App name | Vanta Speech |
| User support email | твой email |
| App logo | 512x512 png |
| App domain | vantaspeech.app (если есть) |
| Developer contact | твой email |

**Scopes** — добавь:
```
https://www.googleapis.com/auth/drive.file
https://www.googleapis.com/auth/documents
```

> ⚠️ `auth/documents` — sensitive scope, требует верификации для production. На этапе разработки работает для тестовых пользователей (до 100 человек).

### 1.4 Создание OAuth Client ID

**APIs & Services → Credentials → Create Credentials → OAuth client ID:**

| Поле | Значение |
|------|----------|
| Application type | iOS |
| Name | Vanta Speech iOS |
| Bundle ID | com.yourcompany.vantaspeech |

После создания скачай `GoogleService-Info.plist` — он понадобится в проекте.

**Важно:** Запиши `CLIENT_ID` — формат: `xxx.apps.googleusercontent.com`

### 1.5 Добавление тестовых пользователей

Пока приложение в режиме "Testing", авторизоваться могут только добавленные пользователи.

**OAuth consent screen → Test users → Add users**

---

## 2. Настройка Xcode проекта

### 2.1 Добавление Google Sign-In SDK

**Swift Package Manager:**

```
File → Add Package Dependencies
URL: https://github.com/google/GoogleSignIn-iOS
Version: 8.0.0+
```

Выбери продукты:
- GoogleSignIn
- GoogleSignInSwift (для SwiftUI)

### 2.2 Добавление GoogleService-Info.plist

Перетащи скачанный `GoogleService-Info.plist` в корень проекта. Убедись что он добавлен в target.

### 2.3 Настройка URL Scheme

**Info.plist** — добавь URL scheme для OAuth callback:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

Замени `YOUR_CLIENT_ID` на часть CLIENT_ID до `.apps.googleusercontent.com`.

Пример: если CLIENT_ID = `123456789.apps.googleusercontent.com`, то scheme = `com.googleusercontent.apps.123456789`

### 2.4 Настройка Info.plist для Google Sign-In

```xml
<key>GIDClientID</key>
<string>YOUR_FULL_CLIENT_ID.apps.googleusercontent.com</string>
```

---

## 3. Реализация OAuth авторизации

### 3.1 AuthManager — синглтон для управления авторизацией

```swift
import GoogleSignIn
import Foundation

final class GoogleAuthManager: ObservableObject {
    static let shared = GoogleAuthManager()
    
    @Published var isSignedIn = false
    @Published var currentUser: GIDGoogleUser?
    @Published var error: Error?
    
    private let scopes = [
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/documents"
    ]
    
    private init() {
        restorePreviousSignIn()
    }
    
    // MARK: - Restore Session
    
    func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            DispatchQueue.main.async {
                if let user = user {
                    self?.handleSignIn(user: user)
                } else {
                    self?.isSignedIn = false
                    self?.currentUser = nil
                }
            }
        }
    }
    
    // MARK: - Sign In
    
    func signIn(presenting viewController: UIViewController) {
        let config = GIDConfiguration(clientID: getClientID())
        
        GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController,
            hint: nil,
            additionalScopes: scopes
        ) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error
                    return
                }
                
                guard let user = result?.user else { return }
                self?.handleSignIn(user: user)
            }
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        DispatchQueue.main.async {
            self.isSignedIn = false
            self.currentUser = nil
        }
    }
    
    // MARK: - Get Valid Access Token
    
    func getValidAccessToken() async throws -> String {
        guard let user = currentUser else {
            throw GoogleAuthError.notSignedIn
        }
        
        // Проверяем, не истёк ли токен
        if let expirationDate = user.accessToken.expirationDate,
           expirationDate < Date() {
            // Refresh token
            return try await withCheckedThrowingContinuation { continuation in
                user.refreshTokensIfNeeded { user, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let token = user?.accessToken.tokenString {
                        continuation.resume(returning: token)
                    } else {
                        continuation.resume(throwing: GoogleAuthError.tokenRefreshFailed)
                    }
                }
            }
        }
        
        return user.accessToken.tokenString
    }
    
    // MARK: - Private
    
    private func handleSignIn(user: GIDGoogleUser) {
        // Проверяем, что все нужные scopes granted
        let grantedScopes = user.grantedScopes ?? []
        let hasAllScopes = scopes.allSatisfy { grantedScopes.contains($0) }
        
        if hasAllScopes {
            self.currentUser = user
            self.isSignedIn = true
        } else {
            // Нужно запросить дополнительные scopes
            self.error = GoogleAuthError.insufficientScopes
        }
    }
    
    private func getClientID() -> String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String else {
            fatalError("GoogleService-Info.plist not found or CLIENT_ID missing")
        }
        return clientID
    }
}

enum GoogleAuthError: LocalizedError {
    case notSignedIn
    case tokenRefreshFailed
    case insufficientScopes
    
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "User is not signed in to Google"
        case .tokenRefreshFailed: return "Failed to refresh access token"
        case .insufficientScopes: return "App doesn't have required permissions"
        }
    }
}
```

### 3.2 Обработка URL callback в AppDelegate / SceneDelegate

**Для UIKit (AppDelegate):**

```swift
import GoogleSignIn

func application(_ app: UIApplication, 
                 open url: URL,
                 options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    return GIDSignIn.sharedInstance.handle(url)
}
```

**Для SwiftUI (App struct):**

```swift
import SwiftUI
import GoogleSignIn

@main
struct VantaSpeechApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
```

### 3.3 SwiftUI View для Sign In

```swift
import SwiftUI
import GoogleSignInSwift

struct GoogleSignInView: View {
    @StateObject private var authManager = GoogleAuthManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            if authManager.isSignedIn {
                VStack {
                    Text("Signed in as:")
                    Text(authManager.currentUser?.profile?.email ?? "Unknown")
                        .font(.headline)
                    
                    Button("Sign Out") {
                        authManager.signOut()
                    }
                    .foregroundColor(.red)
                }
            } else {
                GoogleSignInButton(action: handleSignIn)
                    .frame(width: 280, height: 50)
            }
            
            if let error = authManager.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
    
    private func handleSignIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        authManager.signIn(presenting: rootVC)
    }
}
```

---

## 4. Google Docs API Client

### 4.1 Модели данных

```swift
import Foundation

// MARK: - Create Document Response

struct GoogleDocument: Codable {
    let documentId: String
    let title: String
    let revisionId: String?
}

// MARK: - Batch Update Request

struct BatchUpdateRequest: Codable {
    let requests: [DocumentRequest]
}

struct DocumentRequest: Codable {
    var insertText: InsertTextRequest?
    var updateParagraphStyle: UpdateParagraphStyleRequest?
}

struct InsertTextRequest: Codable {
    let location: Location
    let text: String
}

struct Location: Codable {
    let index: Int
}

struct UpdateParagraphStyleRequest: Codable {
    let range: Range
    let paragraphStyle: ParagraphStyle
    let fields: String
}

struct Range: Codable {
    let startIndex: Int
    let endIndex: Int
}

struct ParagraphStyle: Codable {
    let namedStyleType: String // TITLE, HEADING_1, HEADING_2, NORMAL_TEXT
}

// MARK: - Error Response

struct GoogleAPIError: Codable {
    let error: GoogleErrorDetails
}

struct GoogleErrorDetails: Codable {
    let code: Int
    let message: String
    let status: String?
}
```

### 4.2 GoogleDocsService

```swift
import Foundation

final class GoogleDocsService {
    private let baseURL = "https://docs.googleapis.com/v1/documents"
    private let authManager = GoogleAuthManager.shared
    
    enum ServiceError: LocalizedError {
        case invalidResponse
        case apiError(code: Int, message: String)
        case encodingError
        
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from Google API"
            case .apiError(let code, let message): return "Google API error \(code): \(message)"
            case .encodingError: return "Failed to encode request"
            }
        }
    }
    
    // MARK: - Create Document with Content
    
    /// Создаёт новый Google Doc с названием встречи и summary
    /// - Parameters:
    ///   - title: Название встречи (станет названием документа)
    ///   - summary: Текст summary для добавления в документ
    ///   - folderId: ID папки в Google Drive (опционально)
    /// - Returns: URL созданного документа
    func createMeetingDocument(
        title: String,
        summary: String,
        folderId: String? = nil
    ) async throws -> URL {
        
        let accessToken = try await authManager.getValidAccessToken()
        
        // Step 1: Create empty document
        let document = try await createDocument(title: title, accessToken: accessToken)
        
        // Step 2: Add content
        try await addContent(
            documentId: document.documentId,
            summary: summary,
            accessToken: accessToken
        )
        
        // Step 3: Move to folder (if specified)
        if let folderId = folderId {
            try await moveToFolder(
                documentId: document.documentId,
                folderId: folderId,
                accessToken: accessToken
            )
        }
        
        // Return document URL
        let urlString = "https://docs.google.com/document/d/\(document.documentId)/edit"
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidResponse
        }
        
        return url
    }
    
    // MARK: - Private: Create Empty Document
    
    private func createDocument(title: String, accessToken: String) async throws -> GoogleDocument {
        guard let url = URL(string: baseURL) else {
            throw ServiceError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["title": title]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try JSONDecoder().decode(GoogleDocument.self, from: data)
    }
    
    // MARK: - Private: Add Content via BatchUpdate
    
    private func addContent(
        documentId: String,
        summary: String,
        accessToken: String
    ) async throws {
        
        guard let url = URL(string: "\(baseURL)/\(documentId):batchUpdate") else {
            throw ServiceError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Формируем контент
        let headerText = "Meeting Summary\n\n"
        let fullText = headerText + summary
        
        let batchRequest = BatchUpdateRequest(requests: [
            // Insert all text first
            DocumentRequest(
                insertText: InsertTextRequest(
                    location: Location(index: 1),
                    text: fullText
                )
            ),
            // Style the header as HEADING_1
            DocumentRequest(
                updateParagraphStyle: UpdateParagraphStyleRequest(
                    range: Range(startIndex: 1, endIndex: headerText.count),
                    paragraphStyle: ParagraphStyle(namedStyleType: "HEADING_1"),
                    fields: "namedStyleType"
                )
            )
        ])
        
        request.httpBody = try JSONEncoder().encode(batchRequest)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }
    
    // MARK: - Private: Move to Folder (Drive API)
    
    private func moveToFolder(
        documentId: String,
        folderId: String,
        accessToken: String
    ) async throws {
        
        // Сначала получаем текущих родителей
        let fileURL = URL(string: "https://www.googleapis.com/drive/v3/files/\(documentId)?fields=parents")!
        
        var getRequest = URLRequest(url: fileURL)
        getRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)
        try validateResponse(getResponse, data: getData)
        
        struct FileParents: Codable {
            let parents: [String]?
        }
        let parents = try JSONDecoder().decode(FileParents.self, from: getData)
        let previousParents = parents.parents?.joined(separator: ",") ?? ""
        
        // Перемещаем файл
        var moveURLComponents = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(documentId)")!
        moveURLComponents.queryItems = [
            URLQueryItem(name: "addParents", value: folderId),
            URLQueryItem(name: "removeParents", value: previousParents),
            URLQueryItem(name: "fields", value: "id,parents")
        ]
        
        var moveRequest = URLRequest(url: moveURLComponents.url!)
        moveRequest.httpMethod = "PATCH"
        moveRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (_, moveResponse) = try await URLSession.shared.data(for: moveRequest)
        try validateResponse(moveResponse, data: nil)
    }
    
    // MARK: - Private: Validate Response
    
    private func validateResponse(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let data = data,
               let apiError = try? JSONDecoder().decode(GoogleAPIError.self, from: data) {
                throw ServiceError.apiError(
                    code: apiError.error.code,
                    message: apiError.error.message
                )
            }
            throw ServiceError.apiError(code: httpResponse.statusCode, message: "Unknown error")
        }
    }
}
```

---

## 5. Google Drive API — выбор папки

### 5.1 GoogleDriveService

```swift
import Foundation

final class GoogleDriveService {
    private let baseURL = "https://www.googleapis.com/drive/v3"
    private let authManager = GoogleAuthManager.shared
    
    struct Folder: Identifiable, Codable {
        let id: String
        let name: String
    }
    
    struct FolderListResponse: Codable {
        let files: [Folder]
        let nextPageToken: String?
    }
    
    /// Получает список папок пользователя
    /// - Parameter parentId: ID родительской папки. "root" для корня Drive
    func listFolders(parentId: String = "root") async throws -> [Folder] {
        let accessToken = try await authManager.getValidAccessToken()
        
        var components = URLComponents(string: "\(baseURL)/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "mimeType='application/vnd.google-apps.folder' and '\(parentId)' in parents and trashed=false"),
            URLQueryItem(name: "fields", value: "files(id,name),nextPageToken"),
            URLQueryItem(name: "orderBy", value: "name"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleDocsService.ServiceError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(FolderListResponse.self, from: data)
        return result.files
    }
    
    /// Создаёт новую папку
    func createFolder(name: String, parentId: String = "root") async throws -> Folder {
        let accessToken = try await authManager.getValidAccessToken()
        
        let url = URL(string: "\(baseURL)/files")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": [parentId]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleDocsService.ServiceError.invalidResponse
        }
        
        return try JSONDecoder().decode(Folder.self, from: data)
    }
}
```

### 5.2 FolderPickerView

```swift
import SwiftUI

struct FolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FolderPickerViewModel()
    
    let onSelect: (GoogleDriveService.Folder?) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                // Root option
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    Label("My Drive (root)", systemImage: "folder")
                }
                
                // Folders
                ForEach(viewModel.folders) { folder in
                    Button {
                        onSelect(folder)
                        dismiss()
                    } label: {
                        Label(folder.name, systemImage: "folder.fill")
                    }
                }
            }
            .navigationTitle("Select Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
        .task {
            await viewModel.loadFolders()
        }
    }
}

@MainActor
final class FolderPickerViewModel: ObservableObject {
    @Published var folders: [GoogleDriveService.Folder] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    
    private let driveService = GoogleDriveService()
    
    func loadFolders() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            folders = try await driveService.listFolders()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
```

---

## 6. Интеграция в Vanta Speech

### 6.1 ExportService — точка входа для экспорта

```swift
import Foundation

final class ExportService {
    static let shared = ExportService()
    
    private let docsService = GoogleDocsService()
    
    struct ExportResult {
        let url: URL
        let provider: String
    }
    
    /// Экспортирует meeting в Google Docs
    /// - Parameters:
    ///   - meeting: Объект встречи с названием и транскрипцией
    ///   - folderId: ID папки (опционально)
    func exportToGoogleDocs(
        meeting: Meeting,
        folderId: String? = nil
    ) async throws -> ExportResult {
        
        let documentURL = try await docsService.createMeetingDocument(
            title: meeting.title,
            summary: meeting.summary,
            folderId: folderId
        )
        
        return ExportResult(url: documentURL, provider: "Google Docs")
    }
}

// Пример модели Meeting
struct Meeting {
    let id: UUID
    let title: String
    let summary: String
    let date: Date
    let duration: TimeInterval
}
```

### 6.2 ExportView — UI для экспорта

```swift
import SwiftUI

struct ExportView: View {
    let meeting: Meeting
    
    @StateObject private var authManager = GoogleAuthManager.shared
    @State private var selectedFolder: GoogleDriveService.Folder?
    @State private var showFolderPicker = false
    @State private var isExporting = false
    @State private var exportResult: ExportService.ExportResult?
    @State private var exportError: Error?
    
    var body: some View {
        List {
            // Google section
            Section {
                if authManager.isSignedIn {
                    // Folder selection
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack {
                            Text("Folder")
                            Spacer()
                            Text(selectedFolder?.name ?? "My Drive")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                    
                    // Export button
                    Button {
                        Task { await exportToGoogle() }
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Export to Google Docs")
                            Spacer()
                            Image(systemName: "doc.text")
                        }
                    }
                    .disabled(isExporting)
                    
                } else {
                    Button {
                        signInToGoogle()
                    } label: {
                        HStack {
                            Image("google-logo") // Add asset
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text("Connect Google Account")
                        }
                    }
                }
            } header: {
                Text("Google Docs")
            } footer: {
                if authManager.isSignedIn {
                    Text("Signed in as \(authManager.currentUser?.profile?.email ?? "")")
                }
            }
            
            // Success result
            if let result = exportResult {
                Section("Exported") {
                    Link(destination: result.url) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("Open in \(result.provider)")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                    }
                }
            }
        }
        .navigationTitle("Export Meeting")
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView { folder in
                selectedFolder = folder
            }
        }
        .alert("Export Failed", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError?.localizedDescription ?? "Unknown error")
        }
    }
    
    private func signInToGoogle() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        authManager.signIn(presenting: rootVC)
    }
    
    private func exportToGoogle() async {
        isExporting = true
        exportError = nil
        
        do {
            exportResult = try await ExportService.shared.exportToGoogleDocs(
                meeting: meeting,
                folderId: selectedFolder?.id
            )
        } catch {
            exportError = error
        }
        
        isExporting = false
    }
}
```

---

## 7. Rate Limits и обработка ошибок

### 7.1 Лимиты Google APIs

| API | Лимит | Примечание |
|-----|-------|------------|
| Docs API write | 60/min per user | Создание + batchUpdate = 2 запроса |
| Drive API | 3 writes/sec per user | Жёсткий лимит |
| Project quota | 1,000,000/day | Достаточно для большинства приложений |

### 7.2 Retry Logic

```swift
extension GoogleDocsService {
    
    func executeWithRetry<T>(
        maxAttempts: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch let error as ServiceError {
                lastError = error
                
                // Retry only on rate limit errors (429)
                if case .apiError(let code, _) = error, code == 429 {
                    let delay = Double(attempt) * 2.0 // Exponential backoff
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                throw error
            }
        }
        
        throw lastError ?? ServiceError.invalidResponse
    }
}
```

---

## 8. Testing

### 8.1 Unit Tests

```swift
import XCTest
@testable import VantaSpeech

final class GoogleDocsServiceTests: XCTestCase {
    
    func testBatchRequestEncoding() throws {
        let request = BatchUpdateRequest(requests: [
            DocumentRequest(
                insertText: InsertTextRequest(
                    location: Location(index: 1),
                    text: "Test content"
                )
            )
        ])
        
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertNotNil(json?["requests"])
    }
}
```

### 8.2 Manual Testing Checklist

- [ ] Sign in с новым Google аккаунтом
- [ ] Sign in с существующей сессией (restore)
- [ ] Sign out и повторный sign in
- [ ] Создание документа в root
- [ ] Создание документа в папке
- [ ] Token refresh после истечения (через ~1 час)
- [ ] Обработка отсутствия интернета
- [ ] Обработка отозванных permissions

---

## 9. App Store Submission

### 9.1 Sign in with Apple

Apple требует Sign in with Apple если есть любой сторонний OAuth. Добавь как альтернативу.

### 9.2 Privacy Policy

Обязательно укажи:
- Какие данные собираешь (email, имя)
- Что делаешь с токенами (храним локально в Keychain)
- Какие scopes запрашиваешь и зачем

### 9.3 OAuth Verification

Для публикации в App Store нужно пройти Google OAuth verification:

1. Google Cloud Console → OAuth consent screen → Publish app
2. Заполни форму верификации
3. Загрузи demo video использования OAuth
4. Ожидание: 2-4 недели

---

## 10. Troubleshooting

| Проблема | Причина | Решение |
|----------|---------|---------|
| `invalid_client` | Неправильный Bundle ID | Проверь соответствие в Cloud Console |
| `access_denied` | Пользователь не в test users | Добавь в OAuth consent screen |
| `insufficient_scopes` | Scopes не были granted | Запроси через `additionalScopes` |
| Redirect не работает | Неправильный URL scheme | Проверь Info.plist |
| 403 on API calls | API не включен | Включи в APIs & Services → Library |

---

## Appendix: Полный список файлов

```
VantaSpeech/
├── Services/
│   ├── Auth/
│   │   └── GoogleAuthManager.swift
│   ├── Export/
│   │   ├── ExportService.swift
│   │   ├── GoogleDocsService.swift
│   │   └── GoogleDriveService.swift
│   └── Models/
│       └── GoogleModels.swift
├── Views/
│   ├── Export/
│   │   ├── ExportView.swift
│   │   └── FolderPickerView.swift
│   └── Auth/
│       └── GoogleSignInView.swift
├── Resources/
│   └── GoogleService-Info.plist
└── Info.plist (с URL schemes)
```
