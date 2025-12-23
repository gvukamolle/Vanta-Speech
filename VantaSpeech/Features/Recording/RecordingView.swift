import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = AudioRecorder()
    @State private var recordingTitle = ""
    @State private var currentRecordingURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""

    private var statusText: String {
        if recorder.isConverting {
            return "Converting to OGG..."
        } else if recorder.isInterrupted {
            return "Paused (Interruption)"
        } else if recorder.isRecording {
            return "Recording"
        } else {
            return "Ready"
        }
    }

    private var statusColor: Color {
        if recorder.isInterrupted {
            return .orange
        } else if recorder.isRecording {
            return .red
        } else {
            return .primary
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Background recording indicator
                if recorder.isRecording {
                    backgroundRecordingBadge
                }

                // Status
                HStack(spacing: 8) {
                    if recorder.isRecording && !recorder.isInterrupted {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .modifier(PulseAnimation())
                    } else if recorder.isInterrupted {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                    }

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                // Timer Display
                Text(formatTime(recorder.recordingDuration))
                    .font(.system(size: 64, weight: .light, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: recorder.recordingDuration)

                // Audio Level Indicator
                if recorder.isRecording && !recorder.isInterrupted {
                    AudioLevelView(level: recorder.audioLevel)
                        .frame(height: 60)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                }

                // Interruption message
                if recorder.isInterrupted {
                    VStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text("Recording paused due to interruption")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Will resume automatically")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.scale.combined(with: .opacity))
                }

                // Converting indicator
                if recorder.isConverting {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Converting to OGG...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }

                Spacer()

                // Recording Controls
                HStack(spacing: 60) {
                    if recorder.isRecording {
                        // Stop Button
                        Button(action: stopRecording) {
                            ZStack {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 80, height: 80)

                                Image(systemName: "stop.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white)
                            }
                        }
                        .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
                    } else if recorder.isConverting {
                        // Disabled button during conversion
                        ZStack {
                            Circle()
                                .fill(.gray)
                                .frame(width: 80, height: 80)

                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(recorder.isConverting ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: recorder.isConverting)
                        }
                    } else {
                        // Record Button
                        Button(action: startRecording) {
                            ZStack {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 80, height: 80)

                                Image(systemName: "mic.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white)
                            }
                        }
                        .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
                    }
                }

                // Format indicator
                VStack(spacing: 4) {
                    Text("OGG/Opus • 64 kbps")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if recorder.isRecording {
                        Text("Background recording enabled")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Record")
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .animation(.easeInOut(duration: 0.3), value: recorder.isRecording)
            .animation(.easeInOut(duration: 0.3), value: recorder.isInterrupted)
        }
    }

    // MARK: - Background Recording Badge

    private var backgroundRecordingBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Recording continues in background")
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Actions

    private func startRecording() {
        Task {
            do {
                currentRecordingURL = try await recorder.startRecording()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func stopRecording() {
        Task {
            let result = await recorder.stopRecording(convertToOGG: true)

            switch result {
            case .success(let data):
                let title = "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))"

                let recording = Recording(
                    title: title,
                    duration: data.duration,
                    audioFileURL: data.url.path
                )

                modelContext.insert(recording)
                currentRecordingURL = nil

            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Audio Level View

struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<30, id: \.self) { index in
                    let threshold = Float(index) / 30.0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: index))
                        .opacity(level > threshold ? 1.0 : 0.3)
                }
            }
        }
    }

    private func barColor(for index: Int) -> Color {
        let ratio = Float(index) / 30.0
        if ratio < 0.6 {
            return .green
        } else if ratio < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
}

#Preview {
    RecordingView()
}
