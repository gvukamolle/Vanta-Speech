import Combine
import Foundation
import SwiftData

/// Координатор для управления записью, Live Activity и транскрипцией
/// Связывает AudioRecorder, LiveActivityManager и TranscriptionService
@MainActor
final class RecordingCoordinator: ObservableObject {

    static let shared = RecordingCoordinator()

    // MARK: - Dependencies

    let audioRecorder: AudioRecorder
    let liveActivityManager: LiveActivityManager

    // MARK: - State

    @Published var currentPreset: RecordingPreset?
    @Published var currentRecordingId: UUID?
    @Published private(set) var pendingTranscription: PendingTranscription?
    @Published private(set) var isTranscribing = false
    @Published private(set) var isContinuingRecording = false

    private var cancellables = Set<AnyCancellable>()
    private weak var modelContext: ModelContext?
    private var didCheckPendingShortcut = false

    /// Данные для продолжения записи (склейки)
    private var continuationData: ContinuationData?

    struct ContinuationData {
        let originalRecordingId: UUID
        let originalAudioURL: URL
        let originalDuration: TimeInterval
    }

    // MARK: - Pending Transcription Data

    struct PendingTranscription {
        let recordingId: UUID
        let audioURL: URL
        let duration: TimeInterval
        let preset: RecordingPreset
    }

    // MARK: - Init

    private init() {
        self.audioRecorder = AudioRecorder()
        self.liveActivityManager = LiveActivityManager.shared

        setupNotificationObservers()
        setupAudioRecorderObservers()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context

        // Проверяем pending shortcut только ОДИН раз после установки ModelContext
        guard !didCheckPendingShortcut else { return }
        didCheckPendingShortcut = true
        checkForPendingShortcutRecording()
    }

    // MARK: - Recording Flow

    /// Начать запись с указанным шаблоном
    func startRecording(preset: RecordingPreset) async throws {
        currentPreset = preset
        currentRecordingId = UUID()

        let fileURL = try await audioRecorder.startRecording()

        // Запускаем Live Activity
        if let id = currentRecordingId {
            do {
                try liveActivityManager.startActivity(
                    recordingId: id,
                    preset: preset
                )
                // Первый апдейт сразу после старта
                await liveActivityManager.updateRecording(duration: 0, audioLevel: 0)
            } catch {
                print("[RecordingCoordinator] Failed to start Live Activity: \(error)")
            }
        }

        print("[RecordingCoordinator] Recording started with preset: \(preset.displayName)")
    }

    /// Продолжить запись существующей записи (для склейки)
    /// Очищает транскрипцию и саммари, после остановки склеит аудиофайлы
    func continueRecording(recording: Recording) async throws {
        guard let preset = recording.preset else {
            throw RecordingCoordinatorError.noPreset
        }

        // Сохраняем данные для последующей склейки
        let originalURL = URL(fileURLWithPath: recording.audioFileURL)
        continuationData = ContinuationData(
            originalRecordingId: recording.id,
            originalAudioURL: originalURL,
            originalDuration: recording.duration
        )

        // Очищаем транскрипцию и саммари
        recording.transcriptionText = nil
        recording.summaryText = nil
        recording.isTranscribed = false
        try? modelContext?.save()

        // Устанавливаем состояние
        currentPreset = preset
        currentRecordingId = recording.id
        isContinuingRecording = true

        // Начинаем новую запись
        let fileURL = try await audioRecorder.startRecording()

        // Запускаем Live Activity с начальным временем = старая длительность
        do {
            try liveActivityManager.startActivity(
                recordingId: recording.id,
                preset: preset
            )
            await liveActivityManager.updateRecording(
                duration: recording.duration,
                audioLevel: 0
            )
        } catch {
            print("[RecordingCoordinator] Failed to start Live Activity: \(error)")
        }

        print("[RecordingCoordinator] Continuing recording: \(recording.id), original duration: \(recording.duration)s")
    }

    /// Поставить запись на паузу
    func pauseRecording() {
        audioRecorder.pauseRecording()

        Task {
            await liveActivityManager.updatePaused(duration: audioRecorder.recordingDuration)
        }
    }

    /// Возобновить запись
    func resumeRecording() {
        audioRecorder.resumeRecording()

        // Явно обновляем Live Activity сразу после возобновления
        Task {
            await liveActivityManager.updateRecording(
                duration: audioRecorder.recordingDuration,
                audioLevel: audioRecorder.audioLevel
            )
        }
    }

