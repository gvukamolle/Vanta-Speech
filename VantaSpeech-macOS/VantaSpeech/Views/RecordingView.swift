import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var audioRecorder = AudioRecorder()

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Status text
            Text(statusText)
                .font(.title2)
                .foregroundColor(audioRecorder.isRecording ? .red : .secondary)

            // Duration display
            Text(formattedDuration)
                .font(.system(size: 72, weight: .light, design: .monospaced))
                .foregroundColor(.primary)

            // Audio level visualizer
            if audioRecorder.isActive {
                AudioLevelVisualizer(level: audioRecorder.audioLevel, isActive: audioRecorder.isRecording)
                    .frame(height: 60)
                    .padding(.horizontal, 40)
            }

            // Record button
            RecordButton(isRecording: audioRecorder.isRecording || audioRecorder.isPaused) {
                toggleRecording()
            }

            // Controls for active recording
            if audioRecorder.isActive {
                HStack(spacing: 20) {
                    // Pause/Resume button
                    Button {
                        if audioRecorder.isPaused {
                            audioRecorder.resumeRecording()
                        } else {
                            audioRecorder.pauseRecording()
                        }
                    } label: {
                        Image(systemName: audioRecorder.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    // Stop button
                    Button {
                        stopRecording()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Record")
    }

    private var statusText: String {
        switch audioRecorder.state {
        case .recording: return "Recording..."
        case .paused: return "Paused"
        default: return "Tap to Record"
        }
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

    private func toggleRecording() {
        if audioRecorder.state == .idle {
            _ = audioRecorder.startRecording()
        } else {
            stopRecording()
        }
    }

    private func stopRecording() {
        if let result = audioRecorder.stopRecording() {
            let (url, duration) = result
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy HH:mm"

            let recording = Recording(
                title: "Recording \(formatter.string(from: Date()))",
                duration: duration,
                audioFileURL: url.path
            )

            modelContext.insert(recording)
            try? modelContext.save()
        }
    }
}

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.8), Color.red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)

                if isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .frame(width: 35, height: 35)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 45, height: 45)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct AudioLevelVisualizer: View {
    let level: Float
    let isActive: Bool

    private let barCount = 30

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let distanceFromCenter = abs(Float(index) - Float(barCount) / 2) / (Float(barCount) / 2)
                let barHeight = ((1 - distanceFromCenter * 0.5) * (isActive ? level : 0) * 60).clamped(to: 4...60)

                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? Color.red.opacity(Double(0.3 + level * 0.7)) : Color.gray.opacity(0.3))
                    .frame(height: CGFloat(barHeight))
            }
        }
        .animation(.easeInOut(duration: 0.1), value: level)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    RecordingView()
        .modelContainer(for: Recording.self, inMemory: true)
}
