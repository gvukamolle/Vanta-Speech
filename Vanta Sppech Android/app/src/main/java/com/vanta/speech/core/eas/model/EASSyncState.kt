package com.vanta.speech.core.eas.model

import kotlinx.serialization.Serializable

/**
 * Synchronization state for EAS operations
 */
@Serializable
data class EASSyncState(
    /** Sync key for folder hierarchy (FolderSync) */
    val folderSyncKey: String = "0",

    /** Calendar folder ID discovered via FolderSync */
    val calendarFolderId: String? = null,

    /** Sync key for calendar items (Sync command) */
    val calendarSyncKey: String = "0",

    /** Last successful sync timestamp (epoch millis) */
    val lastSyncDate: Long? = null
) {
    companion object {
        val INITIAL = EASSyncState()
    }

    /** Whether initial folder sync has been completed */
    val hasDiscoveredCalendar: Boolean
        get() = calendarFolderId != null

    /** Whether this is the first sync (syncKey = "0") */
    val isInitialSync: Boolean
        get() = calendarSyncKey == "0"
}

/**
 * EAS folder types from FolderSync response
 */
enum class EASFolderType(val value: Int) {
    USER_CREATED_GENERIC(1),
    DEFAULT_INBOX(2),
    DEFAULT_DRAFTS(3),
    DEFAULT_DELETED_ITEMS(4),
    DEFAULT_SENT_ITEMS(5),
    DEFAULT_OUTBOX(6),
    DEFAULT_TASKS(7),
    DEFAULT_CALENDAR(8),     // This is what we're looking for
    DEFAULT_CONTACTS(9),
    DEFAULT_NOTES(10),
    DEFAULT_JOURNAL(11),
    USER_CREATED_MAIL(12),
    USER_CREATED_CALENDAR(13),
    USER_CREATED_CONTACTS(14),
    USER_CREATED_TASKS(15),
    USER_CREATED_JOURNAL(16),
    USER_CREATED_NOTES(17),
    UNKNOWN(18),
    RECIPIENT_INFO_CACHE(19);

    /** Whether this folder type is a calendar */
    val isCalendar: Boolean
        get() = this == DEFAULT_CALENDAR || this == USER_CREATED_CALENDAR

    companion object {
        fun fromValue(value: Int): EASFolderType {
            return entries.find { it.value == value } ?: UNKNOWN
        }
    }
}

/**
 * Folder information from FolderSync response
 */
@Serializable
data class EASFolder(
    /** Server-assigned folder ID */
    val serverId: String,

    /** Parent folder ID (or "0" for root) */
    val parentId: String,

    /** Display name of the folder */
    val displayName: String,

    /** Folder type value */
    val typeValue: Int
) {
    /** Folder type enum */
    val type: EASFolderType
        get() = EASFolderType.fromValue(typeValue)

    /** Whether this is a calendar folder */
    val isCalendar: Boolean
        get() = type.isCalendar
}
