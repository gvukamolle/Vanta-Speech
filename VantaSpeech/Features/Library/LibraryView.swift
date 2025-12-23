import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var searchText = ""
    @State private var selectedRecording: Recording?

    var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordings
        }
        return recordings.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.transcriptionText?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var recentRecording: Recording? {
        recordings.first
    }

    var olderRecordings: [Recording] {
        Array(filteredRecordings.dropFirst())
    }

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    emptyStateView
                } else {
                    recordingsListView
                }
            }
            .navigationTitle("Recordings")
            .searchable(text: $searchText, prompt: "Search recordings")
            .navigationDestination(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Recordings",
            systemImage: "mic.slash",
            description: Text("Start recording a meeting to see it here.")
        )
    }

    // MARK: - Recordings List

    private var recordingsListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Recent/Featured Recording
                if let recent = recentRecording, searchText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        RecordingCardLarge(recording: recent) {
                            selectedRecording = recent
                        }
                    }
                    .padding(.bottom, 8)
                }

                // All Recordings
                if !olderRecordings.isEmpty || !searchText.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(searchText.isEmpty ? "All Recordings" : "Results")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(filteredRecordings.count)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 4)

                        ForEach(searchText.isEmpty ? olderRecordings : filteredRecordings) { recording in
                            RecordingCard(recording: recording) {
                                selectedRecording = recording
                            }
                            .contextMenu {
                                contextMenuContent(for: recording)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuContent(for recording: Recording) -> some View {
        Button {
            selectedRecording = recording
        } label: {
            Label("Open", systemImage: "arrow.right.circle")
        }

        if !recording.isTranscribed && !recording.isUploading {
            Button {
                // Trigger transcription
            } label: {
                Label("Transcribe", systemImage: "text.bubble")
            }
        }

        Divider()

        Button {
            renameRecording(recording)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            shareRecording(recording)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            deleteRecording(recording)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func deleteRecording(_ recording: Recording) {
        // Delete audio file
        if FileManager.default.fileExists(atPath: recording.audioFileURL) {
            try? FileManager.default.removeItem(atPath: recording.audioFileURL)
        }
        modelContext.delete(recording)
    }

    private func renameRecording(_ recording: Recording) {
        // TODO: Show rename dialog
    }

    private func shareRecording(_ recording: Recording) {
        // TODO: Show share sheet
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: Recording.self, inMemory: true)
}
