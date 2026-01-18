import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DayRecordingsSheet: View {
    let date: Date
    @Query(sort: \Recording.createdAt, order: .reverse) private var allRecordings: [Recording]
    @State private var selectedRecording: Recording?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var calendarManager = EASCalendarManager.shared

    // MARK: - Import State
    @State private var showFileImporter = false
    @State private var showPresetPickerForImport = false
    @State private var importedAudioData: AudioImporter.ImportedAudio?
    @State private var isImporting = false
    @StateObject private var presetSettings = PresetSettings.shared

    private let calendar = Calendar.current

    // MARK: - Data Filtering

    private var recordingsForDate: [Recording] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return allRecordings.filter { recording in
            recording.createdAt >= startOfDay && recording.createdAt < endOfDay
        }
    }

    private var eventsForDate: [EASCalendarEvent] {
        calendarManager.cachedEvents.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: date)
        }
    }

    // Events without recordings
    private var unmatchedEvents: [EASCalendarEvent] {
        eventsForDate.filter { event in
            !recordingsForDate.contains { $0.linkedMeetingId == event.id }
        }
    }

    // Recordings linked to events
    private var linkedRecordings: [Recording] {
        recordingsForDate.filter { $0.hasLinkedMeeting }
    }

    // Recordings without events
    private var unmatchedRecordings: [Recording] {
        recordingsForDate.filter { !$0.hasLinkedMeeting }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Group {
                if recordingsForDate.isEmpty && eventsForDate.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: AudioImporter.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .sheet(isPresented: $showPresetPickerForImport) {
                if let audioData = importedAudioData {
                    ImportPresetPickerSheet(
                        audioData: audioData,
                        presets: presetSettings.enabledPresets,
                        onSelect: { preset in
                            finalizeImport(audioData: audioData, preset: preset)
                            showPresetPickerForImport = false
                        },
                        onCancel: {
                            try? FileManager.default.removeItem(at: audioData.url)
                            importedAudioData = nil
                            showPresetPickerForImport = false
                        }
                    )
                    .presentationDetents([.medium])
                }
            }
            .overlay {
                if isImporting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Импорт...")
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "Нет данных",
            systemImage: "calendar.badge.exclamationmark",
            description: Text("За этот день нет записей и событий")
        )
    }

    // MARK: - Content View (3 Sections)

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Section 1: Events without recordings (unlinked events)
                if !unmatchedEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Встречи")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(unmatchedEvents) { event in
                            EventCard(event: event)
                        }
                    }
                }

                // Section 2: Linked recordings (recordings with meetings)
                if !linkedRecordings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Записи")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(linkedRecordings) { recording in
                            LinkedRecordingCard(
                                recording: recording,
                                availableEvents: eventsForDate
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteRecording(recording)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // Section 3: Recordings without events (unlinked recordings)
                if !unmatchedRecordings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Без встречи")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(unmatchedRecordings) { recording in
                            UnlinkedRecordingCard(
                                recording: recording,
                                availableEvents: eventsForDate
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteRecording(recording)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Actions

    private func deleteRecording(_ recording: Recording) {
        if FileManager.default.fileExists(atPath: recording.audioFileURL) {
            try? FileManager.default.removeItem(atPath: recording.audioFileURL)
        }
        modelContext.delete(recording)
    }

    // MARK: - Import Actions

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            Task {
                do {
                    let importer = AudioImporter()
                    let audioData = try await importer.importAudio(from: url)
                    importedAudioData = audioData
                    isImporting = false
                    showPresetPickerForImport = true
                } catch {
                    isImporting = false
                }
            }
        case .failure:
            break
        }
    }

    private func finalizeImport(audioData: AudioImporter.ImportedAudio, preset: RecordingPreset) {
        // IMPORTANT: Use selected day's date, not Date()
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 12
        components.minute = 0
        let importDate = calendar.date(from: components) ?? date

        let recording = Recording(
            id: UUID(),
            title: "\(preset.displayName) - \(audioData.originalFileName)",
            createdAt: importDate,  // Use selected day's date!
            duration: audioData.duration,
            audioFileURL: audioData.url.path,
            preset: preset
        )

        modelContext.insert(recording)
        try? modelContext.save()
        importedAudioData = nil
    }
}

// MARK: - Event Picker Sheet

private struct EventPickerSheet: View {
    let recording: Recording
    let events: [EASCalendarEvent]
    @Environment(\.dismiss) private var dismiss

    private func formattedTime(_ event: EASCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.startTime)
    }

    var body: some View {
        NavigationStack {
            List(events) { event in
                Button {
                    recording.linkToMeeting(event)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.subject)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 12) {
                            Label(formattedTime(event), systemImage: "clock")

                            if !event.attendees.isEmpty {
                                Label("\(event.humanAttendees.count) участн.", systemImage: "person.2")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Выберите событие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Unlinked Recording Card

private struct UnlinkedRecordingCard: View {
    let recording: Recording
    let availableEvents: [EASCalendarEvent]
    @State private var showRecordingDetail = false

    var body: some View {
        // Recording card - tap to open detail with link button inside
        RecordingCard(recording: recording) {
            showRecordingDetail = true
        }
        .sheet(isPresented: $showRecordingDetail) {
            NavigationStack {
                RecordingDetailView(
                    recording: recording,
                    availableEventsForLinking: availableEvents
                )
            }
            .adaptiveSheet()
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Linked Recording Card (Recording with meeting info inside detail)

private struct LinkedRecordingCard: View {
    let recording: Recording
    let availableEvents: [EASCalendarEvent]
    @State private var showRecordingDetail = false

    var body: some View {
        RecordingCard(recording: recording) {
            showRecordingDetail = true
        }
        .sheet(isPresented: $showRecordingDetail) {
            NavigationStack {
                RecordingDetailView(
                    recording: recording,
                    availableEventsForLinking: availableEvents
                )
            }
            .adaptiveSheet()
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Event Card (Compact)

private struct EventCard: View {
    let event: EASCalendarEvent
    @State private var showDetail = false

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.startTime)
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                    Text(event.subject)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 12) {
                    Label(formattedTime, systemImage: "clock")

                    if !event.attendees.isEmpty {
                        Label("\(event.humanAttendees.count) участн.", systemImage: "person.2")
                    }

                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            MeetingDetailSheet(event: event)
        }
    }
}

#Preview {
    DayRecordingsSheet(date: Date())
        .modelContainer(for: Recording.self, inMemory: true)
}
