import SwiftData
import SwiftUI

/// iPad-оптимизированный view для секции История
/// Календарь и статистика слева, список записей справа
struct iPadLibraryContentView: View {
    @Binding var selectedRecording: Recording?
    var onOpenInNewWindow: ((Recording) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?
    @StateObject private var calendarManager = EASCalendarManager.shared

    private let calendar = Calendar.current

    private var recordingDates: Set<DateComponents> {
        Set(recordings.map { recording in
            calendar.dateComponents([.year, .month, .day], from: recording.createdAt)
        })
    }

    private var recordingsCountForMonth: Int {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? displayedMonth

        return recordings.filter { recording in
            recording.createdAt >= startOfMonth && recording.createdAt < endOfMonth
        }.count
    }

    /// Записи для выбранной даты или последние записи
    private var displayedRecordings: [Recording] {
        if let date = selectedDate {
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return recordings.filter { $0.createdAt >= startOfDay && $0.createdAt < endOfDay }
        } else {
            return Array(recordings.prefix(20))
        }
    }

    private var listTitle: String {
        if let date = selectedDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateStyle = .long
            return formatter.string(from: date)
        } else {
            return "Последние записи"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Левая колонка: Календарь и статистика
            leftColumn
                .frame(width: 360)

            Divider()

            // Правая колонка: Список записей
            rightColumn
        }
        .navigationTitle("История")
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Left Column (Calendar + Stats)

    private var leftColumn: some View {
        ScrollView {
            VStack(spacing: 24) {
                calendarCard
                statsView
                Spacer(minLength: 20)
            }
            .padding()
        }
        .refreshable {
            if calendarManager.isConnected {
                await calendarManager.forceFullSync()
            }
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 0) {
            CalendarView(
                selectedDate: $selectedDate,
                displayedMonth: $displayedMonth,
                recordingDates: recordingDates
            )
            .padding()
        }
        .vantaGlassCard(cornerRadius: 24, shadowRadius: 0, tintOpacity: 0.15)
    }

    private var statsView: some View {
        VStack(spacing: 12) {
            StatCardRow(
                title: "Всего записей",
                value: "\(recordings.count)",
                icon: "waveform",
                color: .pinkVibrant
            )

            StatCardRow(
                title: "За этот месяц",
                value: "\(recordingsCountForMonth)",
                icon: "calendar",
                color: .blueVibrant
            )

            let transcribedCount = recordings.filter { $0.isTranscribed }.count
            StatCardRow(
                title: "Транскрибировано",
                value: "\(transcribedCount)",
                icon: "text.bubble",
                color: .green
            )
        }
    }

    // MARK: - Right Column (Recordings List)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(listTitle)
                    .font(.headline)

                Spacer()

                if selectedDate != nil {
                    Button("Сбросить") {
                        selectedDate = nil
                    }
                    .font(.subheadline)
                }

                Text("\(displayedRecordings.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
            .padding()

            Divider()

            // Recordings list
            if displayedRecordings.isEmpty {
                emptyStateView
            } else {
                recordingsList
            }
        }
    }

    private var recordingsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(displayedRecordings) { recording in
                    RecordingCard(recording: recording) {
                        selectedRecording = recording
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(selectedRecording?.id == recording.id ? Color.pinkVibrant.opacity(0.1) : Color.clear)
                    )
                    .contextMenu {
                        Button {
                            selectedRecording = recording
                        } label: {
                            Label("Открыть", systemImage: "arrow.right.circle")
                        }

                        if onOpenInNewWindow != nil {
                            Button {
                                onOpenInNewWindow?(recording)
                            } label: {
                                Label("Открыть в новом окне", systemImage: "macwindow.badge.plus")
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            deleteRecording(recording)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: selectedDate != nil ? "calendar.badge.exclamationmark" : "waveform.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(selectedDate != nil ? "Нет записей за эту дату" : "Нет записей")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(selectedDate != nil ? "Выберите другую дату в календаре" : "Начните запись, нажав на микрофон")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func deleteRecording(_ recording: Recording) {
        if recording.id == selectedRecording?.id {
            selectedRecording = nil
        }
        if FileManager.default.fileExists(atPath: recording.audioFileURL) {
            try? FileManager.default.removeItem(atPath: recording.audioFileURL)
        }
        modelContext.delete(recording)
    }
}

// MARK: - Stat Card Row (for iPad sidebar)

private struct StatCardRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(color.opacity(0.15))
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .vantaGlassCard(cornerRadius: 20, shadowRadius: 0, tintOpacity: 0.15)
    }
}

#Preview {
    iPadLibraryContentView(selectedRecording: .constant(nil))
        .modelContainer(for: Recording.self, inMemory: true)
}
