import Foundation

/// Utility for toggling markdown checkboxes in text
struct MarkdownCheckboxToggler {

    /// Toggle a checkbox at the given line index
    /// Supports multiple formats: "- [ ] ", "* [ ] ", "[ ] ", "- [] ", "[] "
    /// - Parameters:
    ///   - text: The markdown text containing checkboxes
    ///   - lineIndex: The line number (0-indexed) to toggle
    /// - Returns: The updated markdown text with toggled checkbox
    static func toggleCheckbox(in text: String, at lineIndex: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lineIndex >= 0 && lineIndex < lines.count else { return text }

        let line = lines[lineIndex]

        // Standard format: "- [ ] " / "- [x] "
        if line.contains("- [ ] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        }
        else if line.contains("- [x] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
        }
        else if line.contains("- [X] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [X] ", with: "- [ ] ")
        }
        // Asterisk format: "* [ ] " / "* [x] "
        else if line.contains("* [ ] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [ ] ", with: "* [x] ")
        }
        else if line.contains("* [x] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [x] ", with: "* [ ] ")
        }
        else if line.contains("* [X] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [X] ", with: "* [ ] ")
        }
        // Without dash: "[ ] " / "[x] "
        else if line.contains("[ ] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "[ ] ", with: "[x] ")
        }
        else if line.contains("[x] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "[x] ", with: "[ ] ")
        }
        else if line.contains("[X] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "[X] ", with: "[ ] ")
        }
        // Compact format: "- [] " / "[] "
        else if line.contains("- [] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [] ", with: "- [x] ")
        }
        else if line.contains("[] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "[] ", with: "[x] ")
        }

        return lines.joined(separator: "\n")
    }

    /// Find all checkbox lines in markdown text
    /// - Parameter text: The markdown text to search
    /// - Returns: Array of tuples with (lineIndex, isChecked, taskText)
    static func findCheckboxLines(in text: String) -> [(index: Int, isChecked: Bool, text: String)] {
        let lines = text.components(separatedBy: "\n")
        var result: [(Int, Bool, String)] = []

        for (index, line) in lines.enumerated() {
            if let parsed = parseCheckboxLine(line) {
                result.append((index, parsed.isChecked, parsed.text))
            }
        }

        return result
    }

    /// Check if a line is a checkbox line
    /// Supports multiple formats: "- [ ] ", "* [ ] ", "[ ] ", "- [] ", "[] "
    /// - Parameter line: The line to check
    /// - Returns: Tuple of (isChecked, text) or nil if not a checkbox
    static func parseCheckboxLine(_ line: String) -> (isChecked: Bool, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Standard format: "- [ ] " / "- [x] "
        if trimmed.hasPrefix("- [ ] ") {
            return (false, String(trimmed.dropFirst(6)))
        }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return (true, String(trimmed.dropFirst(6)))
        }

        // Asterisk format: "* [ ] " / "* [x] "
        if trimmed.hasPrefix("* [ ] ") {
            return (false, String(trimmed.dropFirst(6)))
        }
        if trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") {
            return (true, String(trimmed.dropFirst(6)))
        }

        // Without dash: "[ ] " / "[x] "
        if trimmed.hasPrefix("[ ] ") {
            return (false, String(trimmed.dropFirst(4)))
        }
        if trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
            return (true, String(trimmed.dropFirst(4)))
        }

        // Compact format: "- [] " / "[] "
        if trimmed.hasPrefix("- [] ") {
            return (false, String(trimmed.dropFirst(5)))
        }
        if trimmed.hasPrefix("[] ") {
            return (false, String(trimmed.dropFirst(3)))
        }

        return nil
    }
}
