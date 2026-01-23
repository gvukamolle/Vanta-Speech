import Foundation

/// Конвертер Markdown → Confluence Storage Format (XHTML)
enum MarkdownToConfluence {

    // MARK: - Public API

    /// Конвертировать Markdown в Confluence Storage Format
    static func convert(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var xhtml: [String] = []

        var i = 0
        var inCodeBlock = false
        var codeBlockLines: [String] = []
        var codeLanguage: String?

        // List tracking
        var inUnorderedList = false
        var inOrderedList = false
        var inTaskList = false

        while i < lines.count {
            let line = lines[i]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Code block handling
            if trimmedLine.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    xhtml.append(renderCodeBlock(codeBlockLines, language: codeLanguage))
                    codeBlockLines = []
                    codeLanguage = nil
                    inCodeBlock = false
                } else {
                    // Close any open lists first
                    closeOpenLists(&xhtml, &inUnorderedList, &inOrderedList, &inTaskList)
                    // Extract language
                    let lang = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
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

            // Table detection
            if trimmedLine.contains("|") && !trimmedLine.isEmpty && !trimmedLine.hasPrefix("|--") {
                closeOpenLists(&xhtml, &inUnorderedList, &inOrderedList, &inTaskList)

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
                xhtml.append(renderTable(tableRows))
                i = j
                continue
            }

            // Empty line
            if trimmedLine.isEmpty {
                closeOpenLists(&xhtml, &inUnorderedList, &inOrderedList, &inTaskList)
                i += 1
                continue
            }

            // Horizontal rule
            if trimmedLine == "---" || trimmedLine == "***" || trimmedLine == "___" {
                closeOpenLists(&xhtml, &inUnorderedList, &inOrderedList, &inTaskList)
                xhtml.append("<hr/>")
                i += 1
                continue
            }

            // Headers
            if let headerMatch = trimmedLine.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                closeOpenLists(&xhtml, &inUnorderedList, &inOrderedList, &inTaskList)
                let level = headerMatch.1.count
                let text = String(headerMatch.2)
                xhtml.append("<h\(level)>\(processInline(text))</h\(level)>")
                i += 1
                continue
            }

            // Blockquote → Confluence Info panel
            if trimmedLine.hasPrefix("> ") {
                closeOpenLists(&xhtml, &inUnorderedList, &inOrderedList, &inTaskList)
                let quoteText = String(trimmedLine.dropFirst(2))
                xhtml.append("""
                <ac:structured-macro ac:name="info">
                <ac:rich-text-body><p>\(processInline(quoteText))</p></ac:rich-text-body>
                </ac:structured-macro>
                """)
                i += 1
                continue
            }

            // Checklist → Confluence Task List
            if let checkMatch = trimmedLine.firstMatch(of: /^-\s*\[([ xX])\]\s+(.+)$/) {
                if inOrderedList {
                    xhtml.append("</ol>")
                    inOrderedList = false
                }
                if inUnorderedList && !inTaskList {
                    xhtml.append("</ul>")
                    inUnorderedList = false
                }
                if !inTaskList {
                    xhtml.append("<ac:task-list>")
                    inTaskList = true
                }
                let isChecked = checkMatch.1 != " "
                let text = String(checkMatch.2)
                let status = isChecked ? "complete" : "incomplete"
                xhtml.append("""
                <ac:task>
                <ac:task-status>\(status)</ac:task-status>
                <ac:task-body><span class="placeholder-inline-tasks">\(processInline(text))</span></ac:task-body>
                </ac:task>
                """)
                i += 1
                continue
            }

            // Unordered list
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                if inTaskList {
                    xhtml.append("</ac:task-list>")
                    inTaskList = false
                }
                if inOrderedList {
                    xhtml.append("</ol>")
                    inOrderedList = false
                }
                if !inUnorderedList {
                    xhtml.append("<ul>")
                    inUnorderedList = true
                }
                let text = String(trimmedLine.dropFirst(2))
                xhtml.append("<li>\(processInline(text))</li>")
                i += 1
                continue
            }

