import SwiftUI
import SwiftData

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @AppStorage("serverURL") private var serverURL = ""
    @StateObject private var player = AudioPlayer()
    @State private var isTranscribing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedTab: ContentTab = .transcription

    enum ContentTab: String, CaseIterable {
        case transcription = "Transcription"
        case summary = "Summary"

        var icon: String {
            switch self {
            case .transcription: return "text.bubble"
            case .summary: return "doc.text"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Recording Header Card
                headerCard

                // Audio Player Card
                playerCard

                // Transcribe Button (if not transcribed)
                if !recording.isTranscribed {
                    transcribeButton

                    if serverURL.isEmpty {
                        Text("Configure server URL in Settings to enable transcription")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }

                // Content Tabs (Transcription / Summary)
                if recording.isTranscribed {
                    contentSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    shareMenuContent
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            loadAudio()
        }
        .onDisappear {
            player.stop()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            // Waveform visualization
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 100)

                HStack(spacing: 3) {
                    ForEach(0..<40, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: 4, height: CGFloat.random(in: 15...60))
                    }
                }
            }

            VStack(spacing: 8) {
                Text(recording.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                HStack(spacing: 24) {
                    Label(recording.formattedDate, systemImage: "calendar")
                    Label(recording.formattedDuration, systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                // Status badges
                HStack(spacing: 12) {
                    statusBadge(
                        text: "OGG/Opus",
                        color: .blue
                    )

                    if recording.isTranscribed {
                        statusBadge(
                            text: "Transcribed",
                            color: .green
                        )
                    }

                    if recording.isUploading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Processing...")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Player Card

    private var playerCard: some View {
        VStack(spacing: 16) {
            // Progress Bar
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { player.progress },
                    set: { player.seekToProgress($0) }
                ), in: 0...1)
                .tint(.accentColor)

                HStack {
                    Text(player.formattedCurrentTime)
                    Spacer()
                    Text(player.formattedDuration)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            // Playback Controls
            HStack(spacing: 32) {
                Button {
                    player.seek(to: max(0, player.currentTime - 15))
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                .foregroundStyle(.primary)

                Button {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 64, height: 64)

                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }

                Button {
                    player.seek(to: min(player.duration, player.currentTime + 15))
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                .foregroundStyle(.primary)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Transcribe Button

    private var transcribeButton: some View {
        Button {
            transcribeRecording()
        } label: {
            HStack {
                if isTranscribing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(isTranscribing ? "Transcribing..." : "Transcribe Recording")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isTranscribing || serverURL.isEmpty ? Color.gray : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isTranscribing || serverURL.isEmpty)
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(spacing: 16) {
            // Tab Picker
            Picker("Content", selection: $selectedTab) {
                ForEach(ContentTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)

            // Content
            switch selectedTab {
            case .transcription:
                transcriptionContent
            case .summary:
                summaryContent
            }
        }
    }

    private var transcriptionContent: some View {
        ContentCard(
            title: "Transcription",
            icon: "text.bubble",
            text: recording.transcriptionText ?? "No transcription available",
            isEmpty: recording.transcriptionText == nil
        )
    }

    private var summaryContent: some View {
        ContentCard(
            title: "Summary",
            icon: "doc.text",
            text: recording.summaryText ?? "No summary available",
            isEmpty: recording.summaryText == nil
        )
    }

    // MARK: - Share Menu

    @ViewBuilder
    private var shareMenuContent: some View {
        if recording.isTranscribed {
            Button {
                copyTranscription()
            } label: {
                Label("Copy Transcription", systemImage: "doc.on.doc")
            }

            Button {
                copySummary()
            } label: {
                Label("Copy Summary", systemImage: "doc.on.doc")
            }

            Divider()
        }

        Button {
            shareAudio()
        } label: {
            Label("Share Audio", systemImage: "square.and.arrow.up")
        }

        Button {
            exportToFiles()
        } label: {
            Label("Save to Files", systemImage: "folder")
        }
    }

    // MARK: - Actions

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
                guard !serverURL.isEmpty,
                      let url = URL(string: serverURL) else {
                    throw TranscriptionService.TranscriptionError.invalidURL
                }

                let service = TranscriptionService(baseURL: url)
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

    private func copyTranscription() {
        guard let text = recording.transcriptionText else { return }
        copyToClipboard(text)
    }

    private func copySummary() {
        guard let text = recording.summaryText else { return }
        copyToClipboard(text)
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func shareAudio() {
        // TODO: Implement share sheet
    }

    private func exportToFiles() {
        // TODO: Implement export to Files app
    }
}

// MARK: - Content Card

struct ContentCard: View {
    let title: String
    let icon: String
    let text: String
    let isEmpty: Bool

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)

                Spacer()

                if !isEmpty {
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            Text(showCopied ? "Copied!" : "Copy")
                        }
                        .font(.subheadline)
                        .foregroundStyle(showCopied ? .green : .accentColor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Content
            if isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.xmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Not available")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    MarkdownContentView(text: text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 400)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: Recording(
            title: "Weekly Team Sync",
            duration: 1845,
            audioFileURL: "/test/path.ogg",
            transcriptionText: """
            # Meeting Notes

            ## Attendees
            - John Smith
            - Jane Doe
            - Bob Wilson

            ## Discussion Points

            1. **Q4 Planning**
               - Review of current progress
               - Budget allocation discussion

            2. **Product Updates**
               - New feature release scheduled for next week
               - Bug fixes in progress

            > Important: Follow up with design team by Friday

            ## Action Items
            - [ ] Send meeting notes to stakeholders
            - [ ] Schedule follow-up meeting
            - [ ] Review proposal draft
            """,
            summaryText: """
            # Summary

            The team discussed **Q4 planning** and **product updates**. Key decisions include scheduling the new feature release for next week.

            ## Next Steps
            1. Follow up with design team
            2. Review budget allocation
            3. Prepare stakeholder presentation
            """,
            isTranscribed: true
        ))
    }
}
