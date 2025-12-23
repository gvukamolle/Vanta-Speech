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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseBlocks(), id: \.id) { block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func blockView(for block: MarkdownBlock) -> some View {
        Group {
            switch block.type {
            case .heading(let level):
                Text(try! AttributedString(markdown: block.content))
                    .font(fontForHeading(level))
                    .fontWeight(.bold)
                    .padding(.top, level == 1 ? 8 : 4)

            case .paragraph:
                if let attributed = try? AttributedString(markdown: block.content) {
                    Text(attributed)
                        .textSelection(.enabled)
                } else {
                    Text(block.content)
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
    }

    private func fontForHeading(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var currentParagraph = ""
        var inCodeBlock = false
        var codeContent = ""
        var listItems: [String] = []
        var listType: MarkdownBlock.BlockType?

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

        for line in lines {
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
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeContent += line + "\n"
                continue
            }

            // Divider
            if trimmedLine == "---" || trimmedLine == "***" || trimmedLine == "___" {
                flushParagraph()
                flushList()
                blocks.append(MarkdownBlock(type: .divider, content: ""))
                continue
            }

            // Headings
            if let match = trimmedLine.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                flushParagraph()
                flushList()
                let level = match.1.count
                let content = String(match.2)
                blocks.append(MarkdownBlock(type: .heading(level), content: content))
                continue
            }

            // Blockquote
            if trimmedLine.hasPrefix("> ") {
                flushParagraph()
                flushList()
                let content = String(trimmedLine.dropFirst(2))
                blocks.append(MarkdownBlock(type: .blockquote, content: content))
                continue
            }

            // Bullet list
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                flushParagraph()
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

        return blocks
    }
}

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let type: BlockType
    let content: String
    var items: [String] = []

    enum BlockType: Equatable {
        case heading(Int)
        case paragraph
        case bulletList
        case numberedList
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

#Preview("Markdown") {
    ScrollView {
        MarkdownContentView(text: """
        # Meeting Summary

        ## Key Points

        - First important point with **bold text**
        - Second point with *italic*
        - Third point with `code`

        ## Action Items

        1. Review the proposal
        2. Send feedback to team
        3. Schedule follow-up meeting

        > This is a blockquote with important notes

        ```
        Some code example
        let x = 42
        ```

        ---

        Final paragraph with [link](https://example.com).
        """)
        .padding()
    }
}
