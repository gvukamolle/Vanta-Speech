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

    /// Use plain XML instead of WBXML (most servers require WBXML)
    var usePlainXML = false

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
    ///   - body: Email body (plain text)
    ///   - from: Sender email address (optional, uses username if not provided)
    /// - Returns: True if email was sent successfully
    func sendEmail(
        to recipients: [String],
        subject: String,
        body: String,
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
            body: body
        )

        // Build SendMail XML request
        let xmlBody = buildSendMailXML(mimeMessage: mimeMessage)

        // Build and execute request
        let request = try buildSendMailRequest(credentials: credentials, body: xmlBody)
        let (data, response) = try await executeRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailError.networkError("Invalid response")
        }

        // SendMail returns empty body on success (HTTP 200)
        if httpResponse.statusCode == 200 {
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

    private func buildSendMailRequest(credentials: EASCredentials, body: String) throws -> URLRequest {
        guard let url = credentials.buildURL(command: "SendMail") else {
            throw EmailError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        request.setValue(EASCredentials.protocolVersion, forHTTPHeaderField: "MS-ASProtocolVersion")
        request.setValue("VantaSpeech/1.0", forHTTPHeaderField: "User-Agent")

        // Get policy key from sync state if available
        let policyKey = keychainManager.loadEASSyncState()?.policyKey ?? "0"
        request.setValue(policyKey, forHTTPHeaderField: "X-MS-PolicyKey")

        // Use plain XML for testing, WBXML for production
        if usePlainXML {
            request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
            request.setValue("text/xml", forHTTPHeaderField: "Accept")
            request.httpBody = body.data(using: .utf8)
        } else {
            request.setValue("application/vnd.ms-sync.wbxml", forHTTPHeaderField: "Content-Type")
            request.setValue("application/vnd.ms-sync.wbxml", forHTTPHeaderField: "Accept")
            // Encode XML to WBXML
            let encoder = WBXMLEncoder()
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw EmailError.sendFailed("Ошибка кодирования WBXML: \(error.localizedDescription)")
            }
        }

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
        body: String
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

        // Build MIME message (RFC 5322)
        let mime = """
        From: \(from)
        To: \(toHeader)
        Subject: \(encodedSubject)
        Date: \(date)
        Message-ID: \(messageId)
        MIME-Version: 1.0
        Content-Type: text/plain; charset=UTF-8
        Content-Transfer-Encoding: 8bit

        \(body)
        """

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

    // MARK: - EAS XML Building

    private func buildSendMailXML(mimeMessage: String) -> String {
        // Base64 encode the MIME message
        let mimeBase64 = Data(mimeMessage.utf8).base64EncodedString()

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <SendMail xmlns="ComposeMail">
            <SaveInSentItems/>
            <Mime>\(mimeBase64)</Mime>
        </SendMail>
        """
    }
}
