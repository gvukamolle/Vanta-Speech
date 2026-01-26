import Foundation

/// Service for authenticating against Active Directory via LDAP
actor LDAPAuthService {
    // MARK: - LDAP Configuration (from Env)

    private static var ldapHost: String { Env.ldapHost }
    private static var ldapPort: Int { Env.ldapPort }
    private static var ldapBaseDN: String { Env.ldapBaseDN }
    private static var ldapUserSearchFilter: String { Env.ldapUserSearchFilter }
    private static var useLDAPS: Bool { Env.useLDAPS }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Authentication

    enum AuthError: LocalizedError {
        case invalidCredentials
        case connectionFailed(String)
        case serverError(String)
        case timeout
        case streamError(String)
        case writeError(Int, Int)
        case readError

        var errorDescription: String? {
            switch self {
            case .invalidCredentials:
                return "Неверный логин или пароль (LDAP resultCode != 0)"
            case .connectionFailed(let details):
                return "Не удалось подключиться к серверу LDAP. \(details)"
            case .serverError(let message):
                return "Ошибка сервера: \(message)"
            case .timeout:
                return "Превышено время ожидания подключения к LDAP"
            case .streamError(let details):
                return "Ошибка потока данных: \(details)"
            case .writeError(let written, let expected):
                return "Ошибка отправки запроса: записано \(written) из \(expected) байт"
            case .readError:
                return "Ошибка чтения ответа от LDAP сервера (0 байт)"
            }
        }
    }

    /// Authenticate user against LDAP/AD
    /// - Parameters:
    ///   - username: sAMAccountName (e.g., "ivanov")
    ///   - password: User's AD password
    /// - Returns: UserSession on success
    func authenticate(username: String, password: String) async throws -> UserSession {
        // Construct the bind DN from username
        // Format: username@domain or DOMAIN\username or full DN
        let bindDN = "\(username)@b2pos.local"

        // For direct LDAP auth, we would use a library like OpenLDAP
        // Since iOS doesn't have native LDAP, we have two options:
        // 1. Use a backend auth proxy (recommended)
        // 2. Use a third-party LDAP library

        // Option 1: Backend Auth Proxy (implement when backend is ready)
        // return try await authenticateViaProxy(username: username, password: password)

        // Option 2: Simple LDAP bind attempt via TCP (basic implementation)
        // This is a simplified version - in production, use proper LDAP library
        return try await performLDAPBind(bindDN: bindDN, password: password, username: username)
    }

    // MARK: - LDAP Bind Implementation

    private func performLDAPBind(bindDN: String, password: String, username: String) async throws -> UserSession {
        // Create LDAP bind request
        // This is a simplified implementation using raw TCP socket approach
        // For production, consider using a proper LDAP library or backend proxy

        let host = Self.ldapHost
        let port = Self.ldapPort

        return try await withCheckedThrowingContinuation { continuation in
            var inputStream: InputStream?
            var outputStream: OutputStream?

            Stream.getStreamsToHost(
                withName: host,
                port: port,
                inputStream: &inputStream,
                outputStream: &outputStream
            )

            guard let input = inputStream, let output = outputStream else {
                continuation.resume(throwing: AuthError.connectionFailed("Не удалось создать потоки к \(host):\(port)"))
                return
            }

            if Self.useLDAPS {
                let sslSettings: [CFString: Any] = [
                    kCFStreamSSLLevel: kCFStreamSocketSecurityLevelNegotiatedSSL,
                    kCFStreamSSLValidatesCertificateChain: true,
                    kCFStreamSSLPeerName: host as CFString
                ]
                let sslKey = Stream.PropertyKey(kCFStreamPropertySSLSettings as String)
                input.setProperty(sslSettings, forKey: sslKey)
                output.setProperty(sslSettings, forKey: sslKey)
            }

            input.open()
            output.open()

            // Check stream status
            if input.streamStatus == .error {
                let errorDesc = input.streamError?.localizedDescription ?? "unknown"
                input.close()
                output.close()
                continuation.resume(throwing: AuthError.streamError("Input stream error: \(errorDesc)"))
                return
            }

            if output.streamStatus == .error {
                let errorDesc = output.streamError?.localizedDescription ?? "unknown"
                input.close()
                output.close()
                continuation.resume(throwing: AuthError.streamError("Output stream error: \(errorDesc)"))
                return
            }

            // Build LDAP Simple Bind Request
            let bindRequest = buildLDAPBindRequest(bindDN: bindDN, password: password)

            // Send request
            let bytesWritten = bindRequest.withUnsafeBytes { buffer in
                output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: bindRequest.count)
            }

            guard bytesWritten == bindRequest.count else {
                input.close()
                output.close()
                continuation.resume(throwing: AuthError.writeError(bytesWritten, bindRequest.count))
                return
            }

            // Read response
            var responseBuffer = [UInt8](repeating: 0, count: 1024)
            let bytesRead = input.read(&responseBuffer, maxLength: responseBuffer.count)

            guard bytesRead > 0 else {
                input.close()
                output.close()
                continuation.resume(throwing: AuthError.readError)
                return
            }

            // Parse LDAP Bind Response
            let responseData = Data(responseBuffer.prefix(bytesRead))
            let parseResult = parseLDAPBindResponse(response: responseData)

            guard parseResult.success else {
                input.close()
                output.close()
                let errorMsg = "resultCode=\(parseResult.resultCode), \(parseResult.errorMessage), bytes=\(bytesRead), hex=\(responseData.prefix(50).map { String(format: "%02X", $0) }.joined(separator: " "))"
                continuation.resume(throwing: AuthError.serverError(errorMsg))
                return
            }

            // Bind successful - now perform LDAP Search to get user attributes
            let userAttributes = self.performLDAPSearch(
                input: input,
                output: output,
                username: username
            )

            input.close()
            output.close()

            let session = UserSession(
                username: username,
                displayName: userAttributes.displayName ?? username,
                email: userAttributes.email
            )
            continuation.resume(returning: session)
        }
    }

    // MARK: - LDAP Search Implementation

    /// Performs LDAP Search to retrieve user attributes (displayName, mail)
    private func performLDAPSearch(
        input: InputStream,
        output: OutputStream,
        username: String
    ) -> (displayName: String?, email: String?) {
        // Build LDAP Search Request
        let searchRequest = buildLDAPSearchRequest(username: username, messageID: 2)

        // Send search request
        let bytesWritten = searchRequest.withUnsafeBytes { buffer in
            output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: searchRequest.count)
        }

        guard bytesWritten == searchRequest.count else {
            return (nil, nil)
        }

        // Read search response (may need multiple reads for large responses)
        var allResponseData = Data()
        var responseBuffer = [UInt8](repeating: 0, count: 4096)

        // Read initial response
        let bytesRead = input.read(&responseBuffer, maxLength: responseBuffer.count)
        guard bytesRead > 0 else {
            return (nil, nil)
        }
        allResponseData.append(contentsOf: responseBuffer.prefix(bytesRead))

        // Parse search response to extract attributes
        return parseLDAPSearchResponse(response: allResponseData)
    }

    /// Build LDAP Search Request (ASN.1 BER encoded)
    private func buildLDAPSearchRequest(username: String, messageID: Int) -> Data {
        var request = Data()

        // Message ID
        let messageIDBytes: [UInt8] = [0x02, 0x01, UInt8(messageID)]

        // Search Request (application 3)
        var searchRequestContent = Data()

        // Base DN (octet string)
        let baseDNBytes = Self.ldapBaseDN.data(using: .utf8) ?? Data()
        searchRequestContent.append(0x04)
        searchRequestContent.append(contentsOf: encodeLength(baseDNBytes.count))
        searchRequestContent.append(baseDNBytes)

        // Scope: subtree (2) - enumerated
        searchRequestContent.append(contentsOf: [0x0A, 0x01, 0x02])

        // DerefAliases: neverDerefAliases (0) - enumerated
        searchRequestContent.append(contentsOf: [0x0A, 0x01, 0x00])

        // SizeLimit (integer, 0 = no limit)
        searchRequestContent.append(contentsOf: [0x02, 0x01, 0x01])

        // TimeLimit (integer, 0 = no limit)
        searchRequestContent.append(contentsOf: [0x02, 0x01, 0x00])

        // TypesOnly (boolean, false)
        searchRequestContent.append(contentsOf: [0x01, 0x01, 0x00])

        // Filter: (sAMAccountName=username)
        let filterContent = buildEqualityFilter(attribute: "sAMAccountName", value: username)
        searchRequestContent.append(filterContent)

        // Attributes to return: displayName, mail
        var attributesSequence = Data()
        for attr in ["displayName", "mail"] {
            let attrBytes = attr.data(using: .utf8) ?? Data()
            attributesSequence.append(0x04)
            attributesSequence.append(contentsOf: encodeLength(attrBytes.count))
            attributesSequence.append(attrBytes)
        }
        searchRequestContent.append(0x30) // Sequence tag
        searchRequestContent.append(contentsOf: encodeLength(attributesSequence.count))
        searchRequestContent.append(attributesSequence)

        // Wrap in Search Request (application 3)
        var searchRequest = Data()
        searchRequest.append(0x63) // Application 3 (Search Request)
        searchRequest.append(contentsOf: encodeLength(searchRequestContent.count))
        searchRequest.append(searchRequestContent)

        // Build complete message
        var messageContent = Data()
        messageContent.append(contentsOf: messageIDBytes)
        messageContent.append(searchRequest)

        // Wrap in LDAP Message sequence
        request.append(0x30)
        request.append(contentsOf: encodeLength(messageContent.count))
        request.append(messageContent)

        return request
    }

    /// Build LDAP Equality Filter: (attribute=value)
    private func buildEqualityFilter(attribute: String, value: String) -> Data {
        var filter = Data()

        let attrBytes = attribute.data(using: .utf8) ?? Data()
        let valueBytes = value.data(using: .utf8) ?? Data()

        // AttributeValueAssertion content
        var content = Data()
        // Attribute description (octet string)
        content.append(0x04)
        content.append(contentsOf: encodeLength(attrBytes.count))
        content.append(attrBytes)
        // Assertion value (octet string)
        content.append(0x04)
        content.append(contentsOf: encodeLength(valueBytes.count))
        content.append(valueBytes)

        // Wrap in equalityMatch (context-specific 3)
        filter.append(0xA3)
        filter.append(contentsOf: encodeLength(content.count))
        filter.append(content)

        return filter
    }

    /// Parse LDAP Search Response to extract displayName and mail attributes
    private func parseLDAPSearchResponse(response: Data) -> (displayName: String?, email: String?) {
        var displayName: String?
        var email: String?

        let bytes = [UInt8](response)

        // Look for SearchResultEntry (tag 0x64)
        // Structure: SEQUENCE { messageID, searchResultEntry { objectName, attributes } }

        var i = 0
        while i < bytes.count - 4 {
            // Look for octet string (0x04) which might contain attribute names/values
            if bytes[i] == 0x04 {
                let lengthInfo = decodeLength(bytes: bytes, startIndex: i + 1)
                let valueStart = i + 1 + lengthInfo.bytesUsed
                let valueEnd = valueStart + lengthInfo.length

                if valueEnd <= bytes.count {
                    let valueData = Data(bytes[valueStart..<valueEnd])
                    if let stringValue = String(data: valueData, encoding: .utf8) {
                        // Check if this is an attribute name we're looking for
                        if stringValue.lowercased() == "displayname" {
                            // Next octet string should be the value
                            let nextValueResult = findNextOctetString(bytes: bytes, startIndex: valueEnd)
                            if let value = nextValueResult {
                                displayName = value
                            }
                        } else if stringValue.lowercased() == "mail" {
                            // Next octet string should be the value
                            let nextValueResult = findNextOctetString(bytes: bytes, startIndex: valueEnd)
                            if let value = nextValueResult {
                                email = value
                            }
                        }
                    }
                }
            }
            i += 1
        }

        return (displayName, email)
    }

    /// Decode ASN.1 BER length
    private func decodeLength(bytes: [UInt8], startIndex: Int) -> (length: Int, bytesUsed: Int) {
        guard startIndex < bytes.count else { return (0, 0) }

        let firstByte = bytes[startIndex]
        if firstByte < 128 {
            return (Int(firstByte), 1)
        } else {
            let numBytes = Int(firstByte & 0x7F)
            guard startIndex + numBytes < bytes.count else { return (0, 1) }

            var length = 0
            for j in 0..<numBytes {
                length = (length << 8) | Int(bytes[startIndex + 1 + j])
            }
            return (length, 1 + numBytes)
        }
    }

    /// Find the next octet string value after a given index
    private func findNextOctetString(bytes: [UInt8], startIndex: Int) -> String? {
        var i = startIndex
        // Skip SET tag if present (0x31)
        while i < bytes.count - 2 {
            if bytes[i] == 0x04 {
                let lengthInfo = decodeLength(bytes: bytes, startIndex: i + 1)
                let valueStart = i + 1 + lengthInfo.bytesUsed
                let valueEnd = valueStart + lengthInfo.length

                if valueEnd <= bytes.count && lengthInfo.length > 0 {
                    let valueData = Data(bytes[valueStart..<valueEnd])
                    return String(data: valueData, encoding: .utf8)
                }
            }
            i += 1
            // Don't search too far
            if i - startIndex > 20 { break }
        }
        return nil
    }

    // MARK: - LDAP Protocol Helpers

    /// Build LDAP Simple Bind Request (ASN.1 BER encoded)
    private func buildLDAPBindRequest(bindDN: String, password: String) -> Data {
        var request = Data()

        // Message ID (integer, value = 1)
        let messageID: [UInt8] = [0x02, 0x01, 0x01]

        // Bind Request (application 0)
        var bindRequestContent = Data()

        // Version (integer, value = 3 for LDAPv3)
        bindRequestContent.append(contentsOf: [0x02, 0x01, 0x03])

        // Bind DN (octet string)
        let bindDNBytes = bindDN.data(using: .utf8) ?? Data()
        bindRequestContent.append(0x04) // Octet string tag
        bindRequestContent.append(contentsOf: encodeLength(bindDNBytes.count))
        bindRequestContent.append(bindDNBytes)

        // Simple authentication (context-specific 0)
        let passwordBytes = password.data(using: .utf8) ?? Data()
        bindRequestContent.append(0x80) // Context-specific primitive tag 0
        bindRequestContent.append(contentsOf: encodeLength(passwordBytes.count))
        bindRequestContent.append(passwordBytes)

        // Wrap in Bind Request sequence (application 0)
        var bindRequest = Data()
        bindRequest.append(0x60) // Application 0 (Bind Request)
        bindRequest.append(contentsOf: encodeLength(bindRequestContent.count))
        bindRequest.append(bindRequestContent)

        // Build complete message
        var messageContent = Data()
        messageContent.append(contentsOf: messageID)
        messageContent.append(bindRequest)

        // Wrap in LDAP Message sequence
        request.append(0x30) // Sequence tag
        request.append(contentsOf: encodeLength(messageContent.count))
        request.append(messageContent)

        return request
    }

    /// Encode ASN.1 BER length
    private func encodeLength(_ length: Int) -> [UInt8] {
        if length < 128 {
            return [UInt8(length)]
        } else if length < 256 {
            return [0x81, UInt8(length)]
        } else {
            return [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
        }
    }

    /// Parse LDAP Bind Response and extract result code
    private func parseLDAPBindResponse(response: Data) -> (success: Bool, resultCode: Int, errorMessage: String) {
        // Parse ASN.1 BER encoded LDAP Bind Response
        // Looking for resultCode

        guard response.count > 10 else {
            return (false, -1, "Response too short (\(response.count) bytes)")
        }

        // Find the result code in the response
        // Response format: SEQUENCE { messageID, bindResponse { resultCode, matchedDN, diagnosticMessage } }
        // Result codes: 0 = success, 49 = invalidCredentials, 52 = unavailable, etc.

        let bytes = [UInt8](response)

        // Look for enumerated tag (0x0A) which contains the result code
        for i in 0..<(bytes.count - 2) {
            if bytes[i] == 0x0A && bytes[i + 1] == 0x01 {
                // Found enumerated value (result code)
                let resultCode = Int(bytes[i + 2])
                let errorMsg = ldapResultCodeDescription(resultCode)
                return (resultCode == 0, resultCode, errorMsg)
            }
        }

        return (false, -2, "Could not parse result code from response")
    }

    /// Human-readable LDAP result code descriptions
    private func ldapResultCodeDescription(_ code: Int) -> String {
        switch code {
        case 0: return "success"
        case 1: return "operationsError"
        case 2: return "protocolError"
        case 3: return "timeLimitExceeded"
        case 4: return "sizeLimitExceeded"
        case 7: return "authMethodNotSupported"
        case 8: return "strongerAuthRequired"
        case 14: return "saslBindInProgress"
        case 16: return "noSuchAttribute"
        case 32: return "noSuchObject"
        case 34: return "invalidDNSyntax"
        case 48: return "inappropriateAuthentication"
        case 49: return "invalidCredentials"
        case 50: return "insufficientAccessRights"
        case 51: return "busy"
        case 52: return "unavailable"
        case 53: return "unwillingToPerform"
        case 80: return "other"
        default: return "unknownError(\(code))"
        }
    }
}
