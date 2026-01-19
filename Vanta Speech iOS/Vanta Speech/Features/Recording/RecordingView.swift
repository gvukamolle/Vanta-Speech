import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

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
    @State private var showFileImporter = false
    @State private var showPresetPickerForImport = false
    @State private var importedAudioData: AudioImporter.ImportedAudio?
    @State private var isImporting = false
    @State private var showPresetPicker = false  // Для выбора пресета перед записью

    @StateObject private var presetSettings = PresetSettings.shared
    @StateObject private var calendarManager = EASCalendarManager.shared

    /// Текущий режим записи в сессии (не сохраняется при перезапуске)
    @State private var currentRecordingMode = "standard"

    /// Текущий режим записи
    private var isRealtimeMode: Bool {
        currentRecordingMode == "realtime"
    }

    /// Режим импорта
    private var isImportMode: Bool {
        currentRecordingMode == "import"
    }

    /// Текущий режим для отображения
    private var currentModeDisplayName: String {
        switch currentRecordingMode {
        case "realtime": return "Real-time"
        case "import": return "Импорт"
        default: return "Записать"
        }
    }

    /// Иконка текущего режима
    private var currentModeIcon: String {
        switch currentRecordingMode {
        case "realtime": return "text.badge.plus"
        case "import": return "square.and.arrow.down"
        default: return "mic.fill"
        }
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
                        Picker("Режим", selection: $currentRecordingMode) {
                            Text("Обычная").tag("standard")
                            Text("Real-time").tag("realtime")
                            Text("Импорт").tag("import")
                        }
                        .pickerStyle(.segmented)

                        // Upcoming meetings from Exchange calendar
                        UpcomingMeetingsSection()
                            .environment(\.currentRecordingMode, currentRecordingMode)

                        // Today's recordings
                        TodayRecordingsSection()
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
                .refreshable {
                    if calendarManager.isConnected {
                        await calendarManager.forceFullSync()
                    }
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
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: AudioImporter.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .sheet(isPresented: $showPresetPickerForImport) {
                if let audioData = importedAudioData {
                    ImportPresetPickerSheet(
                        audioData: audioData,
                        presets: presetSettings.enabledPresets,
                        onSelect: { preset in
                            finalizeImport(audioData: audioData, preset: preset)
                            showPresetPickerForImport = false
                        },
                        onCancel: {
                            // Удаляем импортированный файл если пользователь отменил
                            try? FileManager.default.removeItem(at: audioData.url)
                            importedAudioData = nil
                            showPresetPickerForImport = false
                        }
                    )
                    .presentationDetents([.medium])
                }
            }
            .overlay {
                if isImporting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Импорт...")
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }
            }
            // Preset picker dialog for regular recording (from mic button)
            .confirmationDialog(
                "Выберите тип записи",
                isPresented: $showPresetPicker,
                titleVisibility: .visible
            ) {
                ForEach(presetSettings.enabledPresets, id: \.rawValue) { preset in
                    Button(preset.displayName) {
                        startRecordingWithPreset(preset, realtime: isRealtimeMode)
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    // MARK: - Microphone Button

    private var microphoneButton: some View {
        Button {
            handleButtonTap()
        } label: {
            HStack(spacing: 8) {
                if recorder.isRecording {
                    Circle()
                        .fill(coordinator.isRealtimeMode ? Color.green : Color.pinkVibrant)
                        .frame(width: 8, height: 8)
                        .modifier(PulseAnimation())

                    Image(systemName: coordinator.isRealtimeMode ? "text.badge.plus" : "waveform")

                    Text(formatTime(recorder.recordingDuration))
                        .monospacedDigit()
                } else if recorder.isConverting {
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
        .disabled(recorder.isConverting)
    }

    /// Обработка нажатия на кнопку
    private func handleButtonTap() {
        if recorder.isRecording {
            // Во время записи - открываем sheet
            if coordinator.isRealtimeMode {
                showRealtimeRecordingSheet = true
            } else {
                showRecordingSheet = true
            }
        } else if isImportMode {
            // Режим импорта - открываем file picker
            showFileImporter = true
        } else {
            // Обычный/Real-time режим - показываем выбор пресета
            showPresetPicker = true
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
                    debugCaptureError(error, context: "Starting recording")
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
                debugCaptureError(error, context: "Starting realtime recording")
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

    // MARK: - Import Handling

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            isImporting = true

            Task {
                do {
                    let importer = AudioImporter()
                    let audioData = try await importer.importAudio(from: url)
                    importedAudioData = audioData
                    isImporting = false
                    showPresetPickerForImport = true
                } catch {
                    isImporting = false
                    errorMessage = error.localizedDescription
                    showError = true
                    debugCaptureError(error, context: "Importing audio file")
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
            debugCaptureError(error, context: "File picker error")
        }
    }

    private func finalizeImport(audioData: AudioImporter.ImportedAudio, preset: RecordingPreset) {
        // Создаём Recording
        let recording = Recording(
            id: UUID(),
            title: "\(preset.displayName) - \(audioData.originalFileName)",
            duration: audioData.duration,
            audioFileURL: audioData.url.path,
            preset: preset
        )

        modelContext.insert(recording)
        try? modelContext.save()

        importedAudioData = nil

        debugLog("Import completed: \(audioData.originalFileName), duration: \(audioData.duration)s", module: "RecordingView")
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
                            Label(preset.displayName, systemImage: preset.icon)
                                .foregroundStyle(.primary)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        onCancel()
                    }
                }
            }
        }
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
