import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @StateObject private var audioRecorder = AudioRecorder()

    var body: some View {
        VStack(spacing: 0) {
            // Recording control
            VStack(spacing: 12) {
                if audioRecorder.isActive {
                    // Active recording state
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(audioRecorder.isRecording ? 1 : 0.5)

                        Text(formattedDuration)
                            .font(.system(.body, design: .monospaced))

                        Spacer()

                        Button {
                            if audioRecorder.isPaused {
                                audioRecorder.resumeRecording()
                            } else {
                                audioRecorder.pauseRecording()
                            }
                        } label: {
                            Image(systemName: audioRecorder.isPaused ? "play.fill" : "pause.fill")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            _ = audioRecorder.stopRecording()
                        } label: {
                            Image(systemName: "stop.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    // Idle state
                    Button {
                        _ = audioRecorder.startRecording()
                    } label: {
                        HStack {
                            Image(systemName: "record.circle")
                                .foregroundColor(.red)
                            Text("Start Recording")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()

            Divider()

            // Recent recordings
            if !recordings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Recordings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    ForEach(recordings.prefix(3)) { recording in
                        Button {
                            openRecording(recording)
                        } label: {
                            HStack {
                                Image(systemName: "waveform")
                                VStack(alignment: .leading) {
                                    Text(recording.title)
                                        .lineLimit(1)
                                    Text(recording.formattedDate)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(recording.formattedDuration)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 8)

                Divider()
            }

            // Footer actions
            HStack {
                Button("Open Vanta Speech") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title == "Vanta Speech" || $0.title.isEmpty }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
            .padding()
        }
        .frame(width: 280)
    }

    private var formattedDuration: String {
        let hours = Int(audioRecorder.duration) / 3600
        let minutes = (Int(audioRecorder.duration) % 3600) / 60
        let seconds = Int(audioRecorder.duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func openRecording(_ recording: Recording) {
        NSApp.activate(ignoringOtherApps: true)
        // Post notification to open recording
        NotificationCenter.default.post(
            name: Notification.Name("openRecording"),
            object: recording.id
        )
    }
}

#Preview {
    MenuBarView()
        .modelContainer(for: Recording.self, inMemory: true)
}
