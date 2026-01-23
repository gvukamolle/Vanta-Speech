import Foundation

/// Форматтер страницы встречи для Confluence
enum MeetingPageFormatter {

    // MARK: - Public API

    /// Форматировать Recording в Confluence Storage Format
    static func format(recording: Recording) -> String {
        var sections: [String] = []

        // Заголовок
        sections.append(formatHeader(recording: recording))

        // Панель с метаданными
        sections.append(formatMetadataPanel(recording: recording))

        // Саммари контент
        if let summary = recording.summaryText, !summary.isEmpty {
            sections.append(formatSummaryContent(summary))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Private Methods

    /// Заголовок страницы
    private static func formatHeader(recording: Recording) -> String {
        let title = recording.linkedMeetingSubject ?? recording.title
        return "<h1>\(escapeXML(title))</h1>"
    }

    /// Панель с метаданными встречи
    private static func formatMetadataPanel(recording: Recording) -> String {
        let dateString = formatDate(recording.createdAt)
        let durationString = formatDuration(recording.duration)

        var rows: [String] = []

        // Дата
        rows.append("""
        <tr>
        <th style="width:120px">Дата</th>
        <td><time datetime="\(formatISO8601(recording.createdAt))"/></td>
        </tr>
        """)

        // Длительность
        rows.append("""
        <tr>
        <th>Длительность</th>
        <td>\(durationString)</td>
        </tr>
        """)

        // Участники (если есть)
        let attendees = recording.linkedMeetingAttendeeEmails
        if !attendees.isEmpty {
            let attendeesHtml = attendees.map { formatUserMention($0) }.joined(separator: ", ")
            rows.append("""
            <tr>
            <th>Участники</th>
            <td>\(attendeesHtml)</td>
            </tr>
            """)
        }

        // Организатор (если есть)
        if let organizer = recording.linkedMeetingOrganizerEmail {
            rows.append("""
            <tr>
            <th>Организатор</th>
            <td>\(formatUserMention(organizer))</td>
            </tr>
            """)
        }

        return """
        <ac:structured-macro ac:name="panel">
        <ac:parameter ac:name="title">Информация о встрече</ac:parameter>
        <ac:rich-text-body>
        <table class="confluenceTable">
        <tbody>
        \(rows.joined(separator: "\n"))
        </tbody>
        </table>
        </ac:rich-text-body>
        </ac:structured-macro>
        """
    }

    /// Форматирование саммари контента
    private static func formatSummaryContent(_ summary: String) -> String {
        // Конвертируем Markdown в Confluence Storage Format
        return MarkdownToConfluence.convert(summary)
    }

    // MARK: - Formatting Helpers

    /// Форматирование упоминания пользователя
    /// Преобразует email (a.verbitsky@pos-credit.ru) в ссылку на профиль Confluence
    private static func formatUserMention(_ email: String) -> String {
        // Извлекаем username из email (часть до @)
        let username: String
        if let atIndex = email.firstIndex(of: "@") {
            username = String(email[..<atIndex])
        } else {
            username = email
        }

        // Возвращаем ссылку на профиль — Confluence сам её распарсит в mention
        return "https://cnfl.b2serv.local/display/~\(username)"
    }

    /// Форматирование даты для отображения
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy, HH:mm"
        return formatter.string(from: date)
    }

    /// Форматирование даты в ISO8601 для <time> тега
    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    /// Форматирование длительности
    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration) / 60
        if totalMinutes < 60 {
            return "\(totalMinutes) мин"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return "\(hours) ч"
            } else {
                return "\(hours) ч \(minutes) мин"
            }
        }
    }

    /// Экранирование XML спецсимволов
    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
