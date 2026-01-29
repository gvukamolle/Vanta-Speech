import SwiftUI

struct RealtimeRecordingSheet: View {
    @EnvironmentObject var coordinator: RecordingCoordinator
    @ObservedObject var speechRecognizer: RealtimeSpeechRecognizer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let preset: RecordingPreset
    let onStop: () -> Void

    @State private var showBackgroundWarning = false
    @State private var wasBackgrounded = false
    @State private var showNoTranscriptionWarning = false
    @State private var isStopping = false

    init(preset: RecordingPreset, onStop: @escaping () -> Void) {
        self.preset = preset
        self.onStop = onStop
        // Получаем speech recognizer из coordinator
        self._speechRecognizer = ObservedObject(wrappedValue: RecordingCoordinator.shared.realtimeSpeechRecognizer)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Transcription content
            transcriptionScrollView

            Divider()

            // Status bar
            statusBar

            // Control buttons
            controlButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(speechRecognizer.isRecording || isStopping)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .alert("Запись приостановлена", isPresented: $showBackgroundWarning) {
            Button("Продолжить запись") {
                coordinator.resumeRecording()
                wasBackgrounded = false
            }
            Button("Закончить запись", role: .destructive) {
                confirmStopRecording()
            }
        } message: {
            Text("Приложение было свёрнуто. Real-time транскрипция работает только при активном приложении.")
        }
        .tint(.primary)
        .alert("Слишком короткая запись", isPresented: $showNoTranscriptionWarning) {
            Button("Продолжить запись") {
                // Just dismiss the alert and continue recording
                showNoTranscriptionWarning = false
            }
            Button("Удалить запись", role: .destructive) {
                discardRecording()
            }
        } message: {
            Text("Запись не содержит распознанной речи. Возможно, микрофон не работал или запись была слишком короткой. Запись не будет сохранена.")
        }
        .tint(.primary)
    }
    
    // MARK: - Recording Control
    
    private func confirmStopRecording() {
        // Check if we have any transcription
        let hasTranscription = !(coordinator.realtimeManager?.paragraphs.isEmpty ?? true)
        let hasInterimText = !speechRecognizer.interimText.isEmpty
        
        if !hasTranscription && !hasInterimText {
            // No transcription at all - show warning
            showNoTranscriptionWarning = true
        } else {
            onStop()
        }
    }
    
