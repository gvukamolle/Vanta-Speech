import SwiftUI

/// Renders Markdown text using SwiftUI's native AttributedString
struct MarkdownView: View {
    let text: String
    @State private var attributedText: AttributedString?

    var body: some View {
        Group {
            if let attributedText = attributedText {
                Text(attributedText)
                    .textSelection(.enabled)
            } else {
                Text(text)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            parseMarkdown()
        }
        .onChange(of: text) { _, _ in
            parseMarkdown()
        }
    }

    private func parseMarkdown() {
        do {
            attributedText = try AttributedString(markdown: text, options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            ))
        } catch {
            attributedText = nil
        }
    }
}

/// Full Markdown renderer with proper block element support
struct MarkdownContentView: View {
    let text: String
    /// Callback when a checkbox is toggled. Parameter is the line number (0-indexed) in the original text.
    var onCheckboxToggle: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseBlocks(), id: \.id) { block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block.type {
        case .heading(let level):
            if let attributed = try? AttributedString(markdown: block.content) {
                Text(attributed)
                    .font(fontForHeading(level))
                    .fontWeight(.bold)
                    .padding(.top, level == 1 ? 8 : 4)
            } else {
                Text(block.content)
                    .font(fontForHeading(level))
                    .fontWeight(.bold)
                    .padding(.top, level == 1 ? 8 : 4)
            }

        case .paragraph:
            let processedContent = processBrTags(block.content)
            if let attributed = try? AttributedString(markdown: processedContent) {
                Text(attributed)
                    .textSelection(.enabled)
            } else {
                Text(processedContent)
                    .textSelection(.enabled)
            }

        case .bulletList:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(block.items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        if let attributed = try? AttributedString(markdown: item) {
                            Text(attributed)
                                .textSelection(.enabled)
                        } else {
                            Text(item)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(.leading, 8)

        case .numberedList:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        if let attributed = try? AttributedString(markdown: item) {
                            Text(attributed)
                                .textSelection(.enabled)
                        } else {
                            Text(item)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

        case .taskList:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(block.taskItems, id: \.lineNumber) { task in
                    HStack(alignment: .top, spacing: 8) {
                        // Make checkbox tappable if callback is provided
                        if let onToggle = onCheckboxToggle {
                            Button {
                                onToggle(task.lineNumber)
                            } label: {
                                Image(systemName: task.isChecked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(task.isChecked ? .green : .secondary)
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Image(systemName: task.isChecked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(task.isChecked ? .green : .secondary)
                                .font(.body)
                        }

                        if let attributed = try? AttributedString(markdown: task.text) {
                            Text(attributed)
                                .textSelection(.enabled)
                                .strikethrough(task.isChecked, color: .secondary)
                                .foregroundStyle(task.isChecked ? .secondary : .primary)
                        } else {
                            Text(task.text)
                                .textSelection(.enabled)
                                .strikethrough(task.isChecked, color: .secondary)
                                .foregroundStyle(task.isChecked ? .secondary : .primary)
                        }
                    }
                }
            }
            .padding(.leading, 8)

        case .table:
            tableView(for: block)

        case .codeBlock:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .blockquote:
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 4)

                if let attributed = try? AttributedString(markdown: block.content) {
                    Text(attributed)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text(block.content)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)

        case .divider:
            Divider()
                .padding(.vertical, 8)
        }
    }

    // MARK: - Table View

    @ViewBuilder
    private func tableView(for block: MarkdownBlock) -> some View {
        if block.tableRows.isEmpty {
            EmptyView()
        } else {
            let columnCount = block.tableRows.first?.count ?? 0
            let screenWidth = UIScreen.main.bounds.width
            let firstColumnWidth = screenWidth / 3
            let otherColumnWidth = screenWidth / 2

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    if let headerRow = block.tableRows.first {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(headerRow.enumerated()), id: \.offset) { index, cell in
                                Text(cell)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(width: index == 0 ? firstColumnWidth : otherColumnWidth, alignment: .leading)

                                if index < columnCount - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(.systemGray5))
                    }

                    // Divider after header
                    Divider()

                    // Data rows
                    ForEach(Array(block.tableRows.dropFirst().enumerated()), id: \.offset) { rowIndex, row in
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                                    let processedCell = processBrTags(cell)

                                    Group {
                                        if let attributed = try? AttributedString(markdown: processedCell) {
                                            Text(attributed)
                                        } else {
                                            Text(processedCell)
                                        }
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(width: index == 0 ? firstColumnWidth : otherColumnWidth, alignment: .leading)
                                    .textSelection(.enabled)

                                    if index < columnCount - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .background(rowIndex % 2 == 0 ? Color.clear : Color(.systemGray6).opacity(0.5))

                            if rowIndex < block.tableRows.count - 2 {
                                Divider()
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
        }
    }

    /// Process <br> tags to newlines
    private func processBrTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
    }

    private func fontForHeading(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    // MARK: - Parsing

    private func parseBlocks() -> [MarkdownBlock] {
        // NOTE: Don't replace <br> globally - it breaks table rows
        // We handle <br> when rendering individual cells/paragraphs instead

        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var currentParagraph = ""
        var inCodeBlock = false
        var codeContent = ""
        var listItems: [String] = []
        var listType: MarkdownBlock.BlockType?
        var taskItems: [MarkdownBlock.TaskItem] = []
        var tableRows: [[String]] = []
        var inTable = false
        var lineIndex = 0

        func flushParagraph() {
            let trimmed = currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(MarkdownBlock(type: .paragraph, content: trimmed))
            }
            currentParagraph = ""
        }

        func flushList() {
            if !listItems.isEmpty, let type = listType {
                blocks.append(MarkdownBlock(type: type, content: "", items: listItems))
                listItems = []
                listType = nil
            }
        }

        func flushTaskList() {
            if !taskItems.isEmpty {
                blocks.append(MarkdownBlock(type: .taskList, content: "", taskItems: taskItems))
                taskItems = []
            }
        }

        func flushTable() {
            if !tableRows.isEmpty {
                blocks.append(MarkdownBlock(type: .table, content: "", tableRows: tableRows))
                tableRows = []
                inTable = false
            }
        }

        /// Parse task list item supporting multiple formats:
        /// - Standard: "- [ ] Task" or "- [x] Task"
        /// - With asterisk: "* [ ] Task" or "* [x] Task"
        /// - Without dash: "[ ] Task" or "[x] Task"
        func parseTaskListItem(_ line: String) -> (isChecked: Bool, text: String)? {
            // Standard formats with dash
            if line.hasPrefix("- [ ] ") {
                return (isChecked: false, text: String(line.dropFirst(6)))
            }
            if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                return (isChecked: true, text: String(line.dropFirst(6)))
            }

            // Asterisk format
            if line.hasPrefix("* [ ] ") {
                return (isChecked: false, text: String(line.dropFirst(6)))
            }
            if line.hasPrefix("* [x] ") || line.hasPrefix("* [X] ") {
                return (isChecked: true, text: String(line.dropFirst(6)))
            }

            // Without dash/asterisk (fallback for LLM variations)
            if line.hasPrefix("[ ] ") {
                return (isChecked: false, text: String(line.dropFirst(4)))
            }
            if line.hasPrefix("[x] ") || line.hasPrefix("[X] ") {
                return (isChecked: true, text: String(line.dropFirst(4)))
            }

            // Compact format without space inside brackets
            if line.hasPrefix("- [] ") {
                return (isChecked: false, text: String(line.dropFirst(5)))
            }
            if line.hasPrefix("[] ") {
                return (isChecked: false, text: String(line.dropFirst(3)))
            }

            return nil
        }

        for (index, line) in lines.enumerated() {
            lineIndex = index
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Code block
            if trimmedLine.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(MarkdownBlock(type: .codeBlock, content: codeContent.trimmingCharacters(in: .newlines)))
                    codeContent = ""
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    flushList()
                    flushTaskList()
                    flushTable()
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeContent += line + "\n"
                continue
            }

            // Table row (starts and ends with |)
            if trimmedLine.hasPrefix("|") && trimmedLine.hasSuffix("|") {
                flushParagraph()
                flushList()
                flushTaskList()

                // Check if it's a separator row (|---|---|)
                let isSeparator = trimmedLine.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
                if isSeparator {
                    inTable = true
                    continue
                }

                // Parse table cells
                let cells = trimmedLine
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                tableRows.append(cells)
                inTable = true
                continue
            }

            // If we were in a table and hit a non-table line, flush it
            if inTable && !trimmedLine.hasPrefix("|") {
                flushTable()
            }

            // Divider
            if trimmedLine == "---" || trimmedLine == "***" || trimmedLine == "___" {
                flushParagraph()
                flushList()
                flushTaskList()
                flushTable()
                blocks.append(MarkdownBlock(type: .divider, content: ""))
                continue
            }

            // Headings
            if let match = trimmedLine.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                flushParagraph()
                flushList()
                flushTaskList()
                flushTable()
                let level = match.1.count
                let content = String(match.2)
                blocks.append(MarkdownBlock(type: .heading(level), content: content))
                continue
            }

            // Blockquote
            if trimmedLine.hasPrefix("> ") {
                flushParagraph()
                flushList()
                flushTaskList()
                flushTable()
                let content = String(trimmedLine.dropFirst(2))
                blocks.append(MarkdownBlock(type: .blockquote, content: content))
                continue
            }

            // Task list (checkbox) - must check before bullet list
            // Support multiple formats: "- [ ] ", "* [ ] ", "[ ] " (without dash)
            if let taskMatch = parseTaskListItem(trimmedLine) {
                flushParagraph()
                flushList()
                flushTable()

                taskItems.append(MarkdownBlock.TaskItem(isChecked: taskMatch.isChecked, text: taskMatch.text, lineNumber: lineIndex))
                continue
            }

            // Bullet list
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                flushParagraph()
                flushTaskList()
                flushTable()
                if listType != .bulletList {
                    flushList()
                    listType = .bulletList
                }
                listItems.append(String(trimmedLine.dropFirst(2)))
                continue
            }

            // Numbered list
            if let match = trimmedLine.firstMatch(of: /^\d+\.\s+(.+)$/) {
                flushParagraph()
                flushTaskList()
                flushTable()
                if listType != .numberedList {
                    flushList()
                    listType = .numberedList
                }
                listItems.append(String(match.1))
                continue
            }

            // Empty line
            if trimmedLine.isEmpty {
                flushParagraph()
                flushList()
                flushTaskList()
                flushTable()
                continue
            }

            // Regular paragraph
            if !currentParagraph.isEmpty {
                currentParagraph += " "
            }
            currentParagraph += trimmedLine
        }

        flushParagraph()
        flushList()
        flushTaskList()
        flushTable()

        return blocks
    }
}

