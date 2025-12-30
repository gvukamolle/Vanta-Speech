import Foundation

/// Low-level EWS SOAP client with NTLM authentication
final class EWSClient: NSObject {
    private let serverURL: URL
    private let credential: URLCredential
    private var session: URLSession!

    init(serverURL: URL, credential: URLCredential) {
        self.serverURL = serverURL
        self.credential = credential
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = IntegrationConfig.EWS.requestTimeout
        config.timeoutIntervalForResource = IntegrationConfig.EWS.requestTimeout * 2

        self.session = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Public API

    /// Send a SOAP request to EWS
    /// - Parameters:
    ///   - soapAction: The SOAPAction header value
    ///   - body: The complete SOAP envelope XML
    /// - Returns: Response data
    func sendRequest(soapAction: String, body: String) async throws -> Data {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(soapAction, forHTTPHeaderField: "SOAPAction")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EWSError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw EWSError.authenticationFailed
        case 403:
            throw EWSError.accessDenied
        case 429:
            throw EWSError.throttled
        case 500...599:
            // Try to extract SOAP fault
            if let fault = extractSOAPFault(from: data) {
                throw EWSError.soapFault(fault)
            }
            throw EWSError.serverError("HTTP \(httpResponse.statusCode)")
        default:
            throw EWSError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - SOAP Fault Extraction

    private func extractSOAPFault(from data: Data) -> String? {
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }

        // Simple regex extraction of faultstring
        if let range = xmlString.range(of: "<faultstring>"),
           let endRange = xmlString.range(of: "</faultstring>") {
            let startIndex = range.upperBound
            let endIndex = endRange.lowerBound
            return String(xmlString[startIndex..<endIndex])
        }

        return nil
    }
}

// MARK: - URLSessionTaskDelegate (NTLM Authentication)

extension EWSClient: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Prevent infinite auth loops
        guard challenge.previousFailureCount < 3 else {
            debugLog("Authentication failed after 3 attempts", module: "EWSClient", level: .error)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let authMethod = challenge.protectionSpace.authenticationMethod

        switch authMethod {
        case NSURLAuthenticationMethodNTLM:
            debugLog("NTLM challenge received, responding with credentials", module: "EWSClient")
            completionHandler(.useCredential, credential)

        case NSURLAuthenticationMethodServerTrust:
            // Trust self-signed certs in dev (remove for production or use cert pinning)
            if let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }

        case NSURLAuthenticationMethodHTTPBasic:
            // Fallback to Basic auth if NTLM not available
            debugLog("Basic auth challenge received", module: "EWSClient")
            completionHandler(.useCredential, credential)

        default:
            debugLog("Unknown auth method: \(authMethod)", module: "EWSClient", level: .warning)
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Convenience Factory

extension EWSClient {
    /// Create EWSClient from stored credentials
    static func fromCredentials(_ credentials: EWSCredentials) throws -> EWSClient {
        guard let serverURL = credentials.ewsEndpoint else {
            throw EWSError.invalidServerURL
        }

        let urlCredential = URLCredential(
            user: credentials.ntlmUsername,
            password: credentials.password,
            persistence: .forSession
        )

        return EWSClient(serverURL: serverURL, credential: urlCredential)
    }
}
