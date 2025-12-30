import Foundation
import Combine
import UIKit

/// High-level coordinator for Google Docs integration
@MainActor
final class GoogleDocsManager: ObservableObject {
    static let shared = GoogleDocsManager()

    // MARK: - Published State

    @Published private(set) var isSignedIn = false
    @Published private(set) var userEmail: String?
    @Published private(set) var userName: String?
    @Published private(set) var lastError: Error?

    @Published var selectedFolder: DriveFolder?
    @Published private(set) var availableFolders: [DriveFolder] = []
    @Published private(set) var isLoadingFolders = false

    // MARK: - Private

    private let authManager = GoogleAuthManager.shared
    private let docsService: GoogleDocsService
    private let driveService: GoogleDriveService
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.docsService = GoogleDocsService(authManager: authManager)
        self.driveService = GoogleDriveService(authManager: authManager)
        setupBindings()
    }

    // MARK: - Authentication

    /// Sign in with Google
    func signIn(from viewController: UIViewController) async -> Bool {
        lastError = nil

        let success = await authManager.signIn(from: viewController)

        if success {
            await loadFolders()
        } else {
            lastError = authManager.lastError
        }

        return success
    }

    /// Sign out
    func signOut() {
        authManager.signOut()
        selectedFolder = nil
        availableFolders = []
    }

    /// Handle OAuth URL callback
    func handleURL(_ url: URL) -> Bool {
        authManager.handleURL(url)
    }

    // MARK: - Folder Management

    /// Load available folders from Google Drive
    func loadFolders() async {
        guard isSignedIn else { return }

        isLoadingFolders = true
        lastError = nil

        do {
            let folders = try await driveService.listFolders()
            availableFolders = folders
            debugLog("Loaded \(folders.count) folders", module: "GoogleDocsManager")
        } catch {
            lastError = error
            debugLog("Failed to load folders: \(error.localizedDescription)", module: "GoogleDocsManager", level: .error)
            debugCaptureError(error, context: "Loading Google Drive folders")
        }

        isLoadingFolders = false
    }

    /// Select a folder for saving documents
    func selectFolder(_ folder: DriveFolder?) {
        selectedFolder = folder
        // Persist selection
        UserDefaults.standard.set(folder?.id, forKey: "google_docs_selected_folder_id")
        UserDefaults.standard.set(folder?.name, forKey: "google_docs_selected_folder_name")
    }

    // MARK: - Document Creation

    /// Create a meeting summary document
    /// - Parameters:
    ///   - title: Meeting title
    ///   - summary: AI-generated summary
    ///   - transcription: Optional full transcription
    ///   - date: Meeting date
    /// - Returns: URL to the created document
    func createMeetingSummary(
        title: String,
        summary: String,
        transcription: String? = nil,
        date: Date = Date()
    ) async throws -> URL {
        guard isSignedIn else {
            throw GoogleDocsError.notSignedIn
        }

        lastError = nil

        do {
            // Create document with content
            let document = try await docsService.createMeetingSummaryDocument(
                title: title,
                summary: summary,
                transcription: transcription,
                date: date
            )

            // Move to selected folder if any
            if let folder = selectedFolder {
                try await driveService.moveToFolder(
                    fileId: document.documentId,
                    folderId: folder.id
                )
                debugLog("Moved document to folder: \(folder.name)", module: "GoogleDocsManager")
            }

            guard let url = document.url else {
                throw GoogleDocsError.documentCreationFailed("Invalid document URL")
            }

            debugLog("Created document: \(title)", module: "GoogleDocsManager")
            return url

        } catch {
            lastError = error
            debugCaptureError(error, context: "Creating Google Doc with markdown")
            throw error
        }
    }

    /// Create a simple document
    func createDocument(title: String, content: String) async throws -> URL {
        guard isSignedIn else {
            throw GoogleDocsError.notSignedIn
        }

        do {
            let document = try await docsService.createDocument(title: title)

            if !content.isEmpty {
                try await docsService.insertText(
                    documentId: document.documentId,
                    text: content
                )
            }

            if let folder = selectedFolder {
                try await driveService.moveToFolder(
                    fileId: document.documentId,
                    folderId: folder.id
                )
            }

            guard let url = document.url else {
                throw GoogleDocsError.documentCreationFailed("Invalid document URL")
            }

            return url

        } catch {
            lastError = error
            debugCaptureError(error, context: "Creating Google Doc")
            throw error
        }
    }

    // MARK: - Private

    private func setupBindings() {
        authManager.$isSignedIn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSignedIn in
                self?.isSignedIn = isSignedIn
            }
            .store(in: &cancellables)

        authManager.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.userEmail = user?.email
                self?.userName = user?.displayName
            }
            .store(in: &cancellables)

        // Restore selected folder
        if let folderId = UserDefaults.standard.string(forKey: "google_docs_selected_folder_id"),
           let folderName = UserDefaults.standard.string(forKey: "google_docs_selected_folder_name") {
            selectedFolder = DriveFolder(
                id: folderId,
                name: folderName,
                mimeType: nil,
                iconLink: nil,
                modifiedTime: nil
            )
        }
    }
}