// MARK: - Data Models

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let type: BlockType
    let content: String
    var items: [String] = []
    var taskItems: [TaskItem] = []
    var tableRows: [[String]] = []

    struct TaskItem: Hashable {
        let isChecked: Bool
        let text: String
        let lineNumber: Int  // Line number in original text (0-indexed)
    }

    enum BlockType: Equatable {
        case heading(Int)
        case paragraph
        case bulletList
        case numberedList
        case taskList
        case table
        case codeBlock
        case blockquote
        case divider
    }
}

/// Copyable text field with copy button
struct CopyableTextField: View {
    let title: String
    let text: String
    let icon: String
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)

                Spacer()

                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Copied" : "Copy")
                    }
                    .font(.caption)
                    .foregroundStyle(showCopied ? .green : .accentColor)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollView {
                MarkdownContentView(text: text)
                    .padding()
            }
            .frame(maxHeight: 300)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

#Preview("Markdown with Tables & Tasks") {
    ScrollView {
        MarkdownContentView(text: """
        # Meeting Summary

        ## Key Points

        | Раздел | Содержание |
        |--------|------------|
        | Тема 1 | Обсуждение **важных** вопросов |
        | Тема 2 | Планирование *следующих* шагов |
        | Тема 3 | Итоги встречи |

        ## Action Items

        - [ ] Review the proposal
        - [x] Send feedback to team
        - [ ] Schedule follow-up meeting
        - [x] Complete documentation

        ## Regular List

        - First point with **bold text**
        - Second point with *italic*
        - Third point with `code`

        > This is a blockquote with important notes

        ---

        Final paragraph with line<br>break in the middle.
        """)
        .padding()
    }
}