            // Ordered list
            if let orderedMatch = trimmedLine.firstMatch(of: /^(\d+)\.\s+(.+)$/) {
                if inTaskList {
                    xhtml.append("</ac:task-list>")
                    inTaskList = false
                }
                if inUnorderedList {
                    xhtml.append("</ul>")
                    inUnorderedList = false
                }
                if !inOrderedList {
                    xhtml.append("<ol>")
                    inOrderedList = true
                }
                let text = String(orderedMatch.2)
                xhtml.append("<li>\(processInline(text))</li>")
                i += 1
                continue
            }

            // Regular paragraph
            closeOpenLists(&xhtml, &inUnorderedList, &inOrderedList, &inTaskList)
            xhtml.append("<p>\(processInline(trimmedLine))</p>")
            i += 1
        }

        // Close remaining lists
        closeOpenLists(&xhtml, &inUnorderedList, &inOrderedList, &inTaskList)

        if inCodeBlock {
            xhtml.append(renderCodeBlock(codeBlockLines, language: codeLanguage))
        }

        return xhtml.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private static func closeOpenLists(
        _ xhtml: inout [String],
        _ inUnorderedList: inout Bool,
        _ inOrderedList: inout Bool,
        _ inTaskList: inout Bool
    ) {
        if inTaskList {
            xhtml.append("</ac:task-list>")
            inTaskList = false
        }
        if inUnorderedList {
            xhtml.append("</ul>")
            inUnorderedList = false
        }
        if inOrderedList {
            xhtml.append("</ol>")
            inOrderedList = false
        }
    }

    /// Обработка inline форматирования
    private static func processInline(_ text: String) -> String {
        var result = escapeXML(text)

        // Inline code
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )

        // Bold + Italic
        result = result.replacingOccurrences(
            of: "\\*\\*\\*(.+?)\\*\\*\\*",
            with: "<strong><em>$1</em></strong>",
            options: .regularExpression
        )

        // Bold
        result = result.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic (not matching ** which is bold)
        result = result.replacingOccurrences(
            of: "(?<!\\*)\\*(?!\\*)([^*]+)(?<!\\*)\\*(?!\\*)",
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Strikethrough
        result = result.replacingOccurrences(
            of: "~~(.+?)~~",
            with: "<span style=\"text-decoration: line-through;\">$1</span>",
            options: .regularExpression
        )

        // Links [text](url)
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        return result
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Render code block using ac:structured-macro
    private static func renderCodeBlock(_ lines: [String], language: String?) -> String {
        let code = lines.joined(separator: "\n")
        let lang = language ?? "none"

        return """
        <ac:structured-macro ac:name="code">
        <ac:parameter ac:name="language">\(lang)</ac:parameter>
        <ac:parameter ac:name="theme">Confluence</ac:parameter>
        <ac:plain-text-body><![CDATA[\(code)]]></ac:plain-text-body>
        </ac:structured-macro>
        """
    }

    /// Render table
    private static func renderTable(_ rows: [String]) -> String {
        guard rows.count >= 2 else { return "" }

        var xhtml = "<table class=\"confluenceTable\"><tbody>"

        for (index, row) in rows.enumerated() {
            // Skip separator row (|---|---|)
            if row.contains("---") || row.contains(":--") { continue }

            let cells = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard !cells.isEmpty else { continue }

            let isHeader = index == 0
            let tag = isHeader ? "th" : "td"
            let cellClass = isHeader ? "confluenceTh" : "confluenceTd"

            xhtml += "<tr>"
            for cell in cells {
                xhtml += "<\(tag) class=\"\(cellClass)\">\(processInline(cell))</\(tag)>"
            }
            xhtml += "</tr>"
        }

        xhtml += "</tbody></table>"
        return xhtml
    }
}
