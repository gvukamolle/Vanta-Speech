import SwiftUI
import SwiftData

struct TodayRecordingsSection: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var allRecordings: [Recording]
    @State private var selectedRecording: Recording?
    @Environment(\.modelContext) private var modelContext
    @StateObject private var calendarManager = EASCalendarManager.shared
    @State private var recordingForSuggestion: Recording?
    @State private var showEventPickerForSuggestion = false

    private let calendar = Calendar.current

    private var todayRecordings: [Recording] {
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return allRecordings.filter { recording in
            recording.createdAt >= startOfDay && recording.createdAt < endOfDay
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
                VStack(spacing: 8) {
                    // Show meeting suggestion if not linked and calendar is connected
                    if !recording.hasLinkedMeeting && calendarManager.isConnected {
                        if let suggestedMeeting = calendarManager.findMostProbableMeeting(for: recording) {
                            MeetingSuggestionCard(
                                suggestedEvent: suggestedMeeting,
                                recording: recording,
                                onConfirm: { try? modelContext.save() },
                                onEdit: {
                                    recordingForSuggestion = recording
                                    showEventPickerForSuggestion = true
                                }
                            )
                        }
                    }

                    RecordingCard(recording: recording) {
                        selectedRecording = recording
                    }
                    .contextMenu {
                        Button {
                            selectedRecording = recording
                        } label: {
                            Label("Открыть", systemImage: "arrow.right.circle")
                        }

                        Button(role: .destructive) {
                            deleteRecording(recording)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
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
}

// MARK: - Meeting Suggestion Card

struct MeetingSuggestionCard: View {
    let suggestedEvent: EASCalendarEvent
    let recording: Recording
    let onConfirm: () -> Void
    let onEdit: () -> Void

    @State private var isConfirmed = false

    var body: some View {
        if isConfirmed {
            confirmedView
        } else {
            suggestionView
        }
    }

    private var suggestionView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("Предлагаемая встреча")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestedEvent.subject)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(formatTime(suggestedEvent.startTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !suggestedEvent.humanAttendees.isEmpty {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(suggestedEvent.humanAttendees.count) участн.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Confirm button (checkmark)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        recording.linkToMeeting(suggestedEvent)
                        isConfirmed = true
                        onConfirm()
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.10)
    }

    private var confirmedView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(Color.blue.opacity(0.15))
                Image(systemName: "calendar")
                    .font(.body)
                    .foregroundStyle(.blue)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestedEvent.subject)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(formatTime(suggestedEvent.startTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !suggestedEvent.humanAttendees.isEmpty {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(suggestedEvent.humanAttendees.count) участн.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Pencil button for editing
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.10)
    }

    private func formatTime(_ date: Date) -> String {
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
            List {
                // Кнопка "Отвязать" если есть связь
                if recording.hasLinkedMeeting {
                    Section {
                        Button(role: .destructive) {
                            recording.unlinkFromMeeting()
                            dismiss()
                        } label: {
                            Label("Отвязать от встречи", systemImage: "link.badge.minus")
                        }
                    }
                }

                // Список событий
                Section {
                    ForEach(events) { event in
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
                }
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

    private func formattedTime(_ event: EASCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.startTime)
    }
}

#Preview {
    TodayRecordingsSection()
        .modelContainer(for: Recording.self, inMemory: true)
        .padding()
}
