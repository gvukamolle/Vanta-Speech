import Foundation

// MARK: - WBXML Constants

/// WBXML token types
enum WBXMLToken: UInt8 {
    case switchPage = 0x00
    case end = 0x01
    case entity = 0x02
    case strI = 0x03      // Inline string
    case literal = 0x04
    case extI0 = 0x40
    case extI1 = 0x41
    case extI2 = 0x42
    case pi = 0x43
    case literalC = 0x44
    case extT0 = 0x80
    case extT1 = 0x81
    case extT2 = 0x82
    case strT = 0x83      // String table reference
    case literalA = 0x84
    case extO = 0xC0
    case ext1 = 0xC1
    case ext2 = 0xC2
    case opaque = 0xC3    // Opaque data
    case literalAC = 0xC4
}

/// Mask for checking if tag has content
let WBXML_HAS_CONTENT: UInt8 = 0x40
/// Mask for checking if tag has attributes
let WBXML_HAS_ATTRIBUTES: UInt8 = 0x80
/// Mask for extracting tag value
let WBXML_TAG_MASK: UInt8 = 0x3F

// MARK: - Code Page Definitions

/// EAS Code Pages
enum EASCodePage: UInt8 {
    case airSync = 0
    case contacts = 1
    case email = 2
    case airNotify = 3
    case calendar = 4
    case move = 5
    case getItemEstimate = 6
    case folderHierarchy = 7
    case meetingResponse = 8
    case tasks = 9
    case resolveRecipients = 10
    case validateCert = 11
    case contacts2 = 12
    case ping = 13
    case provision = 14
    case search = 15
    case gal = 16
    case airSyncBase = 17
    case settings = 18  // DeviceInformation is here
    case documentLibrary = 19
    case itemOperations = 20
    case composeEmail = 21
    case email2 = 22
    case notes = 23
    case rightsManagement = 24
}

// MARK: - Tag Definitions

/// AirSync namespace (Code Page 0)
let airSyncTags: [UInt8: String] = [
    0x05: "Sync",
    0x06: "Responses",
    0x07: "Add",
    0x08: "Change",
    0x09: "Delete",
    0x0A: "Fetch",
    0x0B: "SyncKey",
    0x0C: "ClientId",
    0x0D: "ServerId",
    0x0E: "Status",
    0x0F: "Collection",
    0x10: "Class",
    0x11: "Version",
    0x12: "CollectionId",
    0x13: "GetChanges",
    0x14: "MoreAvailable",
    0x15: "WindowSize",
    0x16: "Commands",
    0x17: "Options",
    0x18: "FilterType",
    0x19: "Truncation",
    0x1A: "RTFTruncation",
    0x1B: "Conflict",
    0x1C: "Collections",
    0x1D: "ApplicationData",
    0x1E: "DeletesAsMoves",
    0x1F: "NotifyGUID",
    0x20: "Supported",
    0x21: "SoftDelete",
    0x22: "MIMESupport",
    0x23: "MIMETruncation",
    0x24: "Wait",
    0x25: "Limit",
    0x26: "Partial",
    0x27: "ConversationMode",
    0x28: "MaxItems",
    0x29: "HeartbeatInterval",
]

/// Calendar namespace (Code Page 4)
let calendarTags: [UInt8: String] = [
    0x05: "TimeZone",
    0x06: "AllDayEvent",
    0x07: "Attendees",
    0x08: "Attendee",
    0x09: "Email",
    0x0A: "Name",
    0x0B: "Body",
    0x0C: "BodyTruncated",
    0x0D: "BusyStatus",
    0x0E: "Categories",
    0x0F: "Category",
    0x10: "CompressedRTF",
    0x11: "DtStamp",
    0x12: "EndTime",
    0x13: "Exception",
    0x14: "Exceptions",
    0x15: "Deleted",
    0x16: "ExceptionStartTime",
    0x17: "Location",
    0x18: "MeetingStatus",
    0x19: "OrganizerEmail",
    0x1A: "OrganizerName",
    0x1B: "Recurrence",
    0x1C: "Type",
    0x1D: "Until",
    0x1E: "Occurrences",
    0x1F: "Interval",
    0x20: "DayOfWeek",
    0x21: "DayOfMonth",
    0x22: "WeekOfMonth",
    0x23: "MonthOfYear",
    0x24: "Reminder",
    0x25: "Sensitivity",
    0x26: "Subject",
    0x27: "StartTime",
    0x28: "UID",
    0x29: "AttendeeStatus",
    0x2A: "AttendeeType",
    0x2B: "DisallowNewTimeProposal",
    0x2C: "ResponseRequested",
    0x2D: "AppointmentReplyTime",
    0x2E: "ResponseType",
    0x2F: "CalendarType",
    0x30: "IsLeapMonth",
    0x31: "FirstDayOfWeek",
    0x32: "OnlineMeetingConfLink",
    0x33: "OnlineMeetingExternalLink",
    0x34: "ClientUid",
]

