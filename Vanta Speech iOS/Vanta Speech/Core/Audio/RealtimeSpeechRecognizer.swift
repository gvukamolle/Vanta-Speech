import AVFoundation
import Speech
import Combine
import UIKit

/// Распознаватель речи в реальном времени с локальной диктовкой
/// Использует SFSpeechRecognizer для предпревью и определения пауз
@MainActor
final class RealtimeSpeechRecognizer: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// Текущий промежуточный текст от локальной диктовки
    @Published private(set) var interimText: String = ""

    /// Идет ли запись
    @Published private(set) var isRecording = false

    /// Уровень аудио для визуализации
    @Published private(set) var audioLevel: Float = 0

    /// Общая длительность записи
    @Published private(set) var recordingDuration: TimeInterval = 0

    /// Приостановлена ли запись
    @Published private(set) var isInterrupted = false

    // MARK: - Callbacks

    /// Вызывается когда фраза завершена (пауза в речи)
    /// Параметры: URL аудиофайла, длительность, предварительный текст диктовки
    var onPhraseCompleted: ((URL, TimeInterval, String) -> Void)?

    // MARK: - Private Properties

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var audioFile: AVAudioFile?
    private var currentChunkURL: URL?
    private var chunkIndex = 0

    private var startTime: Date?
    private var phraseStartTime: Date?
    private var lastSpeechTime: Date?
    private var currentPhraseText: String = ""

    private var pauseTimer: Timer?
    private var metricsTimer: Timer?

    private let fileManager = FileManager.default

    /// Длительность паузы для завершения фразы (секунды)
    /// Настраивается через UserDefaults с ключом "realtime_pauseThreshold"
    private var pauseThreshold: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "realtime_pauseThreshold")
        return value > 0 ? value : 3.0  // Default 3.0 секунды
    }

    /// Минимальное количество слов для отправки фразы
    /// Защита от галлюцинаций Whisper на коротких аудио
    private var minimumWordCount: Int {
        let value = UserDefaults.standard.integer(forKey: "realtime_minWordCount")
        return value > 0 ? value : 10
    }

    // MARK: - Directories

    var recordingsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        if !fileManager.fileExists(atPath: recordingsPath.path) {
            try? fileManager.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        }
        return recordingsPath
    }

    var chunksDirectory: URL {
        let chunksPath = recordingsDirectory.appendingPathComponent("Chunks", isDirectory: true)
        if !fileManager.fileExists(atPath: chunksPath.path) {
            try? fileManager.createDirectory(at: chunksPath, withIntermediateDirectories: true)
        }
        return chunksPath
    }

    // MARK: - Init

    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        super.init()
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        // Request microphone permission
        let micPermission = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard micPermission else { return false }

        // Request speech recognition permission
        let speechPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        return speechPermission
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        guard await requestPermissions() else {
            throw SpeechRecognizerError.permissionDenied
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognizerError.recognizerUnavailable
        }

        // Очищаем старые чанки
        clearChunksDirectory()

        // Configure audio session
        try configureAudioSession()

        // Reset state
        chunkIndex = 0
        interimText = ""
        currentPhraseText = ""
        recordingDuration = 0
        isInterrupted = false

        // Start new phrase
        try startNewPhrase()

        isRecording = true
        startTime = Date()
        startMetricsTimer()

        // Запрещаем гашение экрана во время записи
        UIApplication.shared.isIdleTimerDisabled = true

        debugLog("Realtime config: pauseThreshold=\(String(format: "%.2f", pauseThreshold))s, minWordCount=\(minimumWordCount)", module: "RealtimeSpeechRecognizer")
        debugLog("Recording started", module: "RealtimeSpeechRecognizer")
    }

    func stopRecording() -> TimeInterval {
        let duration = recordingDuration

        // Останавливаем все
        pauseTimer?.invalidate()
        pauseTimer = nil
        metricsTimer?.invalidate()
        metricsTimer = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Закрываем файл перед финализацией, чтобы корректно записалась длительность/размер
        audioFile = nil

        // Финализируем текущую фразу если есть
        if let _ = currentChunkURL,
           let phraseStart = phraseStartTime {
            let phraseDuration = Date().timeIntervalSince(phraseStart)
            finishCurrentPhrase(duration: phraseDuration, allowEmptyText: true)
        }

        currentChunkURL = nil

        deactivateAudioSession()

        isRecording = false
        interimText = ""
        currentPhraseText = ""
        recordingDuration = 0
        startTime = nil

        // Разрешаем гашение экрана после остановки записи
        UIApplication.shared.isIdleTimerDisabled = false

        debugLog("Recording stopped, duration: \(duration)s", module: "RealtimeSpeechRecognizer")

        return duration
    }

    func pauseRecording() {
        guard isRecording, !isInterrupted else { return }

        audioEngine.pause()
        pauseTimer?.invalidate()
        metricsTimer?.invalidate()
        isInterrupted = true

        debugLog("Recording paused", module: "RealtimeSpeechRecognizer")
    }

    func resumeRecording() {
        guard isRecording, isInterrupted else { return }

        try? audioEngine.start()
        startMetricsTimer()
        resetPauseTimer()
        isInterrupted = false

        debugLog("Recording resumed", module: "RealtimeSpeechRecognizer")
    }

    // MARK: - Private Methods

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startNewPhrase() throws {
        // Создаём новый файл для чанка
        let chunkURL = chunksDirectory.appendingPathComponent("chunk_\(chunkIndex)_\(Date().timeIntervalSince1970).wav")
        chunkIndex += 1
        currentChunkURL = chunkURL

        // Настраиваем запись в файл
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        audioFile = try AVAudioFile(forWriting: chunkURL, settings: recordingFormat.settings)

        // Создаём новый recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        // Запускаем recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }

        // Убираем старый tap если есть
        inputNode.removeTap(onBus: 0)

        // Устанавливаем tap на входной узел
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            // Пишем в файл
            try? self?.audioFile?.write(from: buffer)

            // Отправляем в распознаватель
            self?.recognitionRequest?.append(buffer)

            // Обновляем уровень звука
            DispatchQueue.main.async {
                self?.updateAudioLevel(buffer: buffer)
            }
        }

        // Запускаем audio engine
        audioEngine.prepare()
        try audioEngine.start()

        phraseStartTime = Date()
        lastSpeechTime = Date()
        currentPhraseText = ""

        resetPauseTimer()

        debugLog("New phrase started: \(chunkURL.lastPathComponent)", module: "RealtimeSpeechRecognizer")
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        guard let result = result else {
            if let error = error {
                debugLog("Recognition error: \(error)", module: "RealtimeSpeechRecognizer", level: .error)
                debugCaptureError(error, context: "Speech recognition")
            }
            return
        }

        let text = result.bestTranscription.formattedString
        currentPhraseText = text
        interimText = text

        // Обновляем время последней речи
        lastSpeechTime = Date()
        resetPauseTimer()

        // Если это финальный результат, можно что-то сделать
        if result.isFinal {
            debugLog("Final result: \(text)", module: "RealtimeSpeechRecognizer")
        }
    }

    private func resetPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseThreshold, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handlePauseTimeout()
            }
        }
    }

    private func handlePauseTimeout() {
        // Пауза — проверяем условия для завершения фразы
        guard isRecording,
              !isInterrupted,
              let phraseStart = phraseStartTime,
              !currentPhraseText.isEmpty else {
            // Если текста нет, просто продолжаем ждать
            resetPauseTimer()
            return
        }

        // Проверяем минимальное количество слов (защита от галлюцинаций Whisper)
        let wordCount = currentPhraseText.split(separator: " ").count
        if wordCount < minimumWordCount {
            // Слов недостаточно — продолжаем ждать
            debugLog("Word count \(wordCount) < \(minimumWordCount), waiting for more speech...", module: "RealtimeSpeechRecognizer")
            resetPauseTimer()
            return
        }

        let phraseDuration = Date().timeIntervalSince(phraseStart)
        finishCurrentPhrase(duration: phraseDuration)

        // Начинаем новую фразу
        do {
            // Останавливаем текущий recognition
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest?.endAudio()
            recognitionRequest = nil

            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            audioFile = nil

            // Небольшая задержка перед новой фразой
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if self.isRecording && !self.isInterrupted {
                    try? self.startNewPhrase()
                }
            }
        }
    }

    private func finishCurrentPhrase(duration: TimeInterval, allowEmptyText: Bool = false) {
        guard let chunkURL = currentChunkURL else { return }

        let text = currentPhraseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileSizeBytes = (try? fileManager.attributesOfItem(atPath: chunkURL.path)[.size] as? NSNumber)?.intValue ?? 0

        if !text.isEmpty || allowEmptyText {
            if text.isEmpty && allowEmptyText {
                // Проверяем что файл не пустой
                if fileSizeBytes == 0 {
                    try? fileManager.removeItem(at: chunkURL)
                    currentPhraseText = ""
                    interimText = ""
                    currentChunkURL = nil
                    debugLog("Dropping empty chunk: \(chunkURL.lastPathComponent)", module: "RealtimeSpeechRecognizer", level: .warning)
                    return
                }
            }
            let fileSizeKB = Double(fileSizeBytes) / 1024.0
            debugLog("Phrase completed: '\(text.prefix(50))...', duration: \(String(format: "%.2f", duration))s, size: \(String(format: "%.1f", fileSizeKB)) KB", module: "RealtimeSpeechRecognizer")
            onPhraseCompleted?(chunkURL, duration, text)
        } else {
            // Удаляем пустой чанк
            try? fileManager.removeItem(at: chunkURL)
        }

        currentPhraseText = ""
        interimText = ""
        currentChunkURL = nil
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }
        let average = sum / Float(frameLength)

        // Нормализуем в диапазон 0-1
        let level = min(1.0, average * 10)
        audioLevel = level
    }

    private func startMetricsTimer() {
        metricsTimer?.invalidate()
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, let startTime = self.startTime, !self.isInterrupted else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
        if let timer = metricsTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func clearChunksDirectory() {
        let chunksDir = chunksDirectory
        if let contents = try? fileManager.contentsOfDirectory(at: chunksDir, includingPropertiesForKeys: nil) {
            for file in contents {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

// MARK: - Errors

enum SpeechRecognizerError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Требуется разрешение на микрофон и распознавание речи."
        case .recognizerUnavailable:
            return "Распознаватель речи недоступен."
        case .recordingFailed:
            return "Не удалось начать запись."
        }
    }
}
