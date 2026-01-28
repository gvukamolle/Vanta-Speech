import SwiftUI

struct ActiveRecordingSheet: View {
    @EnvironmentObject var recorder: AudioRecorder
    @EnvironmentObject var coordinator: RecordingCoordinator
    @Environment(\.dismiss) private var dismiss
    let preset: RecordingPreset
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Preset indicator
            HStack(spacing: 8) {
                Image(systemName: preset.icon)
                Text(preset.displayName)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 20)

            Spacer()

            // Timer with milliseconds
            Text(formatTimeWithMilliseconds(recorder.recordingDuration))
                .font(.system(size: 44, weight: .light, design: .monospaced))
                .foregroundStyle(recorder.isInterrupted ? .orange : .primary)

            // Status indicator
            HStack(spacing: 8) {
                if recorder.isRecording && !recorder.isInterrupted {
                    Circle()
                        .fill(Color.pinkVibrant)
                        .frame(width: 8, height: 8)
                        .modifier(PulseAnimation())

                    Text("Запись")
                        .foregroundStyle(Color.pinkVibrant)
                } else if recorder.isInterrupted {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(Color.blueVibrant)

                    Text("Пауза")
                        .foregroundStyle(Color.blueVibrant)
                }
            }
            .font(.caption)
            .textCase(.uppercase)

            // Frequency Visualizer
            if recorder.isRecording && !recorder.isInterrupted {
                FrequencyVisualizerView(level: recorder.audioLevel)
                    .frame(height: 60)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            } else {
                Color.clear
                    .frame(height: 60)
            }

            Spacer()

            // Control buttons
            HStack(spacing: 48) {
                // Pause/Resume button
                Button {
                    if recorder.isInterrupted {
                        coordinator.resumeRecording()
                    } else {
                        coordinator.pauseRecording()
                    }
                } label: {
                    Image(systemName: recorder.isInterrupted ? "play.fill" : "pause.fill")
                }
                .buttonStyle(VantaIconButtonStyle(size: 64, isPrimary: false))

                // Stop button
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(VantaIconButtonStyle(size: 64, isPrimary: true))
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }

    private func formatTimeWithMilliseconds(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        // Десятые доли секунды (0-9), всегда с нулём в конце: 10, 20, 30...
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)

        return String(format: "%02d:%02d:%02d:%d0", hours, minutes, seconds, tenths)
    }
}

#Preview {
    struct PreviewWrapper: View {
        var body: some View {
            Color.gray
                .sheet(isPresented: .constant(true)) {
                    ActiveRecordingSheet(
                        preset: .dailyStandup,
                        onStop: {}
                    )
                    .environmentObject(RecordingCoordinator.shared)
                    .environmentObject(RecordingCoordinator.shared.audioRecorder)
                }
        }
    }

    return PreviewWrapper()
}