/// FolderHierarchy namespace (Code Page 7)
let folderHierarchyTags: [UInt8: String] = [
    0x05: "Folders",
    0x06: "Folder",
    0x07: "DisplayName",
    0x08: "ServerId",
    0x09: "ParentId",
    0x0A: "Type",
    0x0B: "Response",
    0x0C: "Status",
    0x0D: "ContentClass",
    0x0E: "Changes",
    0x0F: "Add",
    0x10: "Delete",
    0x11: "Update",
    0x12: "SyncKey",
    0x13: "FolderCreate",
    0x14: "FolderDelete",
    0x15: "FolderUpdate",
    0x16: "FolderSync",
    0x17: "Count",
]

/// AirSyncBase namespace (Code Page 17)
let airSyncBaseTags: [UInt8: String] = [
    0x05: "BodyPreference",
    0x06: "Type",
    0x07: "TruncationSize",
    0x08: "AllOrNone",
    0x09: "Reserved",
    0x0A: "Body",
    0x0B: "Data",
    0x0C: "EstimatedDataSize",
    0x0D: "Truncated",
    0x0E: "Attachments",
    0x0F: "Attachment",
    0x10: "DisplayName",
    0x11: "FileReference",
    0x12: "Method",
    0x13: "ContentId",
    0x14: "ContentLocation",
    0x15: "IsInline",
    0x16: "NativeBodyType",
    0x17: "ContentType",
    0x18: "Preview",
    0x19: "BodyPartPreference",
    0x1A: "BodyPart",
    0x1B: "Status",
]

/// Provision namespace (Code Page 14)
let provisionTags: [UInt8: String] = [
    0x05: "Provision",
    0x06: "Policies",
    0x07: "Policy",
    0x08: "PolicyType",
    0x09: "PolicyKey",
    0x0A: "Data",
    0x0B: "Status",
    0x0C: "RemoteWipe",
    0x0D: "EASProvisionDoc",
    0x0E: "DevicePasswordEnabled",
    0x0F: "AlphanumericDevicePasswordRequired",
    0x10: "RequireStorageCardEncryption",
    0x11: "PasswordRecoveryEnabled",
    0x12: "AttachmentsEnabled",
    0x13: "MinDevicePasswordLength",
    0x14: "MaxInactivityTimeDeviceLock",
    0x15: "MaxDevicePasswordFailedAttempts",
    0x16: "MaxAttachmentSize",
    0x17: "AllowSimpleDevicePassword",
    0x18: "DevicePasswordExpiration",
    0x19: "DevicePasswordHistory",
    0x1A: "AllowStorageCard",
    0x1B: "AllowCamera",
    0x1C: "RequireDeviceEncryption",
    0x1D: "AllowUnsignedApplications",
    0x1E: "AllowUnsignedInstallationPackages",
    0x1F: "MinDevicePasswordComplexCharacters",
    0x20: "AllowWiFi",
    0x21: "AllowTextMessaging",
    0x22: "AllowPOPIMAPEmail",
    0x23: "AllowBluetooth",
    0x24: "AllowIrDA",
    0x25: "RequireManualSyncWhenRoaming",
    0x26: "AllowDesktopSync",
    0x27: "MaxCalendarAgeFilter",
    0x28: "AllowHTMLEmail",
    0x29: "MaxEmailAgeFilter",
    0x2A: "MaxEmailBodyTruncationSize",
    0x2B: "MaxEmailHTMLBodyTruncationSize",
    0x2C: "RequireSignedSMIMEMessages",
    0x2D: "RequireEncryptedSMIMEMessages",
    0x2E: "RequireSignedSMIMEAlgorithm",
    0x2F: "RequireEncryptionSMIMEAlgorithm",
    0x30: "AllowSMIMEEncryptionAlgorithmNegotiation",
    0x31: "AllowSMIMESoftCerts",
    0x32: "AllowBrowser",
    0x33: "AllowConsumerEmail",
    0x34: "AllowRemoteDesktop",
    0x35: "AllowInternetSharing",
    0x36: "UnapprovedInROMApplicationList",
    0x37: "ApplicationName",
    0x38: "ApprovedApplicationList",
    0x39: "Hash",
]

