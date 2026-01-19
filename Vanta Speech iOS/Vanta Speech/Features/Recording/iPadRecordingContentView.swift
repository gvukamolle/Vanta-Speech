import SwiftData
import SwiftUI

/// iPad-оптимизированный view для секции Запись
/// Контролы записи слева, сегодняшние записи справа
struct iPadRecordingContentView: View {
    @Binding var selectedRecording: Recording?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var recorder: AudioRecorder
    @EnvironmentObject var coordinator: RecordingCoordinator

    @Query(sort: \Recording.createdAt, order: .reverse) private var allRecordings: [Recording]
    @StateObject private var presetSettings = PresetSettings.shared
    @StateObject private var calendarManager = EASCalendarManager.shared

    @State private var showRecordingSheet = false
    @State private var showRealtimeRecordingSheet = false
    @State private var showRealtimeWarning = false
    @State private var pendingRealtimePreset: RecordingPreset?
    @State private var showError = false
    @State private var errorMessage = ""

    /// Текущий режим записи в сессии (не сохраняется при перезапуске)
    @State private var currentRecordingMode = "standard"

    private let calendar = Calendar.current

    private var todayRecordings: [Recording] {
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return allRecordings.filter { recording in
            recording.createdAt >= startOfDay && recording.createdAt < endOfDay
        }
    }

    var body: some View {
        ZStack {
            // Градиент на самом заднем фоне
            VantaDecorativeBackground()
                .ignoresSafeArea()

            Color(.systemGroupedBackground).opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Режим записи (временный для сессии)
                Picker("Режим", selection: $currentRecordingMode) {
                    Text("Обычная").tag("standard")
                    Text("Real-time").tag("realtime")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Левая колонка: Контролы записи
                        leftColumn
                            .frame(width: geometry.size.width * 0.5)

                        Divider()

                        // Правая колонка: Сегодняшние записи
                        rightColumn
                            .frame(width: geometry.size.width * 0.5)
                    }
                }
            }
        }
        .navigationTitle("Запись")
        .onAppear {
            // Инициализируем текущий режим из настроек по умолчанию
            let defaultMode = UserDefaults.standard.string(forKey: "defaultRecordingMode") ?? "standard"
            currentRecordingMode = defaultMode
        }
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

    // MARK: - Left Column (Recording Controls)

    private var leftColumn: some View {
        VStack(spacing: 32) {
            Spacer()

            // Active recording indicator
            if recorder.isRecording || coordinator.isRealtimeMode {
                activeRecordingView
            }

            // Large microphone button area
            microphoneSection

            Spacer()
        }
        .padding()
    }

    private var activeRecordingView: some View {
        VStack(spacing: 24) {
            // Waveform visualizer
            FrequencyVisualizerView(level: coordinator.isRealtimeMode
                ? coordinator.realtimeSpeechRecognizer.audioLevel
                : recorder.audioLevel)
                .frame(height: 120)
                .padding(.horizontal)

            // Recording info
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(coordinator.isRealtimeMode ? Color.green : Color.pinkVibrant)
                        .frame(width: 12, height: 12)
                        .modifier(PulseAnimation())

                    Text("Идёт запись")
                        .font(.title3)
                        .fontWeight(.medium)
                }

                if coordinator.isRealtimeMode {
                    Text("Real-time транскрипция")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(formatTime(coordinator.isRealtimeMode
                    ? coordinator.realtimeSpeechRecognizer.recordingDuration
                    : recorder.recordingDuration))
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(.primary)

                if let preset = coordinator.currentPreset {
                    Label(preset.displayName, systemImage: preset.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .vantaGlassCard(cornerRadius: 28, shadowRadius: 0, tintOpacity: 0.15)
    }

    private var microphoneSection: some View {
        VStack(spacing: 20) {
            microphoneButton
                .scaleEffect(1.2) // Larger for iPad

            if !recorder.isRecording {
                Text("Выберите тип встречи и начните запись")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var microphoneButton: some View {
        if recorder.isRecording || coordinator.isRealtimeMode {
            // If recording - tapping opens the appropriate sheet
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

                    Image(systemName: coordinator.isRealtimeMode ? "text.badge.plus" : "waveform")
                        .font(.title2)

                    Text(formatTime(coordinator.isRealtimeMode
                        ? coordinator.realtimeSpeechRecognizer.recordingDuration
                        : recorder.recordingDuration))
                        .font(.title3)
                        .monospacedDigit()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 40)
                .padding(.vertical, 18)
                .vantaGlassProminent(cornerRadius: 32)
            }
            .buttonStyle(.plain)
        } else {
            // If not recording - show menu with preset selection
            // Recording mode is taken from settings
            Menu {
                ForEach(presetSettings.enabledPresets, id: \.rawValue) { preset in
                    Button {
                        let isRealtime = currentRecordingMode == "realtime"
                        startRecordingWithPreset(preset, realtime: isRealtime)
                    } label: {
                        Label(preset.displayName, systemImage: preset.icon)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if recorder.isConverting {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Image(systemName: currentRecordingMode == "realtime" ? "text.badge.plus" : "mic.fill")
                            .font(.title2)
                    }

                    Text(currentRecordingMode == "realtime" ? "Real-time" : "Записать")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 40)
                .padding(.vertical, 18)
                .vantaGlassProminent(cornerRadius: 32)
            }
            .buttonStyle(.plain)
            .disabled(recorder.isConverting)
        }
    }

    // MARK: - Right Column (Today's Recordings)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Сегодня")
                    .font(.headline)

                Spacer()

                Text("\(todayRecordings.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
            .padding()

            Divider()

            // Recordings list
            if todayRecordings.isEmpty {
                emptyTodayView
            } else {
                recordingsList
            }
        }
    }

    private var recordingsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(todayRecordings) { recording in
                    RecordingCard(recording: recording) {
                        selectedRecording = recording
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(selectedRecording?.id == recording.id ? Color.pinkVibrant.opacity(0.1) : Color.clear)
                    )
                    .contextMenu {
                        Button {
                            selectedRecording = recording
                        } label: {
                            Label("Открыть", systemImage: "arrow.right.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            deleteRecording(recording)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            if calendarManager.isConnected {
                await calendarManager.forceFullSync()
            }
        }
    }

    private var emptyTodayView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Нет записей за сегодня")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Начните запись, нажав на кнопку микрофона слева")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                    debugCaptureError(error, context: "Starting recording (iPad)")
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
                debugCaptureError(error, context: "Starting realtime recording (iPad)")
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

    private func deleteRecording(_ recording: Recording) {
        if recording.id == selectedRecording?.id {
            selectedRecording = nil
        }
        if FileManager.default.fileExists(atPath: recording.audioFileURL) {
            try? FileManager.default.removeItem(atPath: recording.audioFileURL)
        }
        modelContext.delete(recording)
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

#Preview {
    iPadRecordingContentView(selectedRecording: .constant(nil))
        .environmentObject(RecordingCoordinator.shared)
        .environmentObject(RecordingCoordinator.shared.audioRecorder)
        .modelContainer(for: Recording.self, inMemory: true)
}