    private func discardRecording() {
        // Stop recording without saving
        Task {
            isStopping = true
            await coordinator.stopRealtimeRecordingAndDiscard()
            isStopping = false
            onStop()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            // Preset indicator with LIVE badge
            HStack(spacing: 8) {
                Image(systemName: preset.icon)
                Text(preset.displayName)

                Spacer()

                // Realtime badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // Timer - используем данные от speech recognizer
            Text(formatTimeWithMilliseconds(speechRecognizer.recordingDuration))
                .font(.system(size: 32, weight: .light, design: .monospaced))
                .foregroundStyle(speechRecognizer.isInterrupted ? .orange : .primary)

            // Frequency Visualizer
            if speechRecognizer.isRecording && !speechRecognizer.isInterrupted {
                FrequencyVisualizerView(level: speechRecognizer.audioLevel)
                    .frame(height: 40)
                    .transition(.opacity)
            } else {
                Color.clear
                    .frame(height: 40)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Transcription ScrollView

    private var transcriptionScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let manager = coordinator.realtimeManager {
                        ForEach(manager.paragraphs) { paragraph in
                            ParagraphView(paragraph: paragraph)
                                .id(paragraph.id)
                        }
                    }

                    // Текущий interim текст от локальной диктовки (напрямую от speechRecognizer)
                    if !speechRecognizer.interimText.isEmpty {
                        InterimTextView(text: speechRecognizer.interimText)
                            .id("interim")
                    }

                    // Invisible anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")

                    if coordinator.realtimeManager?.paragraphs.isEmpty ?? true,
                       speechRecognizer.interimText.isEmpty {
                        emptyStateView
                    }
                }
                .padding()
            }
            .onChange(of: coordinator.realtimeManager?.paragraphs.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: speechRecognizer.interimText) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Начните говорить...")
                .foregroundStyle(.secondary)
                .italic()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            // Recording status - используем данные от speech recognizer
            HStack(spacing: 6) {
                // Фиксированный контейнер для стабильного layout на iPad
                ZStack {
                    if speechRecognizer.isRecording && !speechRecognizer.isInterrupted {
                        HStack(spacing: 6) {
                            RecordingIndicatorDot()
                            Text("Запись")
                                .foregroundStyle(.primary)
                        }
                    } else if speechRecognizer.isInterrupted {
                        HStack(spacing: 6) {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(Color.blueVibrant)
                            Text("Пауза")
                                .foregroundStyle(Color.blueVibrant)
                        }
                    }
                }
                .frame(minWidth: 80, alignment: .leading)
            }
            .font(.caption)
            .textCase(.uppercase)

            Spacer()

            // Pending chunks indicator
            if let manager = coordinator.realtimeManager {
                if manager.pendingChunksCount > 0 {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("\(manager.pendingChunksCount) в обработке")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if manager.completedParagraphsCount > 0 {
                    Text("\(manager.completedParagraphsCount) абзац(ев)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: 48) {
            // Pause/Resume button - используем данные от speech recognizer
            Button {
                if speechRecognizer.isInterrupted {
                    coordinator.resumeRecording()
                } else {
                    coordinator.pauseRecording()
                }
            } label: {
                Image(systemName: speechRecognizer.isInterrupted ? "play.fill" : "pause.fill")
            }
            .buttonStyle(VantaIconButtonStyle(size: 56, isPrimary: false))

            // Stop button
            Button(action: confirmStopRecording) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(VantaIconButtonStyle(size: 56, isPrimary: true))
            .disabled(isStopping)
        }
        .padding()
        .padding(.bottom, 16)
    }

    // MARK: - Scene Phase Handling

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            if speechRecognizer.isRecording && !speechRecognizer.isInterrupted {
                // Приостанавливаем запись при сворачивании
                coordinator.pauseRecording()
                wasBackgrounded = true
                debugLog("App backgrounded, recording paused", module: "RealtimeRecordingSheet")
            }
        case .active:
            if wasBackgrounded {
                showBackgroundWarning = true
            }
        @unknown default:
            break
        }
    }

    // MARK: - Helpers

    private func formatTimeWithMilliseconds(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d:%02d:%d0", hours, minutes, seconds, tenths)
    }
}

// MARK: - Paragraph View

private struct ParagraphView: View {
    let paragraph: RealtimeTranscriptionManager.Paragraph

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Timestamp
            Text(formatTimestamp(paragraph.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Text content
            Group {
                switch paragraph.status {
                case .transcribing:
                    VStack(alignment: .leading, spacing: 4) {
                        // Показываем preview от локальной диктовки
                        Text(paragraph.displayText)
                            .font(.body)
                            .foregroundStyle(.primary.opacity(0.7))

                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Обработка...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .completed:
                    Text(paragraph.text)
                        .font(.body)
                case .failed:
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Ошибка транскрипции")
                            .foregroundStyle(.red)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var backgroundColor: Color {
        switch paragraph.status {
        case .transcribing:
            return Color.blue.opacity(0.1)
        case .completed:
            return Color(.tertiarySystemBackground)
        case .failed:
            return Color.red.opacity(0.1)
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Interim Text View

private struct InterimTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Вы говорите...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(text)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Recording Indicator Dot (стабильная анимация для iPad)

private struct RecordingIndicatorDot: View {
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(Color.primary)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        var body: some View {
            Color.gray
                .sheet(isPresented: .constant(true)) {
                    RealtimeRecordingSheet(
                        preset: .projectMeeting,
                        onStop: {}
                    )
                    .environmentObject(RecordingCoordinator.shared)
                }
        }
    }

    return PreviewWrapper()
}
