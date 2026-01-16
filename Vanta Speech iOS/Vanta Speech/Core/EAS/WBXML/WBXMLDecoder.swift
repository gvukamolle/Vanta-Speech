import Foundation

/// Decodes WBXML (WAP Binary XML) data to XML string
final class WBXMLDecoder {

    // MARK: - Properties

    private var data: Data
    private var position: Int = 0
    private var currentCodePage: UInt8 = 0
    private var stringTable: [String] = []

    // MARK: - Initialization

    init(data: Data) {
        self.data = data
    }

    // MARK: - Public API

    /// Decode WBXML data to XML string
    func decode() throws -> String {
        position = 0

        // Parse header
        try parseHeader()

        // Parse body
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        xml += try parseBody()

        return xml
    }

    // MARK: - Header Parsing

    private func parseHeader() throws {
        // Version (1 byte) - should be 0x03 for WBXML 1.3
        let version = try readByte()
        guard version == 0x03 else {
            throw WBXMLError.unsupportedVersion(version)
        }

        // Public ID (mb_u_int32)
        _ = try readMultiByteInt()

        // Charset (mb_u_int32) - typically 106 for UTF-8
        _ = try readMultiByteInt()

        // String table length and data
        let stringTableLength = try readMultiByteInt()
        if stringTableLength > 0 {
            try parseStringTable(length: stringTableLength)
        }
    }

    private func parseStringTable(length: Int) throws {
        let endPosition = position + length
        var strings: [String] = []
        var currentString = ""

        while position < endPosition {
            let byte = try readByte()
            if byte == 0x00 {
                strings.append(currentString)
                currentString = ""
            } else {
                currentString += String(UnicodeScalar(byte))
            }
        }

        if !currentString.isEmpty {
            strings.append(currentString)
        }

        stringTable = strings
    }

    // MARK: - Body Parsing

    private func parseBody() throws -> String {
        var xml = ""

        while position < data.count {
            let token = try readByte()
            xml += try processToken(token)
        }

        return xml
    }

    private func processToken(_ token: UInt8) throws -> String {
        // Handle special tokens
        switch token {
        case WBXMLToken.switchPage.rawValue:
            currentCodePage = try readByte()
            return ""

        case WBXMLToken.end.rawValue:
            return ""

        case WBXMLToken.strI.rawValue:
            let str = try readInlineString()
            return escapeXML(str)

        case WBXMLToken.strT.rawValue:
            let index = try readMultiByteInt()
            if index < stringTable.count {
                return escapeXML(stringTable[index])
            }
            return ""

        case WBXMLToken.opaque.rawValue:
            let length = try readMultiByteInt()
            let opaqueData = try readBytes(length)
            // Try to decode as UTF-8 string, otherwise base64
            if let str = String(data: opaqueData, encoding: .utf8) {
                return escapeXML(str)
            } else {
                return opaqueData.base64EncodedString()
            }

        default:
            // It's a tag
            return try processTag(token)
        }
    }

    private func processTag(_ token: UInt8) throws -> String {
        let hasContent = (token & WBXML_HAS_CONTENT) != 0
        let hasAttributes = (token & WBXML_HAS_ATTRIBUTES) != 0
        let tagName = getTagName(codePage: currentCodePage, tag: token)

        var xml = "<\(tagName)"

        // Parse attributes if present
        if hasAttributes {
            xml += try parseAttributes()
        }

        if hasContent {
            xml += ">"
            xml += try parseContent()
            xml += "</\(tagName)>"
        } else {
            xml += "/>"
        }

        return xml
    }

    private func parseAttributes() throws -> String {
        var attributes = ""

        while position < data.count {
            let token = try peekByte()

            if token == WBXMLToken.end.rawValue {
                _ = try readByte() // consume END
                break
            }

            // Skip attribute parsing for now (not commonly used in EAS)
            _ = try readByte()
        }

        return attributes
    }

    private func parseContent() throws -> String {
        var content = ""

        while position < data.count {
            let token = try peekByte()

            if token == WBXMLToken.end.rawValue {
                _ = try readByte() // consume END
                break
            }

            _ = try readByte() // consume token
            content += try processToken(token)
        }

        return content
    }

    // MARK: - Reading Helpers

    private func readByte() throws -> UInt8 {
        guard position < data.count else {
            throw WBXMLError.unexpectedEndOfData
        }
        let byte = data[position]
        position += 1
        return byte
    }

    private func peekByte() throws -> UInt8 {
        guard position < data.count else {
            throw WBXMLError.unexpectedEndOfData
        }
        return data[position]
    }

    private func readBytes(_ count: Int) throws -> Data {
        guard position + count <= data.count else {
            throw WBXMLError.unexpectedEndOfData
        }
        let bytes = data.subdata(in: position..<(position + count))
        position += count
        return bytes
    }

    /// Read multi-byte integer (mb_u_int32)
    private func readMultiByteInt() throws -> Int {
        var result = 0

        while true {
            let byte = try readByte()
            result = (result << 7) | Int(byte & 0x7F)

            if (byte & 0x80) == 0 {
                break
            }
        }

        return result
    }

    /// Read null-terminated inline string
    private func readInlineString() throws -> String {
        var bytes: [UInt8] = []

        while true {
            let byte = try readByte()
            if byte == 0x00 {
                break
            }
            bytes.append(byte)
        }

        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    // MARK: - XML Escaping

    private func escapeXML(_ string: String) -> String {
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        return escaped
    }
}

// MARK: - Errors

enum WBXMLError: LocalizedError {
    case unsupportedVersion(UInt8)
    case unexpectedEndOfData
    case invalidToken(UInt8)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Неподдерживаемая версия WBXML: \(version)"
        case .unexpectedEndOfData:
            return "Неожиданный конец данных WBXML"
        case .invalidToken(let token):
            return "Неизвестный токен WBXML: \(token)"
        case .decodingFailed(let message):
            return "Ошибка декодирования WBXML: \(message)"
        }
    }
}
