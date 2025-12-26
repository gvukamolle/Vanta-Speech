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
                            .fill(.ultraThinMaterial)
                        Circle()
                            .fill(Color.pinkVibrant.opacity(0.15))
                        Image(systemName: statusIcon)
                            .font(.system(size: 18))
                            .foregroundStyle(statusColor)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

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
                        .background {
                            ZStack {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                Capsule()
                                    .fill(Color.pinkVibrant.opacity(0.15))
                            }
                        }
                        .clipShape(Capsule())
                }

                // Status bar
                HStack(spacing: 16) {
                    // Transcription status
                    statusBadge(
                        icon: "text.bubble",
                        text: recording.isTranscribed ? "Транскрибировано" : "Не транскрибировано",
                        isActive: recording.isTranscribed
                    )

                    // Summary status
                    statusBadge(
                        icon: "doc.text",
                        text: recording.summaryText != nil ? "Саммари" : "Нет саммари",
                        isActive: recording.summaryText != nil
                    )

                    Spacer()

                    // Upload indicator
                    if recording.isUploading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Загрузка")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .vantaGlassCard(cornerRadius: 24, shadowRadius: 0, tintOpacity: 0.15)
            .vantaHover(.lift)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        if recording.isUploading {
            return .blueVibrant
        } else if recording.isTranscribed {
            return .pinkVibrant
        } else {
            return .blueVibrant
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
        .foregroundStyle(isActive ? Color.pinkVibrant : .secondary)
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
                                colors: [.pinkLight.opacity(0.5), .blueLight.opacity(0.5)],
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
                        Label("Транскрибировано", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.pinkVibrant)
                    } else if recording.isUploading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Обработка...")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.blueVibrant)
                    } else {
                        Label("Готово к транскрипции", systemImage: "text.bubble")
                            .font(.caption)
                            .foregroundStyle(Color.blueVibrant)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .vantaGlassCard(cornerRadius: 28, shadowRadius: 0, tintOpacity: 0.15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview("Card") {
    VStack(spacing: 16) {
        RecordingCard(recording: Recording(
            title: "Еженедельный созвон",
            duration: 1845,
            audioFileURL: "/test.ogg",
            transcriptionText: "Это превью текста транскрипции...",
            isTranscribed: true
        ))

        RecordingCard(recording: Recording(
            title: "Встреча с клиентом",
            duration: 3600,
            audioFileURL: "/test.ogg",
            isUploading: true
        ))

        RecordingCardLarge(recording: Recording(
            title: "Планирование продукта",
            duration: 2700,
            audioFileURL: "/test.ogg"
        ))
    }
    .padding()
    .background(Color(.systemGray6))
}
