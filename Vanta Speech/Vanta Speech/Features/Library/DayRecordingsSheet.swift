import SwiftUI
import SwiftData

struct DayRecordingsSheet: View {
    let date: Date
    @Query(sort: \Recording.createdAt, order: .reverse) private var allRecordings: [Recording]
    @State private var selectedRecording: Recording?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let calendar = Calendar.current

    private var recordingsForDate: [Recording] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return allRecordings.filter { recording in
            recording.createdAt >= startOfDay && recording.createdAt < endOfDay
        }
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
                if recordingsForDate.isEmpty {
                    emptyStateView
                } else {
                    recordingsListView
                }
            }
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
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
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "Нет записей",
            systemImage: "mic.slash",
            description: Text("За этот день записей нет")
        )
    }

    // MARK: - Recordings List

    private var recordingsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(recordingsForDate) { recording in
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
}

#Preview {
    DayRecordingsSheet(date: Date())
        .modelContainer(for: Recording.self, inMemory: true)
}
