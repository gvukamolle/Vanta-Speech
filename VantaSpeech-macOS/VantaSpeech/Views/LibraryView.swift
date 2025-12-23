import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var searchText = ""
    @State private var selectedRecording: Recording?

    private var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordings
        }
        return recordings.filter { recording in
            recording.title.localizedCaseInsensitiveContains(searchText) ||
            (recording.transcriptionText?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var recentRecording: Recording? {
        recordings.first
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search recordings...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding()

                if filteredRecordings.isEmpty && searchText.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "mic")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No recordings yet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Press ⌘R to start recording")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                        Spacer()
                    }
                } else {
                    List(selection: $selectedRecording) {
                        // Recent card
                        if let recent = recentRecording, searchText.isEmpty {
                            Section("Recent") {
                                RecordingCardLarge(recording: recent)
                                    .tag(recent)
                            }
                        }

                        // All recordings
                        Section(searchText.isEmpty ? "All Recordings" : "Results") {
                            ForEach(filteredRecordings.filter { $0.id != recentRecording?.id || !searchText.isEmpty }) { recording in
                                RecordingRow(recording: recording)
                                    .tag(recording)
                                    .contextMenu {
                                        Button("Rename") {
                                            // TODO: Implement rename
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            deleteRecording(recording)
                                        }
                                    }
                            }
                            .onDelete(perform: deleteRecordings)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            if let recording = selectedRecording {
                RecordingDetailView(recording: recording)
            } else {
                ContentUnavailableView(
                    "Select a Recording",
                    systemImage: "waveform",
                    description: Text("Choose a recording from the list to view details")
                )
            }
        }
        .navigationTitle("Library")
    }

    private func deleteRecording(_ recording: Recording) {
        // Delete audio file
        let fileURL = URL(fileURLWithPath: recording.audioFileURL)
        try? FileManager.default.removeItem(at: fileURL)

        // Delete from database
        modelContext.delete(recording)
        try? modelContext.save()
    }

    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = filteredRecordings[index]
            deleteRecording(recording)
        }
    }
}

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: recording.isTranscribed ? "checkmark.circle.fill" : "waveform")
                    .foregroundColor(recording.isTranscribed ? .green : .accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(recording.formattedDate)
                    Text("•")
                    Text(recording.formattedDuration)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if recording.isUploading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecordingCardLarge: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(recording.formattedDate)
                        Text("•")
                        Text(recording.formattedDuration)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                if recording.isTranscribed {
                    Text("Transcribed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }

            if let preview = recording.transcriptionPreview {
                Text(preview)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color(hex: "1A1A2E"), Color(hex: "2D2D44")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: Recording.self, inMemory: true)
}
