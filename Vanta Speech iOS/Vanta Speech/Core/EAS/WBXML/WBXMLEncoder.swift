import Foundation

/// Encodes XML string to WBXML (WAP Binary XML) data
final class WBXMLEncoder {

    // MARK: - Properties

    private var output: [UInt8] = []
    private var currentCodePage: UInt8 = 0
    private var tagStack: [String] = []
    private var namespaceStack: [UInt8] = [] // Track namespace context

    /// Map root elements to their namespace code pages
    private let rootNamespaces: [String: UInt8] = [
        "Sync": EASCodePage.airSync.rawValue,
        "FolderSync": EASCodePage.folderHierarchy.rawValue,
        "Provision": EASCodePage.provision.rawValue,
        "Settings": EASCodePage.settings.rawValue,
        "SendMail": EASCodePage.composeEmail.rawValue,
        "SmartForward": EASCodePage.composeEmail.rawValue,
        "SmartReply": EASCodePage.composeEmail.rawValue
    ]

    /// Elements that switch namespace context
    private let contextSwitchElements: [String: UInt8] = [
        "DeviceInformation": EASCodePage.settings.rawValue,
        "Policies": EASCodePage.provision.rawValue,
        "Policy": EASCodePage.provision.rawValue,
        "BodyPreference": EASCodePage.airSyncBase.rawValue,
        "Body": EASCodePage.airSyncBase.rawValue,
        "ApplicationData": EASCodePage.calendar.rawValue
    ]

    // MARK: - Public API

    /// Encode XML string to WBXML data
    func encode(_ xml: String) throws -> Data {
        output = []
        namespaceStack = []

        // Write header
        writeHeader()

        // Parse and encode XML
        try parseAndEncode(xml)

        return Data(output)
    }

    // MARK: - Header

    private func writeHeader() {
        // WBXML version 1.3
        output.append(0x03)

        // Public ID (unknown = 0x01)
        output.append(0x01)

        // Charset (UTF-8 = 106 = 0x6A)
        output.append(0x6A)

        // String table length (0 = no string table)
        output.append(0x00)
    }

    // MARK: - XML Parsing and Encoding

    private func parseAndEncode(_ xml: String) throws {
        // Simple XML parser
        var index = xml.startIndex
        let end = xml.endIndex

        while index < end {
            // Skip whitespace
            while index < end && xml[index].isWhitespace {
                index = xml.index(after: index)
            }

            guard index < end else { break }

            if xml[index] == "<" {
                index = xml.index(after: index)

                // Skip XML declaration
                if index < end && xml[index] == "?" {
                    // Skip until ?>
                    if let closeIndex = xml.range(of: "?>", range: index..<end)?.upperBound {
                        index = closeIndex
                        continue
                    }
                }

                // Check for closing tag
                if index < end && xml[index] == "/" {
                    index = xml.index(after: index)
                    // Read tag name
                    let tagStart = index
                    while index < end && xml[index] != ">" && !xml[index].isWhitespace {
                        index = xml.index(after: index)
                    }
                    _ = String(xml[tagStart..<index])

                    // Skip to >
                    while index < end && xml[index] != ">" {
                        index = xml.index(after: index)
                    }
                    if index < end {
                        index = xml.index(after: index)
                    }

                    // Write END token
                    output.append(WBXMLToken.end.rawValue)
                    if !tagStack.isEmpty {
                        tagStack.removeLast()
                    }
                    // Pop namespace context
                    if !namespaceStack.isEmpty {
                        namespaceStack.removeLast()
                    }
                    continue
                }

                // Read tag name
                let tagStart = index
                while index < end && xml[index] != ">" && xml[index] != "/" && !xml[index].isWhitespace {
                    index = xml.index(after: index)
                }
                let tagName = String(xml[tagStart..<index])

                // Skip attributes (for now)
                while index < end && xml[index] != ">" && xml[index] != "/" {
                    index = xml.index(after: index)
                }

                // Check for self-closing tag
                let selfClosing = index < end && xml[index] == "/"
                if selfClosing {
                    index = xml.index(after: index)
                }

                // Skip >
                if index < end && xml[index] == ">" {
                    index = xml.index(after: index)
                }

                // Determine namespace context for this element
                var elementNamespace: UInt8?
                if let rootNs = rootNamespaces[tagName] {
                    elementNamespace = rootNs
                } else if let contextNs = contextSwitchElements[tagName] {
                    elementNamespace = contextNs
                }

                // Write tag
                try writeTag(tagName, hasContent: !selfClosing)

                if !selfClosing {
                    tagStack.append(tagName)
                    // Push namespace context (use element's namespace or inherit from parent)
                    let nsContext = elementNamespace ?? namespaceStack.last ?? 0
                    namespaceStack.append(nsContext)
                }
            } else {
                // Text content
                let textStart = index
                while index < end && xml[index] != "<" {
                    index = xml.index(after: index)
                }
                let text = String(xml[textStart..<index]).trimmingCharacters(in: .whitespacesAndNewlines)

                if !text.isEmpty {
                    writeInlineString(text)
                }
            }
        }
    }

