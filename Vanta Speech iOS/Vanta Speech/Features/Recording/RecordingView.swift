import SwiftUI
import SwiftData
import Combine

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var recorder: AudioRecorder
    @EnvironmentObject var coordinator: RecordingCoordinator

    @StateObject private var viewModel = RecordingViewModel()
    @State private var showMeetingLinkSecondLevel = false

    /// Текущий режим записи
    private var isRealtimeMode: Bool {
        viewModel.isRealtimeMode
    }

    /// Режим импорта
    private var isImportMode: Bool {
        viewModel.isImportMode
    }

    /// Текущий режим для отображения
    private var currentModeDisplayName: String {
        viewModel.currentModeDisplayName
    }

    /// Иконка текущего режима
    private var currentModeIcon: String {
        viewModel.currentModeIcon
    }

    /// Ближайшая встреча (текущая или следующая в течение 2 часов)
    private var upcomingMeeting: EASCalendarEvent? {
        viewModel.upcomingMeeting
    }
    
    /// Две ближайшие встречи по времени начала (для выбора в RecordingOptionsSheet)
    private var upcomingMeetings: [EASCalendarEvent] {
        viewModel.upcomingMeetings
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Decorative background
                VantaDecorativeBackground()
                    .ignoresSafeArea()

                // Main content
                ScrollView {
                    VStack(spacing: 16) {
                        // Режим записи (временный для сессии)
                        Picker("Режим", selection: $viewModel.currentRecordingMode) {
                            Text("Обычная").tag("standard")
                            Text("Real-time").tag("realtime")
                            Text("Импорт").tag("import")
                        }
                        .pickerStyle(.segmented)

                        // Upcoming meetings from Exchange calendar
                        UpcomingMeetingsSection()
                            .environment(\.currentRecordingMode, viewModel.currentRecordingMode)

                        // Today's recordings
                        TodayRecordingsSection()
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await viewModel.refreshCalendar()
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
            .onAppear {
                viewModel.bind(
                    recorder: recorder,
                    coordinator: coordinator,
                    calendarManager: .shared,
                    presetSettings: .shared,
                    modelContext: modelContext
                )
                viewModel.loadDefaultMode()
            }
            .sheet(isPresented: $viewModel.showRecordingSheet) {
                if let preset = viewModel.currentPreset {
                    ActiveRecordingSheet(preset: preset, onStop: viewModel.stopRecording)
                        .environmentObject(recorder)
                        .environmentObject(coordinator)
                }
            }
            .sheet(isPresented: $viewModel.showRealtimeRecordingSheet) {
                if let preset = viewModel.currentPreset {
                    RealtimeRecordingSheet(preset: preset, onStop: viewModel.stopRealtimeRecording)
                        .environmentObject(coordinator)
                }
            }
            .alert("Ошибка", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("Real-time транскрипция", isPresented: $viewModel.showRealtimeWarning) {
                Button("Начать запись") {
                    viewModel.confirmRealtimeRecording()
                }
                Button("Отмена", role: .cancel) {
                    viewModel.cancelRealtimeRecording()
                }
            } message: {
                Text("В этом режиме не сворачивайте приложение. При сворачивании запись будет приостановлена.")
            }
            .tint(.primary)
            .fileImporter(
                isPresented: $viewModel.showFileImporter,
                allowedContentTypes: AudioImporter.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                viewModel.handleFileImport(result: result)
            }
            .sheet(isPresented: $viewModel.showPresetPickerForImport) {
                if let audioData = viewModel.importedAudioData {
                    ImportPresetPickerSheet(
                        audioData: audioData,
                        presets: viewModel.enabledPresets,
                        onSelect: { preset in
                            viewModel.finalizeImport(audioData: audioData, preset: preset)
                            viewModel.showPresetPickerForImport = false
                        },
                        onCancel: {
                            viewModel.cancelImport()
                            viewModel.showPresetPickerForImport = false
                        }
                    )
                    .presentationDetents([.medium])
                }
            }
            .meetingLinkingAlert(
                isPresented: $viewModel.showMeetingLinkWarning,
                showSecondLevel: $showMeetingLinkSecondLevel,
                for: viewModel.realtimeRecording ?? Recording(title: "", audioFileURL: ""),
                onSend: {
                    viewModel.proceedWithRealtimeSummary()
                },
                onLink: {
                    // Для real-time открываем RecordingDetailView с выбором встречи
                    // Запись уже сохранена, пользователь может привязать вручную
                    viewModel.cancelRealtimeSummary()
                }
            )
            .overlay {
                if viewModel.isImporting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Импорт...")
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }
            }
            // Sheet для выбора пресета с предложением привязки к встрече
            .sheet(isPresented: $viewModel.showRecordingOptionsSheet) {
                RecordingOptionsSheet(
                    upcomingMeetings: upcomingMeetings,
                    presets: viewModel.enabledPresets,
                    isRealtimeMode: isRealtimeMode,
                    onSelectPreset: { preset, selectedMeeting in
                        viewModel.showRecordingOptionsSheet = false
                        if let meeting = selectedMeeting {
                            MeetingRecordingLink.shared.pendingMeetingEvent = meeting
                        }
                        viewModel.startRecordingWithPreset(preset, realtime: isRealtimeMode)
                    },
                    onCancel: {
                        viewModel.showRecordingOptionsSheet = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Microphone Button

    private var microphoneButton: some View {
        Button {
            viewModel.handleButtonTap()
        } label: {
            HStack(spacing: 8) {
                if viewModel.isRecording {
                    Circle()
                        .fill(viewModel.isRealtimeActive ? Color.green : Color.pinkVibrant)
                        .frame(width: 8, height: 8)
                        .modifier(PulseAnimation())

                    Image(systemName: viewModel.isRealtimeActive ? "text.badge.plus" : "waveform")

                    Text(formatTime(viewModel.recordingDuration))
                        .monospacedDigit()
                } else if viewModel.isConverting {
                    ProgressView()
                        .tint(.primary)

                    Text("Обработка...")
                        .font(.body)
                        .fontWeight(.semibold)
                } else {
                    Image(systemName: currentModeIcon)
                        .font(.title3)
                        .frame(width: 24, height: 24)

                    Text(currentModeDisplayName)
                        .font(.body)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(.primary)
            .frame(minWidth: 160)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .vantaGlassProminent(cornerRadius: 28)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isConverting)
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
            // Fix for iPad: contain the animation within fixed frame to prevent layout shifts
            .frame(width: 12, height: 12)
            .clipped()
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

// MARK: - Import Preset Picker Sheet

struct ImportPresetPickerSheet: View {
    let audioData: AudioImporter.ImportedAudio
    let presets: [RecordingPreset]
    let onSelect: (RecordingPreset) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(audioData.originalFileName)
                                .font(.headline)
                            Text(formatDuration(audioData.duration))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Импортированный файл")
                }

                Section {
                    ForEach(presets, id: \.rawValue) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            Label {
                                Text(preset.displayName)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: preset.icon)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } header: {
                    Text("Выберите тип записи")
                } footer: {
                    Text("Тип записи влияет на формат транскрипции и саммари")
                }
            }
            .navigationTitle("Импорт аудио")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.primary)
        .presentationDragIndicator(.visible)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d ч %02d мин", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%d мин %02d сек", minutes, seconds)
        } else {
            return String(format: "%d сек", seconds)
        }
    }
}

#Preview {
    RecordingView()
        .environmentObject(RecordingCoordinator.shared)
        .environmentObject(RecordingCoordinator.shared.audioRecorder)
        .modelContainer(for: Recording.self, inMemory: true)
}
