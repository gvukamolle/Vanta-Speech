import SwiftUI

/// Card component for displaying a recording in the library
struct RecordingCard: View {
    let recording: Recording
    var onTap: () -> Void = {}
    var onDelete: (() -> Void)?
    var onTranscribe: (() -> Void)?
    var onViewTranscription: (() -> Void)?
    var onGenerateSummary: (() -> Void)?
    var onViewSummary: (() -> Void)?

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
                    if recording.isSummaryGenerating {
                        statusBadge(
                            icon: "sparkles",
                            text: "Анализ...",
                            isActive: true,
                            isAnimating: true
                        )
                    } else if recording.summaryText != nil {
                        statusBadge(
                            icon: "doc.text",
                            text: "Саммари",
                            isActive: true
                        )
                    } else if recording.isTranscribed && onGenerateSummary != nil {
                        // Кликабельный бейдж для генерации саммари
                        Button(action: onGenerateSummary!) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.caption2)
                                Text("Сгенерировать")
                                    .font(.caption2)
                            }
                            .foregroundStyle(Color.blueVibrant)
                        }
                        .buttonStyle(.plain)
                    } else {
                        statusBadge(
                            icon: "doc.text",
                            text: "Нет саммари",
                            isActive: false
                        )
                    }

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
        .contextMenu {
            // MARK: - Динамические кнопки в зависимости от состояния записи
            
            // Случай 1: Нет расшифровки → кнопка "Расшифровать"
            if !recording.isTranscribed, let onTranscribe {
                Button {
                    onTranscribe()
                } label: {
                    Label {
                        Text("Расшифровать")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.primary)
                    }
                }
                .tint(.primary)
            }
            
            // Случай 2: Есть расшифровка → кнопка "Расшифровка"
            if recording.isTranscribed, let onViewTranscription {
                Button {
                    onViewTranscription()
                } label: {
                    Label {
                        Text("Расшифровка")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "text.bubble.fill")
                            .foregroundStyle(.primary)
                    }
                }
                .tint(.primary)
            }
            
            // Случай 3: Есть расшифровка, но нет саммари → кнопка "Сделать саммари"
            if recording.isTranscribed && recording.summaryText == nil && !recording.isSummaryGenerating, let onGenerateSummary {
                Button {
                    onGenerateSummary()
                } label: {
                    Label {
                        Text("Сделать саммари")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.primary)
                    }
                }
                .tint(.primary)
            }
            
            // Случай 4: Есть саммари → кнопка "Саммари"
            if recording.summaryText != nil, let onViewSummary {
                Button {
                    onViewSummary()
                } label: {
                    Label {
                        Text("Саммари")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.primary)
                    }
                }
                .tint(.primary)
            }
            
            // Кнопка "Удалить" всегда внизу, красным
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label {
                        Text("Удалить")
                            .foregroundStyle(.red)
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .tint(.red)
            }
        }
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
    private func statusBadge(icon: String, text: String, isActive: Bool, isAnimating: Bool = false) -> some View {
        HStack(spacing: 4) {
            if isAnimating {
                Image(systemName: icon)
                    .font(.caption2)
                    .symbolEffect(.pulse.byLayer, options: .repeating, isActive: true)
            } else {
                Image(systemName: icon)
                    .font(.caption2)
            }
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
                        Label("Готово к расшифровке", systemImage: "text.bubble")
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
