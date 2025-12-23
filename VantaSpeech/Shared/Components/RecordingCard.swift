import SwiftUI

/// Card component for displaying a recording in the library
struct RecordingCard: View {
    let recording: Recording
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with status
                HStack {
                    // Recording icon
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: statusIcon)
                            .font(.system(size: 18))
                            .foregroundStyle(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(recording.formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Duration badge
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                // Status bar
                HStack(spacing: 16) {
                    // Transcription status
                    statusBadge(
                        icon: "text.bubble",
                        text: recording.isTranscribed ? "Transcribed" : "Not transcribed",
                        isActive: recording.isTranscribed
                    )

                    // Summary status
                    statusBadge(
                        icon: "doc.text",
                        text: recording.summaryText != nil ? "Summary" : "No summary",
                        isActive: recording.summaryText != nil
                    )

                    Spacer()

                    // Upload indicator
                    if recording.isUploading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Uploading")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Preview of transcription if available
                if let transcription = recording.transcriptionText, !transcription.isEmpty {
                    Text(transcription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 4)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        if recording.isUploading {
            return .orange
        } else if recording.isTranscribed {
            return .green
        } else {
            return .blue
        }
    }

    private var statusIcon: String {
        if recording.isUploading {
            return "arrow.up.circle"
        } else if recording.isTranscribed {
            return "checkmark.circle"
        } else {
            return "waveform"
        }
    }

    @ViewBuilder
    private func statusBadge(icon: String, text: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(isActive ? .green : .secondary)
    }
}

/// Large card variant for featured/recent recording
struct RecordingCardLarge: View {
    let recording: Recording
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Waveform visualization placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 80)

                    HStack(spacing: 2) {
                        ForEach(0..<30, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.6))
                                .frame(width: 4, height: CGFloat.random(in: 10...40))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(recording.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack {
                        Label(recording.formattedDate, systemImage: "calendar")
                        Spacer()
                        Label(recording.formattedDuration, systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Action buttons
                HStack(spacing: 12) {
                    if recording.isTranscribed {
                        Label("Transcribed", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if recording.isUploading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Processing...")
                                .font(.caption)
                        }
                        .foregroundStyle(.orange)
                    } else {
                        Label("Ready to transcribe", systemImage: "text.bubble")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Card") {
    VStack(spacing: 16) {
        RecordingCard(recording: Recording(
            title: "Weekly Team Sync",
            duration: 1845,
            audioFileURL: "/test.ogg",
            transcriptionText: "This is a preview of the transcription text that was generated...",
            isTranscribed: true
        ))

        RecordingCard(recording: Recording(
            title: "Client Meeting",
            duration: 3600,
            audioFileURL: "/test.ogg",
            isUploading: true
        ))

        RecordingCardLarge(recording: Recording(
            title: "Product Planning Session",
            duration: 2700,
            audioFileURL: "/test.ogg"
        ))
    }
    .padding()
    .background(Color(.systemGray6))
}
