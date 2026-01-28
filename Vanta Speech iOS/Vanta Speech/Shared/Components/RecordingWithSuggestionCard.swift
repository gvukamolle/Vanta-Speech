import SwiftUI
import SwiftData

/// Объединённая карточка записи с предложением встречи (для новых записей)
struct RecordingWithSuggestionCard: View {
    let recording: Recording
    let suggestedEvent: EASCalendarEvent
    let onConfirm: () -> Void
    let onSelectOther: () -> Void
    let onDismiss: () -> Void
    let onTapRecording: () -> Void
    let onDelete: (() -> Void)?
    var onTranscribe: (() -> Void)?
    var onViewTranscription: (() -> Void)?
    var onGenerateSummary: (() -> Void)?
    var onViewSummary: (() -> Void)?
    
    @State private var isConfirmed = false
    @State private var isTransitioning = false
    @State private var showSuggestion = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Верхняя часть: информация о записи (всегда видна)
            recordingInfoSection
            
            // MARK: - Нижняя часть: предложение встречи (скрывается при переходе)
            if showSuggestion && !isTransitioning {
                suggestionSection
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            }
        }
        .vantaGlassCard(cornerRadius: 24, shadowRadius: 0, tintOpacity: 0.15)
        .vantaHover(.lift)
        .clipped()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSuggestion)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isTransitioning)
    }
    
    // MARK: - Recording Info Section
    
    private var recordingInfoSection: some View {
        Button(action: onTapRecording) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with icon and title
                HStack {
                    // Recording icon
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                        Circle()
                            .fill(Color.pinkVibrant.opacity(0.15))
                        Image(systemName: isConfirmed ? "checkmark.circle" : "waveform")
                            .font(.system(size: 18))
                            .foregroundStyle(isConfirmed ? Color.green : Color.blueVibrant)
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
                
                // Статус привязки (показывается после подтверждения)
                if isConfirmed {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text("Привязано к: \(suggestedEvent.subject)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.green)
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTransitioning)
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
    
    // MARK: - Suggestion Section
    
    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Разделитель
            Divider()
                .padding(.horizontal, 16)
                .opacity(0.5)
            
            // Header with icon and label
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("Предлагаемая встреча")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // Meeting info
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(Color.blueVibrant)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestedEvent.subject)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        Label(formatTime(suggestedEvent.startTime), systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !suggestedEvent.humanAttendees.isEmpty {
                            Label("\(suggestedEvent.humanAttendees.count)", systemImage: "person.2")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // Action buttons - три кнопки с новыми цветами
            HStack(spacing: 10) {
                // Cancel button - тёмно-красный фон, красный текст
                Button {
                    performTransition {
                        onDismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.caption)
                        Text("Отмена")
                            .font(.caption)
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                
                // Other button - серый фон, белый текст
                Button {
                    onSelectOther()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                        Text("Другая")
                            .font(.caption)
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                
                // Confirm button - зелёный фон, тёмно-зелёный текст
                Button {
                    performTransition {
                        recording.linkToMeeting(suggestedEvent)
                        isConfirmed = true
                        onConfirm()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption)
                        Text("Связать")
                            .font(.caption)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.green.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 4)
    }
    
    // MARK: - Transition Animation
    
    private func performTransition(completion: @escaping () -> Void) {
        withAnimation(.easeInOut(duration: 0.25)) {
            isTransitioning = true
            showSuggestion = false
        }
        
        // Вызываем callback после завершения анимации
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            completion()
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    VStack {
        RecordingWithSuggestionCard(
            recording: Recording(
                title: "Project Meeting 28 янв., 19:19",
                duration: 1845,
                audioFileURL: "/test.ogg"
            ),
            suggestedEvent: EASCalendarEvent(
                id: "test",
                subject: "Груминг POS",
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                attendees: []
            ),
            onConfirm: {},
            onSelectOther: {},
            onDismiss: {},
            onTapRecording: {},
            onDelete: nil
        )
    }
    .padding()
    .background(Color(.systemGray6))
}