    /// Остановить запись
    func stopRecording() async -> Recording? {
        guard let preset = currentPreset,
              let recordingId = currentRecordingId else { return nil }

        let result = await audioRecorder.stopRecording(convertToOGG: false)

        switch result {
        case .success(let data):
            var finalURL = data.url
            var finalDuration = data.duration

            // Если это продолжение записи - склеиваем файлы
            if let continuation = continuationData, isContinuingRecording {
                do {
                    let mergeResult = try await audioRecorder.mergeAudioFiles(
                        firstURL: continuation.originalAudioURL,
                        secondURL: data.url,
                        deleteSecond: true
                    )
                    finalURL = mergeResult.url
                    finalDuration = mergeResult.duration
                    print("[RecordingCoordinator] Audio files merged, total duration: \(finalDuration)s")
                } catch {
                    print("[RecordingCoordinator] Failed to merge audio: \(error)")
                    // Если склейка не удалась, используем новый файл
                }

                // Обновляем существующую запись
                if let context = modelContext {
                    let descriptor = FetchDescriptor<Recording>(
                        predicate: #Predicate { $0.id == recordingId }
                    )
                    if let recordings = try? context.fetch(descriptor),
                       let recording = recordings.first {
                        recording.duration = finalDuration
                        recording.audioFileURL = finalURL.path
                        try? context.save()

                        // Сохраняем для возможной транскрипции
                        pendingTranscription = PendingTranscription(
                            recordingId: recordingId,
                            audioURL: finalURL,
                            duration: finalDuration,
                            preset: preset
                        )

                        // Обновляем Live Activity в состояние "stopped"
                        await liveActivityManager.updateStopped(
                            duration: finalDuration,
                            audioFileURL: finalURL.path
                        )

                        continuationData = nil
                        isContinuingRecording = false
                        currentPreset = nil
                        currentRecordingId = nil

                        print("[RecordingCoordinator] Continued recording stopped, ready for transcription")
                        return recording
                    }
                }

                continuationData = nil
                isContinuingRecording = false
                currentPreset = nil
                currentRecordingId = nil
                return nil
            }

            // Обычная новая запись
            let recording = Recording(
                id: recordingId,
                title: "\(preset.displayName) \(formatDate(Date()))",
                duration: data.duration,
                audioFileURL: data.url.path,
                preset: preset
            )

            modelContext?.insert(recording)
            try? modelContext?.save()

            // Сохраняем для возможной транскрипции
            pendingTranscription = PendingTranscription(
                recordingId: recordingId,
                audioURL: data.url,
                duration: data.duration,
                preset: preset
            )

            // Обновляем Live Activity в состояние "stopped"
            await liveActivityManager.updateStopped(
                duration: data.duration,
                audioFileURL: data.url.path
            )

            currentPreset = nil
            currentRecordingId = nil

            print("[RecordingCoordinator] Recording stopped, ready for transcription")
            return recording

        case .failure(let error):
            print("[RecordingCoordinator] Failed to stop recording: \(error)")
            continuationData = nil
            isContinuingRecording = false
            currentPreset = nil
            currentRecordingId = nil
            return nil
        }
    }

    // MARK: - Transcription Flow

    /// Начать транскрипцию pending записи
    func startTranscription() async {
        print("[RecordingCoordinator] startTranscription called")

        guard let pending = pendingTranscription else {
            print("[RecordingCoordinator] No pending transcription - pendingTranscription is nil!")
            return
        }

        print("[RecordingCoordinator] Starting transcription for recording: \(pending.recordingId)")
        print("[RecordingCoordinator] Audio URL: \(pending.audioURL)")

        isTranscribing = true

        // Обновляем Live Activity
        await liveActivityManager.updateTranscribing(progress: 0.1)

        do {
            let service = TranscriptionService()

            // Симулируем прогресс (API не даёт реального прогресса)
            let progressTask = Task {
                for i in 1...8 {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 сек
                    await liveActivityManager.updateTranscribing(progress: Double(i) * 0.1)
                }
            }

            let result = try await service.transcribe(
                audioFileURL: pending.audioURL,
                preset: pending.preset
            )

            progressTask.cancel()

            // Обновляем запись в SwiftData
            await updateRecording(
                id: pending.recordingId,
                transcription: result.transcription,
                summary: result.summary,
                title: result.generatedTitle
            )

            // Завершаем Live Activity
            await liveActivityManager.endWithCompletion(recordingId: pending.recordingId)

            pendingTranscription = nil
            isTranscribing = false

            print("[RecordingCoordinator] Transcription completed successfully")

        } catch {
            print("[RecordingCoordinator] Transcription failed: \(error)")
            // Завершаем Live Activity с ошибкой
            await liveActivityManager.endActivityImmediately()
            pendingTranscription = nil
            isTranscribing = false
        }
    }

    /// Отменить pending транскрипцию и закрыть Live Activity
    func cancelPendingTranscription() async {
        pendingTranscription = nil
        await liveActivityManager.endActivityImmediately()
    }

    // MARK: - Private Methods

