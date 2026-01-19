import Foundation

/// Конвертер Markdown → HTML для email
/// Поддерживает все основные элементы MD с инлайновыми стилями (email-safe)
enum MarkdownToHTML {

    // MARK: - Styles

    /// Инлайн стили для email (не используем CSS классы)
    private enum Styles {
        // Typography
        static let h1 = "font-size:24px;font-weight:bold;color:#1a1a1a;margin:20px 0 12px 0;padding:0;"
        static let h2 = "font-size:20px;font-weight:bold;color:#1a1a1a;margin:18px 0 10px 0;padding:0;"
        static let h3 = "font-size:16px;font-weight:bold;color:#1a1a1a;margin:14px 0 8px 0;padding:0;"
        static let paragraph = "margin:8px 0;padding:0;line-height:1.5;color:#333333;"

        // Lists
        static let ul = "margin:8px 0;padding-left:24px;"
        static let ol = "margin:8px 0;padding-left:24px;"
        static let li = "margin:4px 0;line-height:1.5;color:#333333;"

        // Checklist
        static let checklistItem = "margin:4px 0;line-height:1.5;color:#333333;"
        static let checklistDone = "margin:4px 0;line-height:1.5;color:#888888;text-decoration:line-through;"
        static let checkbox = "font-size:14px;margin-right:8px;"

        // Table
        static let table = "border-collapse:collapse;margin:12px 0;width:100%;font-size:14px;"
        static let th = "background:#f5f5f5;font-weight:bold;padding:10px 12px;border:1px solid #ddd;text-align:left;color:#1a1a1a;"
        static let td = "padding:10px 12px;border:1px solid #ddd;color:#333333;"

        // Blockquote
        static let blockquote = "margin:12px 0;padding:12px 16px;border-left:4px solid #4a90d9;background:#f8f9fa;color:#555555;font-style:italic;"

        // Code
        static let inlineCode = "background:#f0f0f0;padding:2px 6px;border-radius:4px;font-family:monospace;font-size:13px;color:#c7254e;"
        static let codeBlock = "background:#f5f5f5;padding:12px 16px;border-radius:6px;font-family:monospace;font-size:13px;overflow-x:auto;margin:12px 0;white-space:pre-wrap;color:#333333;"

        // Horizontal rule
        static let hr = "border:none;border-top:1px solid #e0e0e0;margin:20px 0;"
    }

    // MARK: - Public API

    /// Конвертировать Markdown в HTML
    /// - Parameter markdown: Markdown текст
    /// - Returns: HTML строка с инлайновыми стилями
    static func convert(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html: [String] = []

        var i = 0
        var inCodeBlock = false
        var codeBlockLines: [String] = []

        // List tracking
        var inUnorderedList = false
        var inOrderedList = false

        while i < lines.count {
            let line = lines[i]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Code block handling
            if trimmedLine.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    html.append(renderCodeBlock(codeBlockLines))
                    codeBlockLines = []
                    inCodeBlock = false
                } else {
                    // Start code block - close any open lists first
                    if inUnorderedList {
                        html.append("</ul>")
                        inUnorderedList = false
                    }
                    if inOrderedList {
                        html.append("</ol>")
                        inOrderedList = false
                    }
                    inCodeBlock = true
                }
                i += 1
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                i += 1
                continue
            }

            // Table detection - check if this line and next look like a table
            if trimmedLine.contains("|") && !trimmedLine.isEmpty {
                // Close any open lists
                if inUnorderedList {
                    html.append("</ul>")
                    inUnorderedList = false
                }
                if inOrderedList {
                    html.append("</ol>")
                    inOrderedList = false
                }

                // Collect table rows
                var tableRows: [String] = [line]
                var j = i + 1
                while j < lines.count {
                    let nextLine = lines[j].trimmingCharacters(in: .whitespaces)
                    if nextLine.contains("|") && !nextLine.isEmpty {
                        tableRows.append(lines[j])
                        j += 1
                    } else {
                        break
                    }
                }
                html.append(renderTable(tableRows))
                i = j
                continue
            }

            // Empty line - close lists
            if trimmedLine.isEmpty {
                if inUnorderedList {
                    html.append("</ul>")
                    inUnorderedList = false
                }
                if inOrderedList {
                    html.append("</ol>")
                    inOrderedList = false
                }
                i += 1
                continue
            }

            // Horizontal rule
            if trimmedLine == "---" || trimmedLine == "***" || trimmedLine == "___" {
                if inUnorderedList {
                    html.append("</ul>")
                    inUnorderedList = false
                }
                if inOrderedList {
                    html.append("</ol>")
                    inOrderedList = false
                }
                html.append("<hr style=\"\(Styles.hr)\">")
                i += 1
                continue
            }

