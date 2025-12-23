import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var searchText = ""

    var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordings
        }
        return recordings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "mic.slash",
                        description: Text("Start recording a meeting to see it here.")
                    )
                } else {
                    List {
                        ForEach(filteredRecordings) { recording in
                            NavigationLink(destination: RecordingDetailView(recording: recording)) {
                                RecordingRowView(recording: recording)
                            }
                        }
                        .onDelete(perform: deleteRecordings)
                    }
                    .searchable(text: $searchText, prompt: "Search recordings")
                }
            }
            .navigationTitle("Library")
            .toolbar {
                EditButton()
            }
        }
    }

    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = filteredRecordings[index]
            // Delete audio file
            if FileManager.default.fileExists(atPath: recording.audioFileURL) {
                try? FileManager.default.removeItem(atPath: recording.audioFileURL)
            }
            modelContext.delete(recording)
        }
    }
}

struct RecordingRowView: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if recording.isUploading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if recording.isTranscribed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                Text(recording.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(recording.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: Recording.self, inMemory: true)
}
