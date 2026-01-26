import ActivityKit
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

    // MARK: - Realtime Mode State

    @Published private(set) var isRealtimeMode = false
    @Published private(set) var realtimeManager: RealtimeTranscriptionManager?
    let realtimeSpeechRecognizer = RealtimeSpeechRecognizer()

    /// Длительность записи для текущего режима
    var currentRecordingDuration: TimeInterval {
        if isRealtimeMode {
            return realtimeSpeechRecognizer.recordingDuration
        }
        return audioRecorder.recordingDuration
    }

    /// Уровень аудио для текущего режима
    var currentAudioLevel: Float {
        if isRealtimeMode {
            return realtimeSpeechRecognizer.audioLevel
        }
        return audioRecorder.audioLevel
    }

    /// Приостановлена ли запись для текущего режима
    var isCurrentRecordingInterrupted: Bool {
        if isRealtimeMode {
            return realtimeSpeechRecognizer.isInterrupted
        }
        return audioRecorder.isInterrupted
    }

    private var cancellables = Set<AnyCancellable>()
    /// Отдельный Set для realtime subscriptions (очищается при остановке)
    private var realtimeCancellables = Set<AnyCancellable>()
    private weak var modelContext: ModelContext?
    private var didCheckPendingShortcut = false
    private var transcriptionTask: Task<Void, Never>?

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
                try await liveActivityManager.startActivity(
                    recordingId: id,
                    preset: preset
                )
                // Первый апдейт сразу после старта
                await liveActivityManager.updateRecording(duration: 0, audioLevel: 0)
            } catch {
                debugLog("Failed to start Live Activity: \(error)", module: "RecordingCoordinator", level: .error)
                debugCaptureError(error, context: "Starting Live Activity")
            }
        }

        debugLog("Recording started with preset: \(preset.displayName)", module: "RecordingCoordinator")
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
        do {
            try modelContext?.save()
        } catch {
            debugLog("Failed to save recording reset state: \(error)", module: "RecordingCoordinator", level: .error)
            debugCaptureError(error, context: "Resetting recording before continuation")
        }

        // Устанавливаем состояние
        currentPreset = preset
        currentRecordingId = recording.id
        isContinuingRecording = true

        // Начинаем новую запись
        let fileURL = try await audioRecorder.startRecording()

        // Запускаем Live Activity с начальным временем = старая длительность
        do {
            try await liveActivityManager.startActivity(
                recordingId: recording.id,
                preset: preset
            )
            await liveActivityManager.updateRecording(
                duration: recording.duration,
                audioLevel: 0
            )
        } catch {
            debugLog("Failed to start Live Activity: \(error)", module: "RecordingCoordinator", level: .error)
            debugCaptureError(error, context: "Starting Live Activity for continuation")
        }

        debugLog("Continuing recording: \(recording.id), original duration: \(recording.duration)s", module: "RecordingCoordinator")
    }

    /// Поставить запись на паузу
    func pauseRecording() {
        if isRealtimeMode {
            realtimeSpeechRecognizer.pauseRecording()
            Task {
                await liveActivityManager.updatePaused(duration: realtimeSpeechRecognizer.recordingDuration)
            }
        } else {
            audioRecorder.pauseRecording()
            Task {
                await liveActivityManager.updatePaused(duration: audioRecorder.recordingDuration)
            }
        }
    }

    /// Возобновить запись
    func resumeRecording() {
        if isRealtimeMode {
            realtimeSpeechRecognizer.resumeRecording()
            Task {
                await liveActivityManager.updateRecording(
                    duration: realtimeSpeechRecognizer.recordingDuration,
                    audioLevel: realtimeSpeechRecognizer.audioLevel
                )
            }
        } else {
            audioRecorder.resumeRecording()
            Task {
                await liveActivityManager.updateRecording(
                    duration: audioRecorder.recordingDuration,
                    audioLevel: audioRecorder.audioLevel
                )
            }
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
                    if continuation.originalAudioURL == data.url {
                        debugLog("Skipping merge: original and new URLs are identical", module: "RecordingCoordinator", level: .error)
                    } else {
                        let mergeResult = try await audioRecorder.mergeAudioFiles(
                            firstURL: continuation.originalAudioURL,
                            secondURL: data.url,
                            deleteSecond: true
                        )
                        finalURL = mergeResult.url
                        finalDuration = mergeResult.duration
                        debugLog("Audio files merged, total duration: \(finalDuration)s", module: "RecordingCoordinator")
                    }
                } catch {
                    debugLog("Failed to merge audio: \(error)", module: "RecordingCoordinator", level: .error)
                    debugCaptureError(error, context: "Merging audio files")
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

                        debugLog("Continued recording stopped, ready for transcription", module: "RecordingCoordinator")
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
            do {
                try modelContext?.save()
            } catch {
                debugLog("Failed to save recording: \(error)", module: "RecordingCoordinator", level: .error)
                debugCaptureError(error, context: "Saving new recording")
            }

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

            debugLog("Recording stopped, ready for transcription", module: "RecordingCoordinator")
            return recording

        case .failure(let error):
            debugLog("Failed to stop recording: \(error)", module: "RecordingCoordinator", level: .error)
            debugCaptureError(error, context: "Stopping recording")

            // Даже при ошибке закрываем Live Activity
            await liveActivityManager.endActivityImmediately()

            continuationData = nil
            isContinuingRecording = false
            currentPreset = nil
            currentRecordingId = nil
            return nil
        }
    }

    // MARK: - Realtime Recording Flow

    /// Начать запись в real-time режиме с локальной диктовкой
    func startRealtimeRecording(preset: RecordingPreset) async throws {
        currentPreset = preset
        currentRecordingId = UUID()
        isRealtimeMode = true

        // Инициализируем менеджер транскрипции
        let manager = RealtimeTranscriptionManager()
        realtimeManager = manager

        // Настраиваем callback для завершения фразы
        // Когда SpeechRecognizer определяет паузу 3 сек — отправляем чанк на сервер
        realtimeSpeechRecognizer.onPhraseCompleted = { [weak manager] url, duration, previewText in
            Task { @MainActor in
                manager?.enqueueChunk(url: url, duration: duration, previewText: previewText)
            }
        }

        // Начинаем запись с локальной диктовкой
        try await realtimeSpeechRecognizer.startRecording()

        // Подписываемся на обновления от SpeechRecognizer (без Live Activity в real-time режиме)
        setupRealtimeSpeechObservers()

        debugLog("Realtime recording started with preset: \(preset.displayName)", module: "RecordingCoordinator")
    }

    /// Настройка обновлений от SpeechRecognizer
    private func setupRealtimeSpeechObservers() {
        // Очищаем старые subscriptions перед добавлением новых
        realtimeCancellables.removeAll()

        // Синхронизируем interimText с менеджером
        realtimeSpeechRecognizer.$interimText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.realtimeManager?.currentInterimText = text
            }
            .store(in: &realtimeCancellables)

        // Пробрасываем обновления от менеджера в координатор для обновления UI
        if let manager = realtimeManager {
            manager.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &realtimeCancellables)
        }
    }

    /// Остановить real-time запись и создать запись
    func stopRealtimeRecording() async -> Recording? {
        guard let preset = currentPreset,
              let recordingId = currentRecordingId,
              let manager = realtimeManager else { return nil }

        // Останавливаем запись и локальную диктовку
        let duration = realtimeSpeechRecognizer.stopRecording()

        // Ждём завершения всех pending транскрипций
        await manager.waitForCompletion()

        // Получаем финальную транскрипцию
        let finalTranscription = manager.getFinalTranscription()

        // Мержим все чанки в один аудиофайл
        let chunkURLs = manager.getProcessedChunkURLs()
        var finalAudioURL = ""

        if !chunkURLs.isEmpty {
            do {
                let mergedURL = try await audioRecorder.mergeMultipleAudioFiles(urls: chunkURLs)
                finalAudioURL = mergedURL.path
                debugLog("Merged \(chunkURLs.count) chunks into: \(mergedURL.lastPathComponent)", module: "RecordingCoordinator")
            } catch {
                debugLog("Failed to merge chunks: \(error)", module: "RecordingCoordinator", level: .error)
                debugCaptureError(error, context: "Merging realtime audio chunks")
            }
        }

        // Fallback: сохранить первый чанк как отдельный файл
        if finalAudioURL.isEmpty, let fallbackChunk = chunkURLs.first {
            if let copiedURL = copyFallbackChunk(from: fallbackChunk) {
                finalAudioURL = copiedURL.path
                debugLog("Using fallback chunk file: \(copiedURL.lastPathComponent)", module: "RecordingCoordinator", level: .warning)
            }
        }

        // Очищаем временные файлы чанков
        manager.cleanupChunks()

        // Если аудиофайл так и не получен — не сохраняем запись
        guard !finalAudioURL.isEmpty else {
            debugLog("Realtime recording finished without audio file, skipping save", module: "RecordingCoordinator", level: .error)
            pendingTranscription = nil
            realtimeSpeechRecognizer.onPhraseCompleted = nil
            realtimeCancellables.removeAll()
            isRealtimeMode = false
            currentPreset = nil
            currentRecordingId = nil
            return nil
        }

        // Создаём запись с audioFileURL (теперь содержит путь к merged файлу)
        let recording = Recording(
            id: recordingId,
            title: "\(preset.displayName) \(formatDate(Date()))",
            duration: duration,
            audioFileURL: finalAudioURL,
            transcriptionText: finalTranscription,
            preset: preset
        )
        recording.isTranscribed = !finalTranscription.isEmpty

        modelContext?.insert(recording)
        try? modelContext?.save()

        // Сохраняем pending для саммаризации
        if !finalTranscription.isEmpty {
            pendingTranscription = PendingTranscription(
                recordingId: recordingId,
                audioURL: URL(fileURLWithPath: finalAudioURL),
                duration: duration,
                preset: preset
            )
        }

        // Очищаем состояние
        realtimeSpeechRecognizer.onPhraseCompleted = nil
        realtimeCancellables.removeAll()  // Очищаем realtime subscriptions
        isRealtimeMode = false
        currentPreset = nil
        currentRecordingId = nil

        debugLog("Realtime recording stopped, paragraphs: \(manager.completedParagraphsCount), audioFile: \(finalAudioURL.isEmpty ? "none" : "saved")", module: "RecordingCoordinator")

        return recording
    }

    private func copyFallbackChunk(from chunkURL: URL) -> URL? {
        let ext = chunkURL.pathExtension.isEmpty ? "m4a" : chunkURL.pathExtension
        let fallbackURL = audioRecorder.recordingsDirectory
            .appendingPathComponent("realtime_fallback_\(Date().timeIntervalSince1970).\(ext)")
        do {
            try FileManager.default.copyItem(at: chunkURL, to: fallbackURL)
            return fallbackURL
        } catch {
            debugLog("Failed to copy fallback chunk: \(error)", module: "RecordingCoordinator", level: .error)
            debugCaptureError(error, context: "Copying fallback chunk")
            return nil
        }
    }

    /// Начать саммаризацию для real-time записи
    func startRealtimeSummarization() async {
        guard let pending = pendingTranscription,
              let manager = realtimeManager else { return }

        isTranscribing = true

        do {
            let service = TranscriptionService()
            let transcriptionText = manager.getFinalTranscription()

            guard !transcriptionText.isEmpty else {
                debugLog("No transcription text to summarize", module: "RecordingCoordinator", level: .warning)
                isTranscribing = false
                realtimeManager = nil
                pendingTranscription = nil
                return
            }

            // Генерируем саммари из накопленной транскрипции
            let (summary, title) = try await service.summarize(
                text: transcriptionText,
                preset: pending.preset
            )

            // Обновляем запись
            await updateRecording(
                id: pending.recordingId,
                transcription: transcriptionText,
                summary: summary,
                title: title
            )

            realtimeManager = nil
            pendingTranscription = nil
            isTranscribing = false

            debugLog("Realtime summarization completed", module: "RecordingCoordinator")

        } catch {
            debugLog("Realtime summarization failed: \(error)", module: "RecordingCoordinator", level: .error)
            debugCaptureError(error, context: "Realtime summarization")
            realtimeManager = nil
            pendingTranscription = nil
            isTranscribing = false
        }
    }

    // MARK: - Transcription Flow

    /// Начать транскрипцию pending записи
    func startTranscription() async {
        if transcriptionTask != nil {
            debugLog("Transcription already in progress", module: "RecordingCoordinator", level: .info)
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runTranscription()
        }
        transcriptionTask = task
        await task.value
        transcriptionTask = nil
    }

    /// Отменить текущую транскрипцию
    func cancelTranscription() async {
        if let pending = pendingTranscription {
            updateRecordingUploadingState(recordingId: pending.recordingId, isUploading: false)
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        pendingTranscription = nil
        isTranscribing = false
        await liveActivityManager.endActivityImmediately()
        debugLog("Transcription cancelled", module: "RecordingCoordinator")
    }

    private func runTranscription() async {
        debugLog("startTranscription called", module: "RecordingCoordinator")

        // Если pendingTranscription nil — пробуем восстановить из Live Activity и БД
        if pendingTranscription == nil {
            if let recovered = tryRecoverPendingTranscription() {
                pendingTranscription = recovered
                debugLog("Recovered pendingTranscription from Live Activity: \(recovered.recordingId)", module: "RecordingCoordinator")
            }
        }

        guard let pending = pendingTranscription else {
            debugLog("No pending transcription - pendingTranscription is nil and recovery failed!", module: "RecordingCoordinator", level: .warning)
            return
        }

        updateRecordingUploadingState(recordingId: pending.recordingId, isUploading: true)

        debugLog("Starting transcription for recording: \(pending.recordingId)", module: "RecordingCoordinator")
        debugLog("Audio URL: \(pending.audioURL)", module: "RecordingCoordinator")

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
            defer {
                progressTask.cancel()
            }

            let result = try await service.transcribe(
                audioFileURL: pending.audioURL,
                preset: pending.preset
            )

            try Task.checkCancellation()

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

            debugLog("Transcription completed successfully", module: "RecordingCoordinator")

        } catch is CancellationError {
            debugLog("Transcription cancelled", module: "RecordingCoordinator", level: .warning)
            await liveActivityManager.endActivityImmediately()
            updateRecordingUploadingState(recordingId: pending.recordingId, isUploading: false)
            pendingTranscription = nil
            isTranscribing = false
        } catch {
            debugLog("Transcription failed: \(error)", module: "RecordingCoordinator", level: .error)
            debugCaptureError(error, context: "Transcription")
            // Завершаем Live Activity с ошибкой
            await liveActivityManager.endActivityImmediately()
            updateRecordingUploadingState(recordingId: pending.recordingId, isUploading: false)
            pendingTranscription = nil
            isTranscribing = false
        }
    }

    /// Отменить pending транскрипцию и закрыть Live Activity
    func cancelPendingTranscription() async {
        if let pending = pendingTranscription {
            updateRecordingUploadingState(recordingId: pending.recordingId, isUploading: false)
        }
        pendingTranscription = nil
        await liveActivityManager.endActivityImmediately()
    }

    /// Восстановить pendingTranscription из Live Activity и базы данных
    /// Используется когда приложение было перезапущено, но Live Activity ещё активна
    private func tryRecoverPendingTranscription() -> PendingTranscription? {
        // Получаем текущую Live Activity
        guard let activity = liveActivityManager.currentActivity else {
            debugLog("Cannot recover: no Live Activity found", module: "RecordingCoordinator", level: .warning)
            return nil
        }

        let recordingId = activity.attributes.recordingId
        debugLog("Attempting to recover pendingTranscription, recordingId: \(recordingId)", module: "RecordingCoordinator")

        // Ищем запись в базе данных
        guard let context = modelContext else {
            debugLog("Cannot recover: no modelContext", module: "RecordingCoordinator", level: .warning)
            return nil
        }

        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.id == recordingId }
        )

        do {
            let recordings = try context.fetch(descriptor)
            if let recording = recordings.first,
               let preset = recording.preset {
                let url = URL(fileURLWithPath: recording.audioFileURL)
                debugLog("Successfully recovered recording: \(recording.title)", module: "RecordingCoordinator")
                return PendingTranscription(
                    recordingId: recording.id,
                    audioURL: url,
                    duration: recording.duration,
                    preset: preset
                )
            } else {
                debugLog("Recording not found or has no preset", module: "RecordingCoordinator", level: .warning)
            }
        } catch {
            debugLog("Failed to fetch recording: \(error)", module: "RecordingCoordinator", level: .error)
            debugCaptureError(error, context: "Recovering pending transcription")
        }

        return nil
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
            debugLog("Failed to update recording: \(error)", module: "RecordingCoordinator", level: .error)
            debugCaptureError(error, context: "Updating recording in database")
        }
    }

    private func updateRecordingUploadingState(recordingId: UUID, isUploading: Bool) {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.id == recordingId }
        )

        do {
            let recordings = try context.fetch(descriptor)
            if let recording = recordings.first {
                recording.isUploading = isUploading
                if !isUploading {
                    recording.isSummaryGenerating = false
                }
                try context.save()
            }
        } catch {
            debugLog("Failed to update upload state: \(error)", module: "RecordingCoordinator", level: .error)
            debugCaptureError(error, context: "Updating recording upload state")
        }
    }

    private func setupNotificationObservers() {
        // From Shortcut - start recording (внутренний notification, работает в одном процессе)
        NotificationCenter.default.publisher(for: .startRecordingFromShortcut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let presetId = notification.userInfo?["presetId"] as? String,
                      let preset = RecordingPreset(rawValue: presetId) else { return }

                Task { @MainActor in
                    try? await self?.startRecording(preset: preset)
                }
            }
            .store(in: &cancellables)

        // Darwin notifications для Live Activity (межпроцессная коммуникация)
        setupDarwinNotificationObservers()
    }

    /// Настройка Darwin notifications для получения команд из Widget Extension
    private func setupDarwinNotificationObservers() {
        DarwinNotificationCenter.shared.startObserving(
            onPause: { [weak self] in
                self?.pauseRecording()
            },
            onResume: { [weak self] in
                self?.resumeRecording()
            },
            onStop: { [weak self] in
                Task { @MainActor in
                    _ = await self?.stopRecording()
                }
            },
            onStartTranscription: { [weak self] in
                debugLog("Received Darwin notification: startTranscription", module: "RecordingCoordinator")
                Task { @MainActor in
                    await self?.startTranscription()
                }
            },
            onDismiss: { [weak self] in
                Task { @MainActor in
                    await self?.dismissActivity()
                }
            },
            onHide: { [weak self] in
                Task { @MainActor in
                    await self?.hideActivity()
                }
            }
        )
    }

    /// Закрыть Live Activity без транскрипции
    func dismissActivity() async {
        pendingTranscription = nil
        await liveActivityManager.endActivityImmediately()
        debugLog("Activity dismissed without transcription", module: "RecordingCoordinator")
    }

    /// Скрыть Live Activity (во время транскрипции продолжает работать в фоне)
    func hideActivity() async {
        await liveActivityManager.endActivityImmediately()
        debugLog("Activity hidden, transcription continues in background", module: "RecordingCoordinator")
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
            debugLog("Ignoring stale pending preset (age: \(Int(age))s)", module: "RecordingCoordinator")
            return
        }

        guard let preset = RecordingPreset(rawValue: presetId) else {
            debugLog("Invalid preset id from shortcut: \(presetId)", module: "RecordingCoordinator", level: .warning)
            return
        }

        // Начинаем запись
        debugLog("Starting recording from shortcut (age: \(Int(age))s)", module: "RecordingCoordinator")
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
