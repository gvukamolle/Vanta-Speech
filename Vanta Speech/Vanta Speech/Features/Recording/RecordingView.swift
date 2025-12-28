import SwiftUI
import SwiftData
import Combine

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var recorder: AudioRecorder
    @EnvironmentObject var coordinator: RecordingCoordinator

    @State private var showRecordingSheet = false
    @State private var showRealtimeRecordingSheet = false
    @State private var showRealtimeWarning = false
    @State private var pendingRealtimePreset: RecordingPreset?
    @State private var showError = false
    @State private var errorMessage = ""

    @StateObject private var presetSettings = PresetSettings.shared

    var body: some View {
        NavigationStack {
            ZStack {
                // Decorative background
                VantaDecorativeBackground()
                    .ignoresSafeArea()

                // Main content
                ScrollView {
                    VStack(spacing: 16) {
                        // Active recording banner
                        if recorder.isRecording {
                            activeRecordingBanner
                        }

                        // Today's recordings
                        TodayRecordingsSection()
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
                .background(Color(.systemGroupedBackground).opacity(0.9))

                // Floating microphone button
                VStack {
                    Spacer()
                    microphoneButton
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Запись")
            .sheet(isPresented: $showRecordingSheet) {
                if let preset = coordinator.currentPreset {
                    ActiveRecordingSheet(preset: preset, onStop: stopRecording)
                        .environmentObject(recorder)
                        .environmentObject(coordinator)
                }
            }
            .sheet(isPresented: $showRealtimeRecordingSheet) {
                if let preset = coordinator.currentPreset {
                    RealtimeRecordingSheet(preset: preset, onStop: stopRealtimeRecording)
                        .environmentObject(coordinator)
                }
            }
            .alert("Ошибка", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Real-time транскрипция", isPresented: $showRealtimeWarning) {
                Button("Начать запись") {
                    if let preset = pendingRealtimePreset {
                        startRealtimeRecording(preset: preset)
                    }
                    pendingRealtimePreset = nil
                }
                Button("Отмена", role: .cancel) {
                    pendingRealtimePreset = nil
                }
            } message: {
                Text("В этом режиме не сворачивайте приложение. При сворачивании запись будет приостановлена.")
            }
        }
    }

    // MARK: - Active Recording Banner

    private var activeRecordingBanner: some View {
        Button {
            if coordinator.isRealtimeMode {
                showRealtimeRecordingSheet = true
            } else {
                showRecordingSheet = true
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(coordinator.isRealtimeMode ? Color.green : Color.pinkVibrant)
                    .frame(width: 10, height: 10)
                    .modifier(PulseAnimation())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Идёт запись")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if coordinator.isRealtimeMode {
                        Text("Real-time транскрипция")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(formatTime(recorder.recordingDuration))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background((coordinator.isRealtimeMode ? Color.green : Color.pinkVibrant).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Microphone Button

    @ViewBuilder
    private var microphoneButton: some View {
        if recorder.isRecording {
            // If recording - tapping opens the appropriate sheet
            Button {
                if coordinator.isRealtimeMode {
                    showRealtimeRecordingSheet = true
                } else {
                    showRecordingSheet = true
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(coordinator.isRealtimeMode ? Color.green : Color.pinkVibrant)
                        .frame(width: 8, height: 8)
                        .modifier(PulseAnimation())

                    Image(systemName: coordinator.isRealtimeMode ? "text.badge.plus" : "waveform")

                    Text(formatTime(recorder.recordingDuration))
                        .monospacedDigit()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .vantaGlassProminent(cornerRadius: 28)
            }
            .buttonStyle(.plain)
        } else {
            // If not recording - show menu with presets and mode selection
            Menu {
                ForEach(presetSettings.enabledPresets, id: \.rawValue) { preset in
                    Menu {
                        Button {
                            startRecordingWithPreset(preset, realtime: false)
                        } label: {
                            Label("Обычная запись", systemImage: "waveform")
                        }

                        Button {
                            startRecordingWithPreset(preset, realtime: true)
                        } label: {
                            Label("Real-time транскрипция", systemImage: "text.badge.plus")
                        }
                    } label: {
                        Label(preset.displayName, systemImage: preset.icon)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if recorder.isConverting {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                    }

                    Text("Записать")
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .vantaGlassProminent(cornerRadius: 28)
            }
            .buttonStyle(.plain)
            .disabled(recorder.isConverting)
        }
    }

    // MARK: - Actions

    private func startRecordingWithPreset(_ preset: RecordingPreset, realtime: Bool = false) {
        if realtime {
            // Показываем предупреждение перед real-time записью
            pendingRealtimePreset = preset
            showRealtimeWarning = true
        } else {
            Task {
                do {
                    try await coordinator.startRecording(preset: preset)
                    // Sheet не открываем автоматически - пользователь откроет через баннер при необходимости
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func startRealtimeRecording(preset: RecordingPreset) {
        Task {
            do {
                try await coordinator.startRealtimeRecording(preset: preset)
                showRealtimeRecordingSheet = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func stopRecording() {
        showRecordingSheet = false

        Task {
            _ = await coordinator.stopRecording()
        }
    }

    private func stopRealtimeRecording() {
        showRealtimeRecordingSheet = false

        Task {
            _ = await coordinator.stopRealtimeRecording()
            // Автоматически запускаем саммаризацию
            await coordinator.startRealtimeSummarization()
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

// MARK: - Conveyor Waveform View (Vertical bars like Voice Memos)

struct FrequencyVisualizerView: View {
    let level: Float
    private let barCount = 80
    @State private var samples: [CGFloat] = []

    private let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    init(level: Float) {
        self.level = level
        _samples = State(initialValue: Array(repeating: 0.05, count: barCount))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1.5) {
                ForEach(0..<samples.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.pinkVibrant.opacity(0.85))
                        .frame(
                            width: 2,
                            height: max(2, samples[index] * geometry.size.height)
                        )
                        .animation(.easeOut(duration: 0.08), value: samples[index])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onReceive(timer) { _ in
            updateSamples()
        }
    }

    private func updateSamples() {
        var newSamples = samples
        newSamples.removeFirst()

        let baseHeight = CGFloat(level)
        let variation = CGFloat.random(in: 0.85...1.15)
        let newValue = min(1.0, max(0.03, baseHeight * variation))

        newSamples.append(newValue)
        samples = newSamples
    }
}

// MARK: - Audio Level View (Legacy - kept for compatibility)

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
        .environmentObject(RecordingCoordinator.shared)
        .environmentObject(RecordingCoordinator.shared.audioRecorder)
        .modelContainer(for: Recording.self, inMemory: true)
}
