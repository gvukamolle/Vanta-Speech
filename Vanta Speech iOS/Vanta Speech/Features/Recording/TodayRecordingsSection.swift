import SwiftUI
import SwiftData

struct TodayRecordingsSection: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var allRecordings: [Recording]
    @State private var selectedRecording: Recording?
    @Environment(\.modelContext) private var modelContext
    @StateObject private var calendarManager = EASCalendarManager.shared
    @State private var recordingForSuggestion: Recording?
    @State private var showEventPickerForSuggestion = false
    @State private var showAllEventsPicker = false
    @State private var dismissedSuggestions = Set<UUID>()
    
    // MARK: - Sheet States for Context Menu Actions
    @State private var showTranscriptionSheet = false
    @State private var showSummarySheet = false
    @State private var recordingForTranscription: Recording?
    @State private var recordingForSummary: Recording?
    
    // Meeting linking warning
    @State private var showMeetingLinkWarning = false
    @State private var pendingRecordingAction: (() -> Void)?
    @State private var recordingForLinkWarning: Recording?

    private let calendar = Calendar.current

    private var todayRecordings: [Recording] {
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        let recordings = allRecordings.filter { recording in
            recording.createdAt >= startOfDay && recording.createdAt < endOfDay
        }
        
        // Deduplicate by ID
        var seenIds = Set<UUID>()
        return recordings.filter { recording in
            if seenIds.contains(recording.id) {
                return false
            }
            seenIds.insert(recording.id)
            return true
        }
    }

    var body: some View {
        Group {
            if todayRecordings.isEmpty {
                emptyTodayView
            } else {
                recordingsSection
            }
        }
        .sheet(item: $selectedRecording) { recording in
            NavigationStack {
                RecordingDetailView(recording: recording)
            }
            .adaptiveSheet()
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Empty State

    private var emptyTodayView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Нет записей за сегодня")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Нажмите на кнопку микрофона, чтобы начать запись")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Recordings Section

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Сегодня")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(todayRecordings.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 4)

            ForEach(todayRecordings) { recording in
                recordingRow(for: recording)
            }
        }
        .sheet(isPresented: $showEventPickerForSuggestion) {
            if let recording = recordingForSuggestion {
                EventPickerSheetForSuggestion(
                    recording: recording,
                    events: eventsForRecording(recording)
                )
            }
        }
        .sheet(isPresented: $showAllEventsPicker) {
            AllEventsPickerSheet(
                recording: recordingForSuggestion,
                events: todayEvents,
                onSelect: { event in
                    recordingForSuggestion?.linkToMeeting(event)
                    try? modelContext.save()
                    showAllEventsPicker = false
                    recordingForSuggestion = nil
                },
                onCancel: {
                    showAllEventsPicker = false
                    recordingForSuggestion = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        // MARK: - Transcription Sheet
        .sheet(item: $recordingForTranscription) { recording in
            NavigationStack {
                TranscriptionView(recording: recording)
            }
            .adaptiveSheet()
            .presentationDragIndicator(.visible)
        }
        // MARK: - Summary Sheet  
        .sheet(item: $recordingForSummary) { recording in
            NavigationStack {
                SummaryView(recording: recording)
            }
            .adaptiveSheet()
            .presentationDragIndicator(.visible)
        }
        .meetingLinkingAlert(
            isPresented: $showMeetingLinkWarning,
            for: recordingForLinkWarning ?? Recording(title: "", audioFileURL: ""),
            onSend: {
                if let action = pendingRecordingAction {
                    action()
                }
                pendingRecordingAction = nil
                recordingForLinkWarning = nil
            },
            onLink: {
                if let recording = recordingForLinkWarning {
                    recordingForSuggestion = recording
                    showAllEventsPicker = true
                }
            }
        )
    }
    
    // MARK: - Single Recording Row
    
    @ViewBuilder
    private func recordingRow(for recording: Recording) -> some View {
        // Check if we should show meeting suggestion for this recording
        if shouldShowSuggestion(for: recording),
           let suggestedMeeting = calendarManager.findMostProbableMeeting(for: recording) {
            // Объединённая карточка с предложением
            RecordingWithSuggestionCard(
                recording: recording,
                suggestedEvent: suggestedMeeting,
                onConfirm: { try? modelContext.save() },
                onSelectOther: {
                    recordingForSuggestion = recording
                    showAllEventsPicker = true
                },
                onDismiss: {
                    dismissedSuggestions.insert(recording.id)
                },
                onTapRecording: {
                    selectedRecording = recording
                },
                onDelete: {
                    deleteRecording(recording)
                },
                onTranscribe: !recording.isTranscribed ? {
                    checkAndTranscribeRecording(recording)
                } : nil,
                onViewTranscription: recording.isTranscribed ? {
                    recordingForTranscription = recording
                } : nil,
                onGenerateSummary: recording.isTranscribed && recording.summaryText == nil && !recording.isSummaryGenerating ? {
                    checkAndGenerateSummary(recording)
                } : nil,
                onViewSummary: recording.summaryText != nil ? {
                    recordingForSummary = recording
                } : nil
            )
        } else {
            // Обычная карточка записи
            RecordingCard(
                recording: recording,
                onTap: {
                    selectedRecording = recording
                },
                onDelete: {
                    deleteRecording(recording)
                },
                onTranscribe: !recording.isTranscribed ? {
                    transcribeRecording(recording)
                } : nil,
                onViewTranscription: recording.isTranscribed ? {
                    recordingForTranscription = recording
                    showTranscriptionSheet = true
                } : nil,
                onGenerateSummary: recording.isTranscribed && recording.summaryText == nil && !recording.isSummaryGenerating ? {
                    checkAndGenerateSummary(recording)
                } : nil,
                onViewSummary: recording.summaryText != nil ? {
                    recordingForSummary = recording
                    showSummarySheet = true
                } : nil
            )
        }
    }
    
    // MARK: - Helpers
    
    private func shouldShowSuggestion(for recording: Recording) -> Bool {
        !recording.hasLinkedMeeting && 
        calendarManager.isConnected && 
        !dismissedSuggestions.contains(recording.id)
    }
    
    private var todayEvents: [EASCalendarEvent] {
        calendarManager.cachedEvents.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: Date())
        }.sorted { $0.startTime < $1.startTime }
    }

    private func eventsForRecording(_ recording: Recording) -> [EASCalendarEvent] {
        calendarManager.cachedEvents.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: recording.createdAt)
        }
    }

    // MARK: - Actions

    private func deleteRecording(_ recording: Recording) {
        if FileManager.default.fileExists(atPath: recording.audioFileURL) {
            try? FileManager.default.removeItem(atPath: recording.audioFileURL)
        }
        modelContext.delete(recording)
    }
    
    // MARK: - Meeting Linking Check
    
    private func checkAndTranscribeRecording(_ recording: Recording) {
        // Если запись уже привязана или нет событий для привязки - сразу транскрибируем
        if recording.hasLinkedMeeting || eventsForRecording(recording).isEmpty {
            transcribeRecording(recording)
            return
        }
        
        // Сохраняем действие для выполнения после алерта
        recordingForLinkWarning = recording
        pendingRecordingAction = { [self] in
            self.transcribeRecording(recording)
        }
        
        // Показываем предупреждение
        showMeetingLinkWarning = true
    }
    
    private func checkAndGenerateSummary(_ recording: Recording) {
        // Если запись уже привязана или нет событий для привязки - сразу генерируем
        if recording.hasLinkedMeeting || eventsForRecording(recording).isEmpty {
            Task {
                await RecordingCoordinator.shared.generateSummary(for: recording)
            }
            return
        }
        
        // Сохраняем действие для выполнения после алерта
        recordingForLinkWarning = recording
        pendingRecordingAction = { 
            Task {
                await RecordingCoordinator.shared.generateSummary(for: recording)
            }
        }
        
        // Показываем предупреждение
        showMeetingLinkWarning = true
    }
    
    private func transcribeRecording(_ recording: Recording) {
        Task {
            recording.isUploading = true
            try? modelContext.save()
            
            do {
                let service = TranscriptionService()
                let audioURL = URL(fileURLWithPath: recording.audioFileURL)
                let preset = recording.preset ?? .projectMeeting
                
                let result = try await service.transcribe(audioFileURL: audioURL, preset: preset)
                
                await MainActor.run {
                    recording.transcriptionText = result.transcription
                    recording.isTranscribed = true
                    recording.summaryText = result.summary
                    if let generatedTitle = result.generatedTitle {
                        recording.title = generatedTitle
                    }
                    recording.isUploading = false
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    recording.isUploading = false
                    try? modelContext.save()
                }
            }
        }
    }
}

