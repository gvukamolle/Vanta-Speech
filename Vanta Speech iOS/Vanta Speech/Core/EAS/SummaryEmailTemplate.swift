import Foundation

/// Контекст данных для шаблона email с саммари
struct SummaryEmailContext {
    // Meeting info
    let meetingSubject: String
    let meetingLocation: String?
    let meetingStartTime: Date?
    let meetingEndTime: Date?
    let meetingDuration: String?

    // Attendees
    let attendeeNames: [String]
    let attendeeCount: Int

    // Recording info
    let recordingTitle: String
    let presetDisplayName: String

    // Summary
    let summaryMarkdown: String

    // Config
    let feedbackEmail: String

    // MARK: - Computed

    /// Formatted meeting time string
    var formattedMeetingTime: String? {
        guard let start = meetingStartTime else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        var result = dateFormatter.string(from: start)

        if let end = meetingEndTime {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            result += " — " + timeFormatter.string(from: end)
        }

        if let duration = meetingDuration {
            result += " (\(duration))"
        }

        return result
    }

    /// Formatted attendees string (показывает первых 3 + счётчик остальных)
    var formattedAttendees: String {
        guard !attendeeNames.isEmpty else {
            return "\(attendeeCount) участник\(pluralSuffix(attendeeCount))"
        }

        if attendeeNames.count <= 3 {
            return attendeeNames.joined(separator: ", ")
        } else {
            let first3 = attendeeNames.prefix(3).joined(separator: ", ")
            let remaining = attendeeNames.count - 3
            return "\(first3) +\(remaining)"
        }
    }

    private func pluralSuffix(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100

        if mod100 >= 11 && mod100 <= 19 {
            return "ов"
        }

        switch mod10 {
        case 1: return ""
        case 2, 3, 4: return "а"
        default: return "ов"
        }
    }
}

/// HTML шаблон для email с саммари встречи
enum SummaryEmailTemplate {

    // MARK: - Colors

    private enum Colors {
        static let background = "#f5f5f5"
        static let cardBackground = "#ffffff"
        static let headerBackground = "#1a1a1a"
        static let headerText = "#ffffff"
        static let primaryText = "#1a1a1a"
        static let secondaryText = "#666666"
        static let border = "#e0e0e0"
        static let accent = "#4a90d9"
        static let buttonBackground = "#4a90d9"
        static let buttonText = "#ffffff"
    }

    // MARK: - Public API

    /// Сгенерировать HTML email из контекста
    /// - Parameter context: Данные для шаблона
    /// - Returns: HTML строка
    static func render(context: SummaryEmailContext) -> String {
        let summaryHTML = MarkdownToHTML.convert(context.summaryMarkdown)

        return """
        <!DOCTYPE html>
        <html lang="ru">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Саммари: \(escapeHTML(context.meetingSubject))</title>
        </head>
        <body style="margin:0;padding:0;background-color:\(Colors.background);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                <tr>
                    <td align="center" style="padding:20px 10px;">
                        <!-- Main Container -->
                        <table role="presentation" width="600" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;width:100%;background-color:\(Colors.cardBackground);border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">

                            <!-- Header -->
                            \(renderHeader(context: context))

                            <!-- Meeting Info -->
                            \(renderMeetingInfo(context: context))

                            <!-- Summary Content + Footer -->
                            \(renderSummaryContent(summaryHTML: summaryHTML, context: context))

                        </table>
                    </td>
                </tr>
            </table>
        </body>
        </html>
        """
    }

    // MARK: - Private Sections

    private static func renderHeader(context: SummaryEmailContext) -> String {
        """
        <tr>
            <td style="background-color:\(Colors.headerBackground);padding:24px 24px 20px;">
                <h1 style="margin:0 0 8px;font-size:20px;font-weight:600;color:\(Colors.headerText);line-height:1.3;">
                    \(escapeHTML(context.recordingTitle))
                </h1>
                <p style="margin:0;font-size:14px;color:rgba(255,255,255,0.7);">
                    \(escapeHTML(context.presetDisplayName))
                </p>
            </td>
        </tr>
        """
    }

    private static func renderMeetingInfo(context: SummaryEmailContext) -> String {
        var infoItems: [String] = []

        // Meeting subject (if different from recording title)
        if context.meetingSubject != context.recordingTitle {
            infoItems.append(infoRow(icon: "📅", label: "Встреча", value: context.meetingSubject))
        }

        // Location
        if let location = context.meetingLocation, !location.isEmpty {
            infoItems.append(infoRow(icon: "📍", label: "Место", value: location))
        }

        // Attendees
        if context.attendeeCount > 0 {
            infoItems.append(infoRow(icon: "👥", label: "Участники", value: context.formattedAttendees))
        }

        // Time
        if let time = context.formattedMeetingTime {
            infoItems.append(infoRow(icon: "🕐", label: "Время", value: time))
        }

        // If no info items, return empty
        guard !infoItems.isEmpty else { return "" }

        return """
        <tr>
            <td style="padding:20px 24px;border-bottom:1px solid \(Colors.border);">
                \(infoItems.joined(separator: "\n"))
            </td>
        </tr>
        """
    }

    private static func infoRow(icon: String, label: String, value: String) -> String {
        """
        <p style="margin:0 0 8px;font-size:14px;color:\(Colors.secondaryText);line-height:1.5;">
            <span style="margin-right:8px;">\(icon)</span>
            <span style="color:\(Colors.primaryText);font-weight:500;">\(escapeHTML(value))</span>
        </p>
        """
    }

    private static func renderSummaryContent(summaryHTML: String, context: SummaryEmailContext) -> String {
        let subject = "Отзыв о Vanta Speech".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Feedback"
        let mailtoURL = "mailto:\(context.feedbackEmail)?subject=\(subject)"

        return """
        <tr>
            <td style="padding:24px;">
                \(summaryHTML)

                <!-- Separator -->
                <hr style="border:none;border-top:1px solid \(Colors.border);margin:24px 0 16px 0;">

                <!-- Footer text -->
                <p style="margin:0;font-size:12px;color:\(Colors.secondaryText);text-align:center;">
                    Сделано в <strong>Vanta Speech</strong>
                </p>
            </td>
        </tr>

        <!-- Feedback link -->
        <tr>
            <td style="padding:0 24px 20px;text-align:center;">
                <a href="\(mailtoURL)" style="font-size:12px;color:\(Colors.secondaryText);text-decoration:underline;">
                    Оставить отзыв
                </a>
            </td>
        </tr>
        """
    }

    // MARK: - Helpers

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
