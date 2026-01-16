import Foundation

/// Synchronization state for EAS operations
struct EASSyncState: Codable, Equatable {
    /// Sync key for folder hierarchy (FolderSync)
    var folderSyncKey: String

    /// Calendar folder ID discovered via FolderSync
    var calendarFolderId: String?

    /// Sync key for calendar items (Sync command)
    var calendarSyncKey: String

    /// Last successful sync timestamp
    var lastSyncDate: Date?

    /// Policy key from Provision command (required by some servers)
    var policyKey: String?

    // MARK: - Initialization

    /// Initial state for first sync
    static var initial: EASSyncState {
        EASSyncState(
            folderSyncKey: "0",
            calendarFolderId: nil,
            calendarSyncKey: "0",
            lastSyncDate: nil,
            policyKey: nil
        )
    }

    /// Whether initial folder sync has been completed
    var hasDiscoveredCalendar: Bool {
        calendarFolderId != nil
    }

    /// Whether this is the first sync (syncKey = "0")
    var isInitialSync: Bool {
        calendarSyncKey == "0"
    }

    /// Whether device has been provisioned
    var isProvisioned: Bool {
        policyKey != nil
    }
}

/// EAS folder types from FolderSync response
enum EASFolderType: Int, Codable {
    case userCreatedGeneric = 1
    case defaultInbox = 2
    case defaultDrafts = 3
    case defaultDeletedItems = 4
    case defaultSentItems = 5
    case defaultOutbox = 6
    case defaultTasks = 7
    case defaultCalendar = 8     // This is what we're looking for
    case defaultContacts = 9
    case defaultNotes = 10
    case defaultJournal = 11
    case userCreatedMail = 12
    case userCreatedCalendar = 13
    case userCreatedContacts = 14
    case userCreatedTasks = 15
    case userCreatedJournal = 16
    case userCreatedNotes = 17
    case unknown = 18
    case recipientInfoCache = 19

    /// Whether this folder type is a calendar
    var isCalendar: Bool {
        self == .defaultCalendar || self == .userCreatedCalendar
    }
}

/// Folder information from FolderSync response
struct EASFolder: Codable, Equatable, Identifiable {
    /// Server-assigned folder ID
    let serverId: String

    /// Parent folder ID (or "0" for root)
    let parentId: String

    /// Display name of the folder
    let displayName: String

    /// Folder type
    let type: EASFolderType

    var id: String { serverId }

    /// Whether this is a calendar folder
    var isCalendar: Bool {
        type.isCalendar
    }
}
