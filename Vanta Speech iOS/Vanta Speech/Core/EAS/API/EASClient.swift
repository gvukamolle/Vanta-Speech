import Foundation
import Network
import UIKit
import os

/// HTTP client for Exchange ActiveSync protocol
final class EASClient {

    // MARK: - Properties

    private let session: URLSession
    private let keychainManager: KeychainManager
    private let networkMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.vantaspeech.eas.network")

    /// Thread-safe access to network availability status
    private let networkAvailableLock = OSAllocatedUnfairLock(initialState: true)

    private var isNetworkAvailable: Bool {
        get { networkAvailableLock.withLock { $0 } }
        set { networkAvailableLock.withLock { $0 = newValue } }
    }

    /// Use plain XML instead of WBXML (most servers require WBXML)
    var usePlainXML = false

    // MARK: - Initialization

    init(
        keychainManager: KeychainManager = .shared,
        session: URLSession = .shared
    ) {
        self.keychainManager = keychainManager
        self.session = session
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

    /// Test connection with OPTIONS request
    func testConnection() async throws -> EASServerInfo {
        let credentials = try getCredentials()
        let request = try buildOptionsRequest(credentials: credentials)
        let (_, response) = try await executeRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EASError.networkError("Invalid response type")
        }

        // Parse server info from headers
        let supportedVersions = httpResponse.value(forHTTPHeaderField: "MS-ASProtocolVersions") ?? ""
        let supportedCommands = httpResponse.value(forHTTPHeaderField: "MS-ASProtocolCommands") ?? ""

        return EASServerInfo(
            protocolVersions: supportedVersions.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            supportedCommands: supportedCommands.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        )
    }

    /// Execute Provision to accept device policies (required by most corporate servers)
    func provision() async throws -> ProvisionResponse {
        let credentials = try getCredentials()

        // Get device info on main actor
        let deviceInfo = await getDeviceInfo()

        // Step 1: Request policy with DeviceInformation
        let requestXml = buildProvisionRequestXML(
            deviceModel: deviceInfo.model,
            osVersion: deviceInfo.osVersion,
            deviceId: credentials.deviceId
        )
        debugLog("Provision request XML:\n\(requestXml)", module: "EAS", level: .info)
        var request = try buildRequest(command: "Provision", credentials: credentials, body: requestXml)
        request.setValue("0", forHTTPHeaderField: "X-MS-PolicyKey") // No policy yet

        let (data1, _) = try await executeRequest(request)
        let initialResponse = try parseProvisionResponse(data1)

        // If we got a policy, acknowledge it
        guard let policyKey = initialResponse.policyKey, initialResponse.status == 1 else {
            // Status 1 means success, anything else is an error
            if initialResponse.status == 2 {
                throw EASError.provisioningDenied
            }
            return initialResponse
        }

        // Step 2: Acknowledge policy (NO DeviceInformation - causes SyntaxError)
        let ackXml = buildProvisionAckXML(policyKey: policyKey)
        debugLog("Provision ack XML:\n\(ackXml)", module: "EAS", level: .info)
        var ackRequest = try buildRequest(command: "Provision", credentials: credentials, body: ackXml)
        ackRequest.setValue("0", forHTTPHeaderField: "X-MS-PolicyKey")

        let (data2, _) = try await executeRequest(ackRequest)
        return try parseProvisionResponse(data2)
    }

    /// Execute FolderSync to discover calendar folder
    func folderSync(syncKey: String, policyKey: String = "0") async throws -> FolderSyncResponse {
        let credentials = try getCredentials()
        let xmlBody = buildFolderSyncXML(syncKey: syncKey)
        var request = try buildRequest(command: "FolderSync", credentials: credentials, body: xmlBody)
        request.setValue(policyKey, forHTTPHeaderField: "X-MS-PolicyKey")

        let (data, _) = try await executeRequest(request)
        return try parseFolderSyncResponse(data)
    }

    /// Execute Sync command to get/create calendar items
    func sync(
        folderId: String,
        syncKey: String,
        getChanges: Bool = true,
        addItems: [EASCalendarEvent]? = nil,
        policyKey: String = "0"
    ) async throws -> SyncResponse {
        let credentials = try getCredentials()
        let xmlBody = buildSyncXML(
            folderId: folderId,
            syncKey: syncKey,
            getChanges: getChanges,
            addItems: addItems
        )
        var request = try buildRequest(command: "Sync", credentials: credentials, body: xmlBody)
        request.setValue(policyKey, forHTTPHeaderField: "X-MS-PolicyKey")

        let (data, _) = try await executeRequest(request)
        return try parseSyncResponse(data)
    }

    // MARK: - Request Building

    private func getCredentials() throws -> EASCredentials {
        guard let credentials = keychainManager.loadEASCredentials() else {
            throw EASError.noCredentials
        }
        return credentials
    }