    private func updateRecording(
        id: UUID,
        transcription: String,
        summary: String?,
        title: String?
    ) async {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            let recordings = try context.fetch(descriptor)
            if let recording = recordings.first {
                recording.transcriptionText = transcription
                recording.summaryText = summary
                if let newTitle = title {
                    recording.title = newTitle
                }
                recording.isTranscribed = true
                recording.isUploading = false
                try context.save()
            }
        } catch {
            print("[RecordingCoordinator] Failed to update recording: \(error)")
        }
    }

    private func setupNotificationObservers() {
        // From Shortcut - start recording
        NotificationCenter.default.publisher(for: .startRecordingFromShortcut)
            .sink { [weak self] notification in
                guard let presetId = notification.userInfo?["presetId"] as? String,
                      let preset = RecordingPreset(rawValue: presetId) else { return }

                Task { @MainActor in
                    try? await self?.startRecording(preset: preset)
                }
            }
            .store(in: &cancellables)

        // From Live Activity - pause
        NotificationCenter.default.publisher(for: .pauseRecordingFromLiveActivity)
            .sink { [weak self] _ in
                self?.pauseRecording()
            }
            .store(in: &cancellables)

        // From Live Activity - resume
        NotificationCenter.default.publisher(for: .resumeRecordingFromLiveActivity)
            .sink { [weak self] _ in
                self?.resumeRecording()
            }
            .store(in: &cancellables)

        // From Live Activity - stop
        NotificationCenter.default.publisher(for: .stopRecordingFromLiveActivity)
            .sink { [weak self] _ in
                Task { @MainActor in
                    _ = await self?.stopRecording()
                }
            }
            .store(in: &cancellables)

        // From Live Activity - start transcription
        NotificationCenter.default.publisher(for: .startTranscriptionFromLiveActivity)
            .sink { [weak self] _ in
                print("[RecordingCoordinator] Received startTranscriptionFromLiveActivity notification")
                Task { @MainActor in
                    await self?.startTranscription()
                }
            }
            .store(in: &cancellables)

        // From Live Activity - open recording
        NotificationCenter.default.publisher(for: .openRecordingFromLiveActivity)
            .sink { notification in
                if let recordingId = notification.userInfo?["recordingId"] as? String {
                    print("[RecordingCoordinator] Open recording requested: \(recordingId)")
                    // TODO: Implement navigation to recording detail
                }
            }
            .store(in: &cancellables)

        // From Live Activity - dismiss (Отлично - закрыть без транскрипции)
        NotificationCenter.default.publisher(for: .dismissActivityFromLiveActivity)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.dismissActivity()
                }
            }
            .store(in: &cancellables)

        // From Live Activity - hide (Скрыть во время транскрипции)
        NotificationCenter.default.publisher(for: .hideActivityFromLiveActivity)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.hideActivity()
                }
            }
            .store(in: &cancellables)
    }

    /// Закрыть Live Activity без транскрипции
    func dismissActivity() async {
        pendingTranscription = nil
        await liveActivityManager.endActivityImmediately()
        print("[RecordingCoordinator] Activity dismissed without transcription")
    }

    /// Скрыть Live Activity (во время транскрипции продолжает работать в фоне)
    func hideActivity() async {
        await liveActivityManager.endActivityImmediately()
        print("[RecordingCoordinator] Activity hidden, transcription continues in background")
    }

    private func setupAudioRecorderObservers() {
        // Observe recording state changes to update Live Activity
        // Убрали filter по isRecording - он блокировал первые обновления
        audioRecorder.$recordingDuration
            .combineLatest(audioRecorder.$audioLevel)
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _, level in
                guard let self = self,
                      self.currentPreset != nil,
                      !self.audioRecorder.isInterrupted else { return }
                Task {
                    // Используем displayDuration для учёта продолжения записи
                    await self.liveActivityManager.updateRecording(duration: self.displayDuration, audioLevel: level)
                }
            }
            .store(in: &cancellables)
    }

    /// Проверяем, был ли запущен Shortcut до запуска приложения
    private func checkForPendingShortcutRecording() {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        guard let presetId = defaults?.string(forKey: "pending_recording_preset") else {
            return
        }

        // Проверяем timestamp - если ключ старше 10 секунд, это "зависший" ключ от предыдущей сессии
        let timestamp = defaults?.double(forKey: "pending_recording_timestamp") ?? 0
        let age = Date().timeIntervalSince1970 - timestamp

        // ВАЖНО: Очищаем ключи СРАЗУ, до попытки начать запись
        defaults?.removeObject(forKey: "pending_recording_preset")
        defaults?.removeObject(forKey: "pending_recording_timestamp")
        defaults?.synchronize()

        // Игнорируем старые ключи (> 10 секунд)
        if age > 10 {
            print("[RecordingCoordinator] Ignoring stale pending preset (age: \(Int(age))s)")
            return
        }

        guard let preset = RecordingPreset(rawValue: presetId) else {
            print("[RecordingCoordinator] Invalid preset id from shortcut: \(presetId)")
            return
        }

        // Начинаем запись
        print("[RecordingCoordinator] Starting recording from shortcut (age: \(Int(age))s)")
        Task {
            try? await startRecording(preset: preset)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    /// Общая длительность для отображения (учитывает продолжение записи)
    var displayDuration: TimeInterval {
        if isContinuingRecording, let continuation = continuationData {
            return continuation.originalDuration + audioRecorder.recordingDuration
        }
        return audioRecorder.recordingDuration
    }
}

// MARK: - Errors

enum RecordingCoordinatorError: LocalizedError {
    case noPreset
    case recordingNotFound

    var errorDescription: String? {
        switch self {
        case .noPreset:
            return "У записи отсутствует шаблон. Продолжение невозможно."
        case .recordingNotFound:
            return "Запись не найдена."
        }
    }
}
