import SwiftUI
import SwiftData

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @StateObject private var player = AudioPlayer()
    @State private var showTranscription = false
    @State private var showSummary = false
    @State private var isTranscribing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Recording Info Card
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)

                    Text(recording.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        Label(recording.formattedDate, systemImage: "calendar")
                        Label(recording.formattedDuration, systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Player Controls
                VStack(spacing: 16) {
                    // Progress Bar
                    VStack(spacing: 4) {
                        Slider(value: Binding(
                            get: { player.progress },
                            set: { player.seekToProgress($0) }
                        ), in: 0...1)
                        .tint(.blue)

                        HStack {
                            Text(player.formattedCurrentTime)
                            Spacer()
                            Text(player.formattedDuration)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    // Playback Controls
                    HStack(spacing: 40) {
                        Button {
                            player.seek(to: max(0, player.currentTime - 15))
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title)
                        }

                        Button {
                            if player.isPlaying {
                                player.pause()
                            } else {
                                player.play()
                            }
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                        }

                        Button {
                            player.seek(to: min(player.duration, player.currentTime + 15))
                        } label: {
                            Image(systemName: "goforward.15")
                                .font(.title)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Action Buttons
                VStack(spacing: 12) {
                    if !recording.isTranscribed {
                        Button {
                            transcribeRecording()
                        } label: {
                            HStack {
                                if isTranscribing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "text.bubble")
                                }
                                Text(isTranscribing ? "Transcribing..." : "Transcribe")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isTranscribing)
                    }

                    if recording.isTranscribed {
                        Button {
                            showTranscription = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                Text("View Transcription")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            showSummary = true
                        } label: {
                            HStack {
                                Image(systemName: "text.alignleft")
                                Text("View Summary")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Button {
                        showShareSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAudio()
        }
        .onDisappear {
            player.stop()
        }
        .sheet(isPresented: $showTranscription) {
            TextDetailView(title: "Transcription", text: recording.transcriptionText ?? "")
        }
        .sheet(isPresented: $showSummary) {
            TextDetailView(title: "Summary", text: recording.summaryText ?? "")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadAudio() {
        let url = URL(fileURLWithPath: recording.audioFileURL)
        do {
            try player.load(url: url)
        } catch {
            errorMessage = "Failed to load audio: \(error.localizedDescription)"
            showError = true
        }
    }

    private func transcribeRecording() {
        isTranscribing = true
        recording.isUploading = true

        Task {
            do {
                // TODO: Replace with actual server URL from settings
                let serverURL = URL(string: "https://api.example.com")!
                let service = TranscriptionService(baseURL: serverURL)

                let audioURL = URL(fileURLWithPath: recording.audioFileURL)
                let result = try await service.transcribe(audioFileURL: audioURL)

                await MainActor.run {
                    recording.transcriptionText = result.transcription
                    recording.summaryText = result.summary
                    recording.isTranscribed = true
                    recording.isUploading = false
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    recording.isUploading = false
                    isTranscribing = false
                }
            }
        }
    }
}

struct TextDetailView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: Recording(
            title: "Test Meeting",
            duration: 125,
            audioFileURL: "/test/path.m4a"
        ))
    }
}