    // MARK: - Tag Writing

    private func writeTag(_ name: String, hasContent: Bool) throws {
        // Determine code page and tag value
        let (codePage, tagValue) = try lookupTag(name)

        // Switch code page if needed
        if codePage != currentCodePage {
            output.append(WBXMLToken.switchPage.rawValue)
            output.append(codePage)
            currentCodePage = codePage
        }

        // Write tag token
        var token = tagValue
        if hasContent {
            token |= WBXML_HAS_CONTENT
        }
        output.append(token)
    }

    private func writeInlineString(_ string: String) {
        output.append(WBXMLToken.strI.rawValue)
        if let data = string.data(using: .utf8) {
            output.append(contentsOf: data)
        }
        output.append(0x00) // null terminator
    }

    // MARK: - Tag Lookup

    private func lookupTag(_ name: String) throws -> (codePage: UInt8, tag: UInt8) {
        // First, try to find tag in current namespace context
        if let currentNs = namespaceStack.last {
            if let result = lookupTagInCodePage(name, codePage: currentNs) {
                return result
            }
        }

        // Then search all namespaces in priority order
        let searchOrder: [(UInt8, [UInt8: String])] = [
            (EASCodePage.composeEmail.rawValue, composeMailTags),
            (EASCodePage.provision.rawValue, provisionTags),
            (EASCodePage.settings.rawValue, settingsTags),
            (EASCodePage.folderHierarchy.rawValue, folderHierarchyTags),
            (EASCodePage.airSync.rawValue, airSyncTags),
            (EASCodePage.calendar.rawValue, calendarTags),
            (EASCodePage.airSyncBase.rawValue, airSyncBaseTags)
        ]

        for (codePage, tags) in searchOrder {
            if let result = lookupTagInCodePage(name, codePage: codePage, tags: tags) {
                return result
            }
        }

        throw WBXMLError.decodingFailed("Unknown tag: \(name)")
    }

    private func lookupTagInCodePage(_ name: String, codePage: UInt8) -> (codePage: UInt8, tag: UInt8)? {
        let tags: [UInt8: String]
        switch codePage {
        case EASCodePage.airSync.rawValue:
            tags = airSyncTags
        case EASCodePage.calendar.rawValue:
            tags = calendarTags
        case EASCodePage.folderHierarchy.rawValue:
            tags = folderHierarchyTags
        case EASCodePage.airSyncBase.rawValue:
            tags = airSyncBaseTags
        case EASCodePage.provision.rawValue:
            tags = provisionTags
        case EASCodePage.settings.rawValue:
            tags = settingsTags
        case EASCodePage.composeEmail.rawValue:
            tags = composeMailTags
        default:
            return nil
        }
        return lookupTagInCodePage(name, codePage: codePage, tags: tags)
    }

    private func lookupTagInCodePage(_ name: String, codePage: UInt8, tags: [UInt8: String]) -> (codePage: UInt8, tag: UInt8)? {
        for (tag, tagName) in tags {
            if tagName == name {
                return (codePage, tag)
            }
        }
        return nil
    }
}
