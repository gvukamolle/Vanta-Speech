import Foundation
import SwiftData

@Model
final class Recording {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFileURL: String
    var transcriptionText: String?
    var summaryText: String?
    var isTranscribed: Bool
    var isUploading: Bool

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileURL: String,
        transcriptionText: String? = nil,
        summaryText: String? = nil,
        isTranscribed: Bool = false,
        isUploading: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionText = transcriptionText
        self.summaryText = summaryText
        self.isTranscribed = isTranscribed
        self.isUploading = isUploading
    }
}

extension Recording {
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(createdAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Today, \(formatter.string(from: createdAt))"
        } else if calendar.isDateInYesterday(createdAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Yesterday, \(formatter.string(from: createdAt))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: createdAt)
        }
    }

    var transcriptionPreview: String? {
        guard let text = transcriptionText else { return nil }
        if text.count > 150 {
            return String(text.prefix(150)) + "..."
        }
        return text
    }
}

enum AudioQuality: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }

    var bitrate: Int {
        switch self {
        case .low: return 64
        case .medium: return 96
        case .high: return 128
        }
    }

    var label: String {
        switch self {
        case .low: return "Low (64 kbps)"
        case .medium: return "Medium (96 kbps)"
        case .high: return "High (128 kbps)"
        }
    }
}
