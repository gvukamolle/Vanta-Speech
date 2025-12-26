import SwiftUI
import SwiftData

struct TodayRecordingsSection: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var allRecordings: [Recording]
    @State private var selectedRecording: Recording?
    @Environment(\.modelContext) private var modelContext

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

    // MARK: - Actions

    private func deleteRecording(_ recording: Recording) {
        if FileManager.default.fileExists(atPath: recording.audioFileURL) {
            try? FileManager.default.removeItem(atPath: recording.audioFileURL)
        }
        modelContext.delete(recording)
    }
}

#Preview {
    TodayRecordingsSection()
        .modelContainer(for: Recording.self, inMemory: true)
        .padding()
}