    private func buildOptionsRequest(credentials: EASCredentials) throws -> URLRequest {
        guard let url = credentials.activeSyncURL else {
            throw EASError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        request.setValue(EASCredentials.protocolVersion, forHTTPHeaderField: "MS-ASProtocolVersion")
        request.setValue("VantaSpeech/1.0", forHTTPHeaderField: "User-Agent")

        return request
    }

    private func buildRequest(command: String, credentials: EASCredentials, body: String) throws -> URLRequest {
        guard let url = credentials.buildURL(command: command) else {
            throw EASError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        request.setValue(EASCredentials.protocolVersion, forHTTPHeaderField: "MS-ASProtocolVersion")
        request.setValue("0", forHTTPHeaderField: "X-MS-PolicyKey")
        request.setValue("VantaSpeech/1.0", forHTTPHeaderField: "User-Agent")

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
                throw EASError.parseError("Ошибка кодирования WBXML: \(error.localizedDescription)")
            }
        }

        return request
    }

    // MARK: - Request Execution

    private func executeRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // Check network availability
        guard isNetworkAvailable else {
            throw EASError.offline
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw EASError.networkError("Invalid response")
            }

            // Handle HTTP status codes
            switch httpResponse.statusCode {
            case 200:
                return (data, response)
            case 401:
                throw EASError.authenticationFailed
            case 403:
                throw EASError.accessDenied
            case 503:
                throw EASError.serverUnavailable
            default:
                let message = String(data: data, encoding: .utf8)
                throw EASError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
        } catch let error as EASError {
            throw error
        } catch {
            throw EASError.networkError(error.localizedDescription)
        }
    }

    // MARK: - XML Building

    private func buildFolderSyncXML(syncKey: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <FolderSync xmlns="FolderHierarchy">
            <SyncKey>\(syncKey)</SyncKey>
        </FolderSync>
        """
    }

    private func buildSyncXML(
        folderId: String,
        syncKey: String,
        getChanges: Bool,
        addItems: [EASCalendarEvent]?
    ) -> String {
        var commandsXml = ""

        if let items = addItems, !items.isEmpty {
            commandsXml = "<Commands>"
            for item in items {
                commandsXml += """
                <Add>
                    <ClientId>\(item.clientId ?? UUID().uuidString)</ClientId>
                    <ApplicationData>
                        \(item.toEASXml())
                    </ApplicationData>
                </Add>
                """
            }
            commandsXml += "</Commands>"
        }

        // For initial sync (SyncKey = "0"), don't include GetChanges, Options, or WindowSize
        // Just get the new SyncKey
        let isInitialSync = syncKey == "0"

        if isInitialSync {
            return """
            <?xml version="1.0" encoding="utf-8"?>
            <Sync xmlns="AirSync">
                <Collections>
                    <Collection>
                        <SyncKey>\(syncKey)</SyncKey>
                        <CollectionId>\(folderId)</CollectionId>
                    </Collection>
                </Collections>
            </Sync>
            """
        }

        // For subsequent syncs, include all options
        // FilterType for Calendar:
        //   0 = No filter (all items) - may not work on all servers
        //   4 = 2 weeks back
        //   5 = 1 month back (includes all future events)
        //   6 = 3 months back
        //   7 = 6 months back
        // Using FilterType 5 to ensure: 30 days back + all future events
        // Note: No namespace prefixes needed - WBXML encoder handles code page switching automatically
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <Sync>
            <Collections>
                <Collection>
                    <SyncKey>\(syncKey)</SyncKey>
                    <CollectionId>\(folderId)</CollectionId>
                    <GetChanges>\(getChanges ? "1" : "0")</GetChanges>
                    <WindowSize>100</WindowSize>
                    <Options>
                        <FilterType>5</FilterType>
                        <BodyPreference>
                            <Type>2</Type>
                            <TruncationSize>51200</TruncationSize>
                        </BodyPreference>
                    </Options>
                    \(commandsXml)
                </Collection>
            </Collections>
        </Sync>
        """
    }

    @MainActor
    private func getDeviceInfo() -> (model: String, osVersion: String) {
        let device = UIDevice.current
        return (device.model, device.systemVersion)
    }

    private func buildProvisionRequestXML(deviceModel: String, osVersion: String, deviceId: String) -> String {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"

        // Include all fields that some Exchange servers require
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <Provision xmlns="Provision">
            <DeviceInformation>
                <Set>
                    <Model>\(deviceModel)</Model>
                    <IMEI>\(deviceId)</IMEI>
                    <FriendlyName>VantaSpeech</FriendlyName>
                    <OS>iOS \(osVersion)</OS>
                    <OSLanguage>\(languageCode)</OSLanguage>
                    <PhoneNumber></PhoneNumber>
                    <MobileOperator></MobileOperator>
                    <UserAgent>VantaSpeech/1.0</UserAgent>
                </Set>
            </DeviceInformation>
            <Policies>
                <Policy>
                    <PolicyType>MS-EAS-Provisioning-WBXML</PolicyType>
                </Policy>
            </Policies>
        </Provision>
        """
    }

    private func buildProvisionAckXML(policyKey: String) -> String {
        // Acknowledgment must NOT contain DeviceInformation - causes SyntaxError (Status 2)
        // Only PolicyType, PolicyKey, and Status=1
        """
        <?xml version="1.0" encoding="utf-8"?>
        <Provision xmlns="Provision">
            <Policies>
                <Policy>
                    <PolicyType>MS-EAS-Provisioning-WBXML</PolicyType>
                    <PolicyKey>\(policyKey)</PolicyKey>
                    <Status>1</Status>
                </Policy>
            </Policies>
        </Provision>
        """
    }

    // MARK: - Response Parsing

    private func parseFolderSyncResponse(_ data: Data) throws -> FolderSyncResponse {
        let xmlString = try decodeResponseData(data)
        let parser = EASXMLParser(xml: xmlString)
        return try parser.parseFolderSync()
    }

    private func parseSyncResponse(_ data: Data) throws -> SyncResponse {
        let xmlString = try decodeResponseData(data)
        let parser = EASXMLParser(xml: xmlString)
        return try parser.parseSync()
    }

    private func parseProvisionResponse(_ data: Data) throws -> ProvisionResponse {
        let xmlString = try decodeResponseData(data)

        // Simple XML parsing for Provision response
        var status = 0
        var policyKey: String?

        // Extract Status
        if let statusRange = xmlString.range(of: "<Status>"),
           let statusEndRange = xmlString.range(of: "</Status>", range: statusRange.upperBound..<xmlString.endIndex) {
            let statusStr = String(xmlString[statusRange.upperBound..<statusEndRange.lowerBound])
            status = Int(statusStr) ?? 0
        }

        // Extract PolicyKey
        if let keyRange = xmlString.range(of: "<PolicyKey>"),
           let keyEndRange = xmlString.range(of: "</PolicyKey>", range: keyRange.upperBound..<xmlString.endIndex) {
            policyKey = String(xmlString[keyRange.upperBound..<keyEndRange.lowerBound])
        }

        return ProvisionResponse(status: status, policyKey: policyKey)
    }

    /// Decode response data, detecting WBXML vs XML
    private func decodeResponseData(_ data: Data) throws -> String {
        guard !data.isEmpty else {
            throw EASError.parseError("Пустой ответ от сервера")
        }

        // Check if response is WBXML (starts with 0x03 - version 1.3)
        if data.count > 0 && data[0] == 0x03 {
            // Decode WBXML to XML
            let decoder = WBXMLDecoder(data: data)
            do {
                let xmlString = try decoder.decode()
                debugLog("Decoded WBXML to XML:\n\(xmlString.prefix(3000))", module: "EAS", level: .info)
                // Check if there are attendees in the response
                if xmlString.contains("Attendee") || xmlString.contains("ttendee") {
                    debugLog("Response contains Attendee data!", module: "EAS", level: .info)
                }
                return xmlString
            } catch {
                throw EASError.parseError("Ошибка декодирования WBXML: \(error.localizedDescription)")
            }
        }

        // Try to decode as UTF-8
        guard let xmlString = String(data: data, encoding: .utf8) else {
            // Try to decode as ASCII
            if let asciiString = String(data: data, encoding: .ascii) {
                return asciiString
            }
            throw EASError.parseError("Невозможно декодировать ответ сервера")
        }

        // Check if it's an HTML error page
        let trimmed = xmlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype html") || trimmed.hasPrefix("<html") {
            // Extract error message from HTML if possible
            if xmlString.contains("401") || xmlString.lowercased().contains("unauthorized") {
                throw EASError.authenticationFailed
            }
            throw EASError.parseError("Сервер вернул HTML страницу вместо XML. Проверьте URL сервера.")
        }

        // Validate it starts with XML declaration or root element
        if !trimmed.hasPrefix("<?xml") && !trimmed.hasPrefix("<") {
            let preview = String(xmlString.prefix(200))
            throw EASError.parseError("Некорректный формат ответа: \(preview)")
        }

        return xmlString
    }
}

// MARK: - Response Types

/// Server info from OPTIONS response
struct EASServerInfo {
    let protocolVersions: [String]
    let supportedCommands: [String]

    var supportsVersion14: Bool {
        protocolVersions.contains { $0.hasPrefix("14") }
    }
}

/// Response from FolderSync command
struct FolderSyncResponse {
    let syncKey: String
    let folders: [EASFolder]
    let status: Int

    /// Find the default calendar folder
    var calendarFolder: EASFolder? {
        folders.first { $0.type == .defaultCalendar }
    }
}

/// Response from Sync command
struct SyncResponse {
    let syncKey: String
    let events: [EASCalendarEvent]
    let deletedEventIds: [String]
    let status: Int
    let moreAvailable: Bool
}

/// Response from Provision command
struct ProvisionResponse {
    let status: Int
    let policyKey: String?

    /// Whether provisioning was successful
    var isSuccess: Bool {
        status == 1 && policyKey != nil
    }
}
