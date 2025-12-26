import SwiftData
import SwiftUI

/// Отдельное окно для просмотра записи (Stage Manager)
struct RecordingDetailWindow: View {
    let recordingId: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var recordings: [Recording]

    private var recording: Recording? {
        recordings.first { $0.id == recordingId }
    }

    var body: some View {
        Group {
            if let recording = recording {
                NavigationStack {
                    RecordingDetailView(recording: recording)
                        .navigationTitle(recording.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                ContentUnavailableView(
                    "Запись не найдена",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Эта запись была удалена или недоступна")
                )
            }
        }
        .tint(.pinkVibrant)
    }
}

#Preview {
    RecordingDetailWindow(recordingId: UUID())
        .modelContainer(for: Recording.self, inMemory: true)
}