            // Headers
            if let headerMatch = trimmedLine.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                if inUnorderedList {
                    html.append("</ul>")
                    inUnorderedList = false
                }
                if inOrderedList {
                    html.append("</ol>")
                    inOrderedList = false
                }
                let level = headerMatch.1.count
                let text = String(headerMatch.2)
                html.append(renderHeader(level: level, text: text))
                i += 1
                continue
            }

            // Blockquote
            if trimmedLine.hasPrefix("> ") {
                if inUnorderedList {
                    html.append("</ul>")
                    inUnorderedList = false
                }
                if inOrderedList {
                    html.append("</ol>")
                    inOrderedList = false
                }
                let quoteText = String(trimmedLine.dropFirst(2))
                html.append("<blockquote style=\"\(Styles.blockquote)\">\(processInline(quoteText))</blockquote>")
                i += 1
                continue
            }

            // Checklist (must check before regular list)
            if let checkMatch = trimmedLine.firstMatch(of: /^-\s*\[([ xX])\]\s+(.+)$/) {
                if inOrderedList {
                    html.append("</ol>")
                    inOrderedList = false
                }
                if !inUnorderedList {
                    html.append("<ul style=\"\(Styles.ul);list-style:none;padding-left:0;\">")
                    inUnorderedList = true
                }
                let isChecked = checkMatch.1 != " "
                let text = String(checkMatch.2)
                let checkbox = isChecked ? "☑" : "☐"
                let style = isChecked ? Styles.checklistDone : Styles.checklistItem
                html.append("<li style=\"\(style)\"><span style=\"\(Styles.checkbox)\">\(checkbox)</span>\(processInline(text))</li>")
                i += 1
                continue
            }

            // Unordered list
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                if inOrderedList {
                    html.append("</ol>")
                    inOrderedList = false
                }
                if !inUnorderedList {
                    html.append("<ul style=\"\(Styles.ul)\">")
                    inUnorderedList = true
                }
                let text = String(trimmedLine.dropFirst(2))
                html.append("<li style=\"\(Styles.li)\">\(processInline(text))</li>")
                i += 1
                continue
            }

            // Ordered list
            if let orderedMatch = trimmedLine.firstMatch(of: /^(\d+)\.\s+(.+)$/) {
                if inUnorderedList {
                    html.append("</ul>")
                    inUnorderedList = false
                }
                if !inOrderedList {
                    html.append("<ol style=\"\(Styles.ol)\">")
                    inOrderedList = true
                }
                let text = String(orderedMatch.2)
                html.append("<li style=\"\(Styles.li)\">\(processInline(text))</li>")
                i += 1
                continue
            }

            // Regular paragraph
            if inUnorderedList {
                html.append("</ul>")
                inUnorderedList = false
            }
            if inOrderedList {
                html.append("</ol>")
                inOrderedList = false
            }
            html.append("<p style=\"\(Styles.paragraph)\">\(processInline(trimmedLine))</p>")
            i += 1
        }

        // Close any remaining open lists
        if inUnorderedList {
            html.append("</ul>")
        }
        if inOrderedList {
            html.append("</ol>")
        }
        if inCodeBlock {
            html.append(renderCodeBlock(codeBlockLines))
        }

        return html.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Обработка инлайн-форматирования (жирный, курсив, код)
    private static func processInline(_ text: String) -> String {
        var result = escapeHTML(text)

        // Inline code `code` → <code>
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code style=\"\(Styles.inlineCode)\">$1</code>",
            options: .regularExpression
        )

        // Bold + Italic ***text*** → <strong><em>
        result = result.replacingOccurrences(
            of: "\\*\\*\\*(.+?)\\*\\*\\*",
            with: "<strong><em>$1</em></strong>",
            options: .regularExpression
        )

        // Bold **text** → <strong>
        result = result.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic *text* → <em> (not matching ** which is bold)
        result = result.replacingOccurrences(
            of: "(?<!\\*)\\*(?!\\*)([^*]+)(?<!\\*)\\*(?!\\*)",
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Preserve <br> tags
        result = result.replacingOccurrences(of: "&lt;br&gt;", with: "<br>")
        result = result.replacingOccurrences(of: "&lt;br/&gt;", with: "<br>")
        result = result.replacingOccurrences(of: "&lt;br /&gt;", with: "<br>")

        return result
    }

    /// Escape HTML special characters
    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Render header element
    private static func renderHeader(level: Int, text: String) -> String {
        let style: String
        switch level {
        case 1: style = Styles.h1
        case 2: style = Styles.h2
        default: style = Styles.h3
        }
        return "<h\(level) style=\"\(style)\">\(processInline(text))</h\(level)>"
    }

    /// Render code block
    private static func renderCodeBlock(_ lines: [String]) -> String {
        let code = lines.map { escapeHTML($0) }.joined(separator: "\n")
        return "<pre style=\"\(Styles.codeBlock)\">\(code)</pre>"
    }

    /// Render table
    private static func renderTable(_ rows: [String]) -> String {
        guard rows.count >= 2 else { return "" }

        var html = "<table style=\"\(Styles.table)\">"

        for (index, row) in rows.enumerated() {
            // Skip separator row (|---|---|)
            if row.contains("---") || row.contains(":--") { continue }

            let cells = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard !cells.isEmpty else { continue }

            let isHeader = index == 0
            let tag = isHeader ? "th" : "td"
            let style = isHeader ? Styles.th : Styles.td

            html += "<tr>"
            for cell in cells {
                // Support <br> in table cells
                let processedCell = processInline(cell)
                html += "<\(tag) style=\"\(style)\">\(processedCell)</\(tag)>"
            }
            html += "</tr>"
        }

        html += "</table>"
        return html
    }
}