/// ComposeMail namespace (Code Page 21) - for SendMail, SmartForward, SmartReply
let composeMailTags: [UInt8: String] = [
    0x05: "SendMail",
    0x06: "SmartForward",
    0x07: "SmartReply",
    0x08: "SaveInSentItems",
    0x09: "ReplaceMime",
    0x0B: "Source",
    0x0C: "FolderId",
    0x0D: "ItemId",
    0x0E: "LongId",
    0x0F: "InstanceId",
    0x10: "Mime",
    0x11: "ClientId",
    0x12: "Status",
    0x13: "AccountId",
]

/// Settings namespace (Code Page 18)
let settingsTags: [UInt8: String] = [
    0x05: "Settings",
    0x06: "Status",
    0x07: "Get",
    0x08: "Set",
    0x09: "Oof",
    0x0A: "OofState",
    0x0B: "StartTime",
    0x0C: "EndTime",
    0x0D: "OofMessage",
    0x0E: "AppliesToInternal",
    0x0F: "AppliesToExternalKnown",
    0x10: "AppliesToExternalUnknown",
    0x11: "Enabled",
    0x12: "ReplyMessage",
    0x13: "BodyType",
    0x14: "DevicePassword",
    0x15: "Password",
    0x16: "DeviceInformation",
    0x17: "Model",
    0x18: "IMEI",
    0x19: "FriendlyName",
    0x1A: "OS",
    0x1B: "OSLanguage",
    0x1C: "PhoneNumber",
    0x1D: "UserInformation",
    0x1E: "EmailAddresses",
    0x1F: "SMTPAddress",
    0x20: "UserAgent",
    0x21: "EnableOutboundSMS",
    0x22: "MobileOperator",
    0x23: "PrimarySmtpAddress",
    0x24: "Accounts",
    0x25: "Account",
    0x26: "AccountId",
    0x27: "AccountName",
    0x28: "UserDisplayName",
    0x29: "SendDisabled",
    0x2A: "RightsManagementInformation",
]

// MARK: - Code Page Registry

/// Get tag name for code page and tag value
func getTagName(codePage: UInt8, tag: UInt8) -> String {
    let tagValue = tag & WBXML_TAG_MASK

    switch codePage {
    case EASCodePage.airSync.rawValue:
        return airSyncTags[tagValue] ?? "Unknown_\(codePage)_\(tagValue)"
    case EASCodePage.calendar.rawValue:
        return calendarTags[tagValue] ?? "Unknown_\(codePage)_\(tagValue)"
    case EASCodePage.folderHierarchy.rawValue:
        return folderHierarchyTags[tagValue] ?? "Unknown_\(codePage)_\(tagValue)"
    case EASCodePage.airSyncBase.rawValue:
        return airSyncBaseTags[tagValue] ?? "Unknown_\(codePage)_\(tagValue)"
    case EASCodePage.provision.rawValue:
        return provisionTags[tagValue] ?? "Unknown_\(codePage)_\(tagValue)"
    case EASCodePage.settings.rawValue:
        return settingsTags[tagValue] ?? "Unknown_\(codePage)_\(tagValue)"
    case EASCodePage.composeEmail.rawValue:
        return composeMailTags[tagValue] ?? "Unknown_\(codePage)_\(tagValue)"
    default:
        return "Unknown_\(codePage)_\(tagValue)"
    }
}
