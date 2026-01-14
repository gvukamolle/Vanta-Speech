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
    var isSummaryGenerating: Bool
    var presetRawValue: String?

    /// The meeting preset used for this recording
    var preset: RecordingPreset? {
        get { presetRawValue.flatMap { RecordingPreset(rawValue: $0) } }
        set { presetRawValue = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileURL: String,
        transcriptionText: String? = nil,
        summaryText: String? = nil,
        isTranscribed: Bool = false,
        isUploading: Bool = false,
        isSummaryGenerating: Bool = false,
        preset: RecordingPreset? = nil
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
        self.isSummaryGenerating = isSummaryGenerating
        self.presetRawValue = preset?.rawValue
    }
}

extension Recording {
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