// MARK: - All Events Picker Sheet

private struct AllEventsPickerSheet: View {
    let recording: Recording?
    let events: [EASCalendarEvent]
    let onSelect: (EASCalendarEvent) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if events.isEmpty {
                    ContentUnavailableView(
                        "Нет событий",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("На сегодня нет запланированных встреч")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(events) { event in
                            Button {
                                onSelect(event)
                            } label: {
                                EventPickerRow(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Выберите встречу")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.primary)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Event Row (стеклянный стиль)

private struct EventRow: View {
    let event: EASCalendarEvent
    
    var body: some View {
        HStack(spacing: 12) {
            // Иконка календаря
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(Color.blueVibrant)
            }
            
            // Информация о встрече
            VStack(alignment: .leading, spacing: 4) {
                Text(event.subject)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 12) {
                    Label(formattedTime(event.startTime), systemImage: "clock")
                        .font(.caption)
                    if !event.humanAttendees.isEmpty {
                        Label("\(event.humanAttendees.count)", systemImage: "person.2")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Event Picker Sheet for Suggestion

private struct EventPickerSheetForSuggestion: View {
    let recording: Recording
    let events: [EASCalendarEvent]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Кнопка "Отвязать" если есть связь
                    if recording.hasLinkedMeeting {
                        Button(role: .destructive) {
                            recording.unlinkFromMeeting()
                            dismiss()
                        } label: {
                            Label {
                                Text("Отвязать от встречи")
                                    .foregroundStyle(.red)
                            } icon: {
                                Image(systemName: "link.badge.minus")
                                    .foregroundStyle(.red)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }

                    // Список событий
                    ForEach(events) { event in
                        Button {
                            recording.linkToMeeting(event)
                            dismiss()
                        } label: {
                            EventPickerRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Выберите событие")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.primary)
        .presentationDragIndicator(.visible)
    }

    private func formattedTime(_ event: EASCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.startTime)
    }
}

// MARK: - Event Picker Row (синий стиль)

private struct EventPickerRow: View {
    let event: EASCalendarEvent
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Иконка календаря
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(Color.blueVibrant)
            }
            
            // Информация о встрече
            VStack(alignment: .leading, spacing: 4) {
                Text(event.subject)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    Label(formattedTime(event.startTime), systemImage: "clock")
                        .font(.caption)
                    
                    if !event.humanAttendees.isEmpty {
                        Label("\(event.humanAttendees.count)", systemImage: "person.2")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .vantaBlueGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.12)
    }
}

#Preview {
    TodayRecordingsSection()
        .modelContainer(for: Recording.self, inMemory: true)
        .padding()
}
