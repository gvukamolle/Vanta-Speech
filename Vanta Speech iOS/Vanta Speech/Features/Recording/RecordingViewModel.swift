import Foundation
import Combine
import SwiftData
import SwiftUI

@MainActor
final class RecordingViewModel: ObservableObject {
    // MARK: - UI State

    @Published var currentRecordingMode: String = "standard"
    @Published var showRecordingSheet = false
    @Published var showRealtimeRecordingSheet = false
    @Published var showRealtimeWarning = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showFileImporter = false
    @Published var showPresetPickerForImport = false
    @Published var importedAudioData: AudioImporter.ImportedAudio?
    @Published var isImporting = false
    @Published var showRecordingOptionsSheet = false

    private var pendingRealtimePreset: RecordingPreset?

    // MARK: - Dependencies

    private var recorder: AudioRecorder
    private var coordinator: RecordingCoordinator
    private var calendarManager: EASCalendarManager
    private var presetSettings: PresetSettings
    private let audioImporter = AudioImporter()
    private var modelContext: ModelContext?

    private var cancellables = Set<AnyCancellable>()

    init(
        recorder: AudioRecorder = RecordingCoordinator.shared.audioRecorder,
        coordinator: RecordingCoordinator = .shared,
        calendarManager: EASCalendarManager = .shared,
        presetSettings: PresetSettings = .shared
    ) {
        self.recorder = recorder
        self.coordinator = coordinator
        self.calendarManager = calendarManager
        self.presetSettings = presetSettings

        configureSubscriptions()
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func bind(
        recorder: AudioRecorder,
        coordinator: RecordingCoordinator,
        calendarManager: EASCalendarManager,
        presetSettings: PresetSettings,
        modelContext: ModelContext
    ) {
        self.recorder = recorder
        self.coordinator = coordinator
        self.calendarManager = calendarManager
        self.presetSettings = presetSettings
        self.modelContext = modelContext
        configureSubscriptions()
    }

    func loadDefaultMode() {
        let defaultMode = UserDefaults.standard.string(forKey: "defaultRecordingMode") ?? "standard"
        currentRecordingMode = defaultMode
    }

    // MARK: - Derived State

    var isRealtimeMode: Bool {
        currentRecordingMode == "realtime"
    }

    var isImportMode: Bool {
        currentRecordingMode == "import"
    }

    var currentModeDisplayName: String {
        switch currentRecordingMode {
        case "realtime": return "Real-time"
        case "import": return "Импорт"
        default: return "Записать"
        }
    }

    var currentModeIcon: String {
        switch currentRecordingMode {
        case "realtime": return "text.badge.plus"
        case "import": return "square.and.arrow.down"
        default: return "mic.fill"
        }
    }

    var isRecording: Bool {
        recorder.isRecording
    }

    var isConverting: Bool {
        recorder.isConverting
    }

    var isRealtimeActive: Bool {
        coordinator.isRealtimeMode
    }

    var recordingDuration: TimeInterval {
        coordinator.currentRecordingDuration
    }

    var currentAudioLevel: Float {
        coordinator.currentAudioLevel
    }

    var isCurrentRecordingInterrupted: Bool {
        coordinator.isCurrentRecordingInterrupted
    }

    var currentPreset: RecordingPreset? {
        coordinator.currentPreset
    }

    var enabledPresets: [RecordingPreset] {
        presetSettings.enabledPresets
    }

    var upcomingMeeting: EASCalendarEvent? {
        upcomingMeetings.first
    }
    
    /// Две ближайшие встречи по времени начала (для выбора в RecordingOptionsSheet)
    var upcomingMeetings: [EASCalendarEvent] {
        let now = Date()
        let twoHoursLater = now.addingTimeInterval(2 * 60 * 60)

        return calendarManager.cachedEvents
            .filter { event in
                let isOngoing = event.startTime <= now && event.endTime > now
                let isUpcoming = event.startTime > now && event.startTime <= twoHoursLater
                return isOngoing || isUpcoming
            }
            .sorted { $0.startTime < $1.startTime }
            .prefix(2)
            .map { $0 }
    }

    // MARK: - Actions

    func refreshCalendar() async {
        guard calendarManager.isConnected else { return }
        await calendarManager.forceFullSync()
    }

    func handleButtonTap() {
        if isRecording {
            if isRealtimeActive {
                showRealtimeRecordingSheet = true
            } else {
                showRecordingSheet = true
            }
        } else if isImportMode {
            showFileImporter = true
        } else {
            showRecordingOptionsSheet = true
        }
    }

    func startRecordingWithPreset(_ preset: RecordingPreset, realtime: Bool = false) {
        if realtime {
            pendingRealtimePreset = preset
            showRealtimeWarning = true
        } else {
            Task {
                do {
                    try await coordinator.startRecording(preset: preset)
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                    debugCaptureError(error, context: "Starting recording")
                }
            }
        }
    }

    func confirmRealtimeRecording() {
        guard let preset = pendingRealtimePreset else { return }
        pendingRealtimePreset = nil
        startRealtimeRecording(preset: preset)
    }

    func cancelRealtimeRecording() {
        pendingRealtimePreset = nil
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

    func stopRecording() {
        showRecordingSheet = false

        Task {
            _ = await coordinator.stopRecording()

            if UserDefaults.standard.bool(forKey: "autoTranscribe") {
                await coordinator.startTranscription()
            }
        }
    }

    // MARK: - Meeting Linking Warning for Realtime
    
    @Published var showMeetingLinkWarning = false
    private var shouldStartRealtimeSummary = false
    var realtimeRecording: Recording?
    
    func stopRealtimeRecording() {
        showRealtimeRecordingSheet = false

        Task {
            if let recording = await coordinator.stopRealtimeRecording() {
                // Проверяем привязку к встрече
                let needsWarning = await MainActor.run { () -> Bool in
                    self.realtimeRecording = recording
                    let needsLink = !recording.hasLinkedMeeting && !self.todayEvents.isEmpty
                    if needsLink {
                        self.shouldStartRealtimeSummary = true
                        self.showMeetingLinkWarning = true
                    }
                    return needsLink
                }
                
                // Если не нужно предупреждение - сразу отправляем на саммари
                if !needsWarning {
                    await coordinator.startRealtimeSummarization()
                }
            }
        }
    }
    
    func proceedWithRealtimeSummary() {
        if shouldStartRealtimeSummary {
            Task {
                await coordinator.startRealtimeSummarization()
                await MainActor.run {
                    self.shouldStartRealtimeSummary = false
                    self.realtimeRecording = nil
                }
            }
        }
    }
    
    func cancelRealtimeSummary() {
        shouldStartRealtimeSummary = false
        realtimeRecording = nil
    }
    
    private var todayEvents: [EASCalendarEvent] {
        calendarManager.cachedEvents.filter { event in
            Calendar.current.isDate(event.startTime, inSameDayAs: Date())
        }.sorted { $0.startTime < $1.startTime }
    }

    func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            isImporting = true

            Task {
                do {
                    let audioData = try await audioImporter.importAudio(from: url)
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

    func finalizeImport(audioData: AudioImporter.ImportedAudio, preset: RecordingPreset) {
        guard let modelContext else {
            errorMessage = "Не удалось сохранить запись"
            showError = true
            return
        }

        let recording = Recording(
            id: UUID(),
            title: "\(preset.displayName) - \(audioData.originalFileName)",
            duration: audioData.duration,
            audioFileURL: audioData.url.path,
            preset: preset
        )

        modelContext.insert(recording)
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            debugCaptureError(error, context: "Saving imported recording")
        }

        importedAudioData = nil

        debugLog("Import completed: \(audioData.originalFileName), duration: \(audioData.duration)s", module: "RecordingView")
    }

    func cancelImport() {
        if let audioData = importedAudioData {
            try? FileManager.default.removeItem(at: audioData.url)
        }
        importedAudioData = nil
    }

    private func configureSubscriptions() {
        cancellables.removeAll()

        recorder.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        coordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        calendarManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        presetSettings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
