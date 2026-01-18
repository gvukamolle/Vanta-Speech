import Foundation

/// Environment configuration template
/// Copy this file to Env.swift and fill in actual values
/// DO NOT commit Env.swift to version control!
enum Env {
    // MARK: - Transcription Service

    /// Base URL for transcription API
    static let transcriptionBaseURL = "http://your-server:8000/v1"

    /// API key for transcription service
    static let transcriptionAPIKey = "your-api-key-here"

    /// Model for audio transcription (Whisper-like)
    static let transcriptionModel = "gigaam-v3"

    /// Model for summary generation (LLM)
    static let summaryModel = "cod/gpt-oss:120b"

    // MARK: - LDAP Configuration

    /// LDAP server host
    static let ldapHost = "your-ldap-server"

    /// LDAP server port
    static let ldapPort = 389

    /// LDAP base DN for user search
    static let ldapBaseDN = "OU=Users,DC=company,DC=local"

    /// LDAP user search filter
    static let ldapUserSearchFilter = "(&(objectCategory=Person)(sAMAccountName=*))"

    /// Use LDAPS (TLS) instead of plain LDAP
    static let useLDAPS = false

    // MARK: - Exchange Server (EAS)

    /// Corporate Exchange server URL
    static let exchangeServerURL = "https://mail.company.com"

    /// Corporate email domain
    static let corporateEmailDomain = "@company.com"
}
