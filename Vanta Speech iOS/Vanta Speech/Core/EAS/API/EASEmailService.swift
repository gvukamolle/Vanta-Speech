import Foundation
import Network

/// Service for sending emails via Exchange ActiveSync SendMail command
final class EASEmailService {

    // MARK: - Properties

    private let session: URLSession
    private let keychainManager: KeychainManager
    private let networkMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.vantaspeech.eas.email.network")

    private var isNetworkAvailable = true


    // MARK: - Errors

    enum EmailError: LocalizedError {
        case noCredentials
        case invalidServerURL
        case networkError(String)
        case authenticationFailed
        case sendFailed(String)
        case noRecipients
        case offline

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "Не найдены учетные данные Exchange"
            case .invalidServerURL:
                return "Неверный URL сервера Exchange"
            case .networkError(let message):
                return "Ошибка сети: \(message)"
            case .authenticationFailed:
                return "Ошибка аутентификации Exchange"
            case .sendFailed(let message):
                return "Не удалось отправить письмо: \(message)"
            case .noRecipients:
                return "Нет получателей для отправки"
            case .offline:
                return "Нет подключения к сети"
            }
        }
    }

    // MARK: - Initialization

    init(
        keychainManager: KeychainManager = .shared,
        session: URLSession? = nil
    ) {
        self.keychainManager = keychainManager

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = session ?? URLSession(configuration: config)

        self.networkMonitor = NWPathMonitor()

        // Start network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkAvailable = path.status == .satisfied
        }
        networkMonitor.start(queue: monitorQueue)
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Public API

    /// Send an email via Exchange ActiveSync
    /// - Parameters:
    ///   - to: Array of recipient email addresses
    ///   - subject: Email subject
    ///   - body: Email body (plain text or HTML)
    ///   - isHTML: Whether body is HTML content (default: false)
    ///   - from: Sender email address (optional, uses username if not provided)
    /// - Returns: True if email was sent successfully
    func sendEmail(
        to recipients: [String],
        subject: String,
        body: String,
        isHTML: Bool = false,
        from: String? = nil
    ) async throws -> Bool {
        guard !recipients.isEmpty else {
            throw EmailError.noRecipients
        }

        guard isNetworkAvailable else {
            throw EmailError.offline
        }

        let credentials = try getCredentials()
        let senderEmail = from ?? credentials.username

        // Build MIME message
        let mimeMessage = buildMIMEMessage(
            to: recipients,
            from: senderEmail,
            subject: subject,
            body: body,
            isHTML: isHTML
        )

        debugLog("Sending email from: \(senderEmail) to: \(recipients)", module: "EASEmail", level: .info)
        debugLog("Subject: \(subject)", module: "EASEmail", level: .info)
        debugLog("Body length: \(body.count) chars", module: "EASEmail", level: .info)

        // Build and execute request (raw MIME for protocol 12.1)
        let request = try buildSendMailRequest(credentials: credentials, mimeMessage: mimeMessage)
        debugLog("SendMail request URL: \(request.url?.absoluteString ?? "nil")", module: "EASEmail", level: .info)
        let (data, response) = try await executeRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailError.networkError("Invalid response")
        }

        debugLog("SendMail response: HTTP \(httpResponse.statusCode), body size: \(data.count) bytes", module: "EASEmail", level: .info)

        // Log response body for debugging
        if !data.isEmpty {
            if let responseText = String(data: data, encoding: .utf8) {
                debugLog("SendMail response body: \(responseText.prefix(500))", module: "EASEmail", level: .info)
            } else {
                debugLog("SendMail response body (hex): \(data.prefix(100).map { String(format: "%02X", $0) }.joined())", module: "EASEmail", level: .info)
            }
        }

        // SendMail returns empty body on success (HTTP 200)
        if httpResponse.statusCode == 200 {
            debugLog("SendMail succeeded (HTTP 200)", module: "EASEmail", level: .info)
            return true
        }

        // Check for error in response
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw EmailError.sendFailed(errorMessage)
    }

    // MARK: - Private Methods

    private func getCredentials() throws -> EASCredentials {
        guard let credentials = keychainManager.loadEASCredentials() else {
            throw EmailError.noCredentials
        }
        return credentials
    }

    private func buildSendMailRequest(credentials: EASCredentials, mimeMessage: String) throws -> URLRequest {
        // Add SaveInSent=T to URL to save in Sent Items
        guard var urlComponents = URLComponents(string: credentials.serverURL) else {
            throw EmailError.invalidServerURL
        }
        urlComponents.path = "/Microsoft-Server-ActiveSync"
        urlComponents.queryItems = [
            URLQueryItem(name: "Cmd", value: "SendMail"),
            URLQueryItem(name: "User", value: credentials.username),
            URLQueryItem(name: "DeviceId", value: credentials.deviceId),
            URLQueryItem(name: "DeviceType", value: "VantaSpeech"),
            URLQueryItem(name: "SaveInSent", value: "T")  // Save to Sent Items
        ]

        guard let url = urlComponents.url else {
            throw EmailError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        // Use protocol version 12.1 which accepts raw MIME
        request.setValue("12.1", forHTTPHeaderField: "MS-ASProtocolVersion")
        request.setValue("VantaSpeech/1.0", forHTTPHeaderField: "User-Agent")

        // Get policy key from sync state if available
        let policyKey = keychainManager.loadEASSyncState()?.policyKey ?? "0"
        request.setValue(policyKey, forHTTPHeaderField: "X-MS-PolicyKey")

        // For protocol 12.1: send raw MIME with Content-Type: message/rfc822
        request.setValue("message/rfc822", forHTTPHeaderField: "Content-Type")
        request.httpBody = mimeMessage.data(using: .utf8)

        return request
    }

    private func executeRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard isNetworkAvailable else {
            throw EmailError.offline
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw EmailError.networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                return (data, response)
            case 401:
                throw EmailError.authenticationFailed
            case 403:
                throw EmailError.authenticationFailed
            default:
                let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                throw EmailError.sendFailed(message)
            }
        } catch let error as EmailError {
            throw error
        } catch {
            throw EmailError.networkError(error.localizedDescription)
        }
    }

    // MARK: - MIME Building

    private func buildMIMEMessage(
        to recipients: [String],
        from: String,
        subject: String,
        body: String,
        isHTML: Bool = false
    ) -> String {
        let messageId = "<\(UUID().uuidString)@vantaspeech.local>"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let date = dateFormatter.string(from: Date())

        // Encode subject for UTF-8 (RFC 2047)
        let encodedSubject = encodeHeader(subject)

        // Build recipients string
        let toHeader = recipients.joined(separator: ", ")

        // Content type based on body format
        let contentType = isHTML
            ? "text/html; charset=UTF-8"
            : "text/plain; charset=UTF-8"

        // Build MIME message (RFC 5322)
        // IMPORTANT: No leading whitespace! MIME headers must start at column 0
        var mime = "From: \(from)\r\n"
        mime += "To: \(toHeader)\r\n"
        mime += "Subject: \(encodedSubject)\r\n"
        mime += "Date: \(date)\r\n"
        mime += "Message-ID: \(messageId)\r\n"
        mime += "MIME-Version: 1.0\r\n"
        mime += "Content-Type: \(contentType)\r\n"
        mime += "Content-Transfer-Encoding: 8bit\r\n"
        mime += "\r\n"  // Empty line separates headers from body
        mime += body

        return mime
    }

    /// Encode header value for UTF-8 using RFC 2047 (=?UTF-8?B?...?=)
    private func encodeHeader(_ value: String) -> String {
        // Check if encoding is needed (non-ASCII characters)
        let needsEncoding = value.unicodeScalars.contains { !$0.isASCII }

        if !needsEncoding {
            return value
        }

        // Base64 encode the UTF-8 string
        if let data = value.data(using: .utf8) {
            let base64 = data.base64EncodedString()
            return "=?UTF-8?B?\(base64)?="
        }

        return value
    }

}
