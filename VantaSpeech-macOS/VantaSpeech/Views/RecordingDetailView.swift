import SwiftUI
import SwiftData

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(\.modelContext) private var modelContext
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var selectedTab = 0
    @State private var isTranscribing = false
    @State private var errorMessage: String?

    @AppStorage("serverURL") private var serverURL = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with waveform
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "1A1A2E"), Color(hex: "2D2D44")],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(spacing: 16) {
                    // Waveform visualization placeholder
                    HStack(spacing: 2) {
                        ForEach(0..<40, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 4, height: CGFloat.random(in: 10...40))
                        }
                    }
                    .frame(height: 50)

                    // Player controls
                    HStack(spacing: 24) {
                        Button {
                            audioPlayer.skipBackward()
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            if audioPlayer.isPlaying {
                                audioPlayer.pause()
                            } else {
                                audioPlayer.play()
                            }
                        } label: {
                            Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            audioPlayer.skipForward()
                        } label: {
                            Image(systemName: "goforward.15")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    // Progress bar
                    VStack(spacing: 4) {
                        Slider(value: Binding(
                            get: { Double(audioPlayer.progress) },
                            set: { audioPlayer.seekToProgress(Float($0)) }
                        ))
                        .tint(.white)

                        HStack {
                            Text(audioPlayer.formattedCurrentTime)
                            Spacer()
                            Text(audioPlayer.formattedDuration)
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .frame(height: 200)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Transcription").tag(0)
                Text("Summary").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if selectedTab == 0 {
                        if let text = recording.transcriptionText, !text.isEmpty {
                            Text(text)
                                .textSelection(.enabled)
                                .padding()
                        } else {
                            ContentUnavailableView(
                                "No Transcription",
                                systemImage: "doc.text",
                                description: Text("Click Transcribe to generate a transcription")
                            )
                        }
                    } else {
                        if let summary = recording.summaryText, !summary.isEmpty {
                            Text(summary)
                                .textSelection(.enabled)
                                .padding()
                        } else {
                            ContentUnavailableView(
                                "No Summary",
                                systemImage: "doc.plaintext",
                                description: Text("A summary will be generated after transcription")
                            )
                        }
                    }
                }
            }

            Divider()

            // Bottom toolbar
            HStack {
                if !recording.isTranscribed {
                    Button {
                        Task { await transcribe() }
                    } label: {
                        if isTranscribing {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Transcribing...")
                        } else {
                            Label("Transcribe", systemImage: "text.bubble")
                        }
                    }
                    .disabled(isTranscribing || serverURL.isEmpty)
                }

                Spacer()

                if recording.isTranscribed {
                    Button {
                        copyToClipboard(selectedTab == 0 ? recording.transcriptionText : recording.summaryText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    Button {
                        // Share action
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .padding()
        }
        .onAppear {
            let url = URL(fileURLWithPath: recording.audioFileURL)
            audioPlayer.load(url: url)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationTitle(recording.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rename") {
                        // TODO
                    }
                    Divider()
                    Button("Show in Finder") {
                        let url = URL(fileURLWithPath: recording.audioFileURL)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func transcribe() async {
        isTranscribing = true
        recording.isUploading = true

        do {
            let service = TranscriptionService()
            await service.updateBaseURL(serverURL)

            let url = URL(fileURLWithPath: recording.audioFileURL)
            let result = try await service.transcribe(audioFileURL: url)

            recording.transcriptionText = result.transcription
            recording.summaryText = result.summary
            recording.isTranscribed = true
            recording.isUploading = false

            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            recording.isUploading = false
        }

        isTranscribing = false
    }

    private func copyToClipboard(_ text: String?) {
        guard let text = text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

#Preview {
    RecordingDetailView(
        recording: Recording(
            title: "Test Recording",
            duration: 125,
            audioFileURL: "/path/to/audio.m4a",
            transcriptionText: "This is a sample transcription text that would appear here after processing.",
            summaryText: "This is the summary."
        )
    )
    .modelContainer(for: Recording.self, inMemory: true)
}
