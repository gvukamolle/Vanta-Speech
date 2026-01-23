import AVFoundation
import Combine
import Foundation
import UIKit

/// Audio recorder with background recording support
/// Continues recording when app is backgrounded or screen is locked
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isConverting = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var isInterrupted = false

    // MARK: - Realtime Mode Properties

    @Published var isRealtimeMode = false

    /// Callback вызывается когда чанк готов для транскрипции
    var onChunkReady: ((URL, TimeInterval) -> Void)?

    /// Конфигурация VAD (Voice Activity Detection)
    var vadConfig: VADConfig {
        VADConfig(
            silenceThreshold: UserDefaults.standard.float(forKey: "vad_silenceThreshold").nonZeroOr(0.08),
            silenceDurationThreshold: UserDefaults.standard.double(forKey: "vad_silenceDuration").nonZeroOr(1.5),
            minimumChunkDuration: UserDefaults.standard.double(forKey: "vad_minChunkDuration").nonZeroOr(10.0),
            maximumChunkDuration: UserDefaults.standard.double(forKey: "vad_maxChunkDuration").nonZeroOr(60.0)
        )
    }

    private var silenceDuration: TimeInterval = 0
    private var currentChunkDuration: TimeInterval = 0
    private var chunkIndex = 0
    private var currentChunkURL: URL?
    private var chunkStartTime: Date?
    private var isFinalizingChunk = false

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    private var pausedDuration: TimeInterval = 0

    private let fileManager = FileManager.default

    /// Converter with quality from user settings
    private var converter: AudioConverter {
        let qualityRaw = UserDefaults.standard.string(forKey: "audioQuality") ?? AudioQuality.low.rawValue
        let quality = AudioQuality(rawValue: qualityRaw) ?? .low
        return AudioConverter(quality: quality)
    }

    // MARK: - Lifecycle

    override init() {
        super.init()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Directory

    var recordingsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)

        if !fileManager.fileExists(atPath: recordingsPath.path) {
            try? fileManager.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        }

        return recordingsPath
    }

    // MARK: - Audio Session Setup

    /// Configure audio session for background recording
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        // Category: playAndRecord allows both recording and playback
        // Mode: spokenAudio optimized for voice/speech recording
        // Options:
        //   - defaultToSpeaker: use speaker for playback
        //   - allowBluetooth: support Bluetooth headsets
        //   - mixWithOthers: don't interrupt other audio (optional)
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )

        // Activate the session
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Deactivate audio session when recording stops
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            debugLog("Failed to deactivate audio session: \(error)", module: "AudioRecorder", level: .error)
        }
    }

    // MARK: - Notifications for Background/Interruptions

    private func setupNotifications() {
        let nc = NotificationCenter.default

        // Audio interruption (phone calls, Siri, etc.)
        nc.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Route change (headphones plugged/unplugged)
        nc.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )

        // App lifecycle
        nc.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        Task { @MainActor in
            switch type {
            case .began:
                // Interruption started (phone call, other app using mic, etc.)
                if isRecording {
                    audioRecorder?.pause()
                    if let startTime = startTime {
                        pausedDuration = Date().timeIntervalSince(startTime)
                    }
                    stopTimer()
                    isInterrupted = true
                    debugLog("Interruption began - recording paused", module: "AudioRecorder")
                }

            case .ended:
                // Interruption ended - don't auto-resume, let user decide
                // User can tap "Continue" button in UI
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        // Re-activate audio session
                        do {
                            try AVAudioSession.sharedInstance().setActive(true)
                            debugLog("Interruption ended - session reactivated, waiting for user to resume", module: "AudioRecorder")
                        } catch {
                            debugLog("Failed to reactivate session: \(error)", module: "AudioRecorder", level: .error)
                        }
                    }
                }

            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - continue recording via built-in mic
            debugLog("Audio route changed: old device unavailable", module: "AudioRecorder")
        case .newDeviceAvailable:
            // New device connected
            debugLog("Audio route changed: new device available", module: "AudioRecorder")
        default:
            break
        }
    }

    @objc private func handleAppWillResignActive() {
        // App going to background
        // Recording continues, but stop UI timer to save battery
        if isRecording {
            // Save current duration before stopping timer
            if let startTime = startTime {
                pausedDuration = Date().timeIntervalSince(startTime)
            }
            stopTimer()
            debugLog("App backgrounded - timer stopped, recording continues", module: "AudioRecorder")
        }
    }

    @objc private func handleAppDidBecomeActive() {
        // App returned to foreground
        if isRecording {
            // Restart UI timer
            startTimer()
            // Duration is calculated from startTime, so it's accurate
            debugLog("App foregrounded - timer restarted", module: "AudioRecorder")
        }
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording Control

    func startRecording() async throws -> URL {
        guard await requestPermission() else {
            throw AudioRecorderError.permissionDenied
        }

        // Configure session for background recording
        try configureAudioSession()

        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let fileURL = recordingsDirectory.appendingPathComponent(fileName)

        // Audio settings optimized for voice/meetings
        // 64kbps AAC mono — хороший баланс качества и размера для голоса
        // ~28 MB на 1 час записи
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,  // 64 kbps
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.delegate = self
        audioRecorder?.record()

        isRecording = true
        isInterrupted = false
        startTime = Date()
        pausedDuration = 0
        startTimer()

        debugLog("Recording started: \(fileURL.lastPathComponent)", module: "AudioRecorder")

        return fileURL
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let recorder = audioRecorder, isRecording else {
            debugLog("stopRecording guard failed: audioRecorder=\(audioRecorder != nil), isRecording=\(isRecording)", module: "AudioRecorder", level: .warning)
            return nil
        }

        let url = recorder.url
        let duration = recordingDuration

        recorder.stop()
        stopTimer()
        deactivateAudioSession()

        isRecording = false
        isInterrupted = false
        recordingDuration = 0
        audioRecorder = nil
        startTime = nil
        pausedDuration = 0

        debugLog("Recording stopped: \(url.lastPathComponent), duration: \(duration)s", module: "AudioRecorder")

        return (url, duration)
    }

    /// Stop recording and convert to OGG format
    func stopRecordingAndConvert() async -> Result<(url: URL, duration: TimeInterval), Error> {
        guard let result = stopRecording() else {
            return .failure(AudioRecorderError.recordingFailed)
        }

        isConverting = true
        defer { isConverting = false }

        do {
            let oggURL = try await converter.convertToOGG(
                inputURL: result.url,
                deleteSource: true
            )
            return .success((oggURL, result.duration))
        } catch {
            debugLog("OGG conversion failed: \(error.localizedDescription). Using M4A.", module: "AudioRecorder", level: .warning)
            return .success(result)
        }
    }

    /// Stop recording with optional OGG conversion
    func stopRecording(convertToOGG: Bool) async -> Result<(url: URL, duration: TimeInterval), Error> {
        if convertToOGG {
            return await stopRecordingAndConvert()
        } else {
            guard let result = stopRecording() else {
                return .failure(AudioRecorderError.recordingFailed)
            }
            return .success(result)
        }
    }

    func pauseRecording() {
        audioRecorder?.pause()
        if let startTime = startTime {
            pausedDuration = Date().timeIntervalSince(startTime)
        }
        stopTimer()
        isInterrupted = true
        debugLog("Recording paused", module: "AudioRecorder")
    }

    func resumeRecording() {
        // Re-activate audio session first
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            debugLog("Failed to reactivate session: \(error)", module: "AudioRecorder", level: .error)
        }

        audioRecorder?.record()
        // Adjust startTime to account for pause
        if pausedDuration > 0 {
            startTime = Date().addingTimeInterval(-pausedDuration)
        }
        isInterrupted = false
        startTimer()
        debugLog("Recording resumed", module: "AudioRecorder")
    }

    // MARK: - Realtime Recording

    /// Директория для временных чанков
    var chunksDirectory: URL {
        let chunksPath = recordingsDirectory.appendingPathComponent("Chunks", isDirectory: true)
        if !fileManager.fileExists(atPath: chunksPath.path) {
            try? fileManager.createDirectory(at: chunksPath, withIntermediateDirectories: true)
        }
        return chunksPath
    }

    /// Начать запись в real-time режиме с VAD
    func startRealtimeRecording() async throws -> URL {
        guard await requestPermission() else {
            throw AudioRecorderError.permissionDenied
        }

        // Configure session for recording
        try configureAudioSession()

        // Очищаем старые чанки
        clearChunksDirectory()

        // Reset realtime state
        isRealtimeMode = true
        chunkIndex = 0
        silenceDuration = 0
        currentChunkDuration = 0
        isFinalizingChunk = false

        // Создаём первый чанк
        let chunkURL = try createNewChunkFile()
        currentChunkURL = chunkURL

        // Audio settings (same as regular recording)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: chunkURL, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.delegate = self
        audioRecorder?.record()

        isRecording = true
        isInterrupted = false
        startTime = Date()
        chunkStartTime = Date()
        pausedDuration = 0
        startTimer()

        debugLog("Realtime recording started: \(chunkURL.lastPathComponent)", module: "AudioRecorder")

        return chunkURL
    }

    /// Остановить real-time запись
    func stopRealtimeRecording() -> (finalChunkURL: URL?, totalDuration: TimeInterval) {
        guard isRecording, isRealtimeMode else {
            return (nil, 0)
        }

        let totalDuration = recordingDuration

        // Сохраняем URL последнего чанка до reset
        var finalChunk: URL? = nil

        // Финализируем последний чанк если он достаточно длинный
        if let chunkURL = currentChunkURL, currentChunkDuration >= 2.0 {
            audioRecorder?.stop()
            finalChunk = chunkURL
            debugLog("Final chunk saved: \(chunkURL.lastPathComponent), duration: \(currentChunkDuration)s", module: "AudioRecorder")
            onChunkReady?(chunkURL, currentChunkDuration)
        } else {
            audioRecorder?.stop()
            // Удаляем слишком короткий последний чанк
            if let chunkURL = currentChunkURL {
                try? fileManager.removeItem(at: chunkURL)
            }
        }

        stopTimer()
        deactivateAudioSession()

        // Reset state
        isRecording = false
        isRealtimeMode = false
        isInterrupted = false
        recordingDuration = 0
        audioRecorder = nil
        startTime = nil
        currentChunkURL = nil
        chunkStartTime = nil
        silenceDuration = 0
        currentChunkDuration = 0

        debugLog("Realtime recording stopped, total duration: \(totalDuration)s", module: "AudioRecorder")

        return (finalChunk, totalDuration)
    }

    /// Создать новый файл для чанка
    private func createNewChunkFile() throws -> URL {
        let fileName = "chunk_\(chunkIndex)_\(Date().timeIntervalSince1970).m4a"
        chunkIndex += 1
        return chunksDirectory.appendingPathComponent(fileName)
    }

    /// Финализировать текущий чанк и начать новый
    private func finalizeCurrentChunk() {
        guard isRealtimeMode,
              !isFinalizingChunk,
              let chunkURL = currentChunkURL,
              currentChunkDuration >= vadConfig.minimumChunkDuration else {
            return
        }

        isFinalizingChunk = true

        // Останавливаем текущую запись
        audioRecorder?.stop()

        let chunkDuration = currentChunkDuration
        debugLog("Chunk finalized: \(chunkURL.lastPathComponent), duration: \(chunkDuration)s", module: "AudioRecorder")

        // Уведомляем о готовности чанка
        onChunkReady?(chunkURL, chunkDuration)

        // Начинаем новый чанк
        do {
            let newChunkURL = try createNewChunkFile()
            currentChunkURL = newChunkURL

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: newChunkURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.delegate = self
            audioRecorder?.record()

            chunkStartTime = Date()
            currentChunkDuration = 0
            silenceDuration = 0

            debugLog("New chunk started: \(newChunkURL.lastPathComponent)", module: "AudioRecorder")
        } catch {
            debugLog("Failed to start new chunk: \(error)", module: "AudioRecorder", level: .error)
            debugCaptureError(error, context: "Starting new audio chunk")
        }

        isFinalizingChunk = false
    }

    /// Очистить директорию чанков
    func clearChunksDirectory() {
        let chunksDir = chunksDirectory
        if let contents = try? fileManager.contentsOfDirectory(at: chunksDir, includingPropertiesForKeys: nil) {
            for file in contents {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isRealtimeMode {
                    self.updateMetricsWithVAD()
                } else {
                    self.updateMetrics()
                }
            }
        }
        // Keep timer running in common run loop mode for scrolling compatibility
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMetrics() {
        guard let startTime = startTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)

        audioRecorder?.updateMeters()
        if let power = audioRecorder?.averagePower(forChannel: 0) {
            let normalizedPower = max(0, (power + 60) / 60)
            audioLevel = normalizedPower
        }
    }

    /// Обновление метрик с VAD логикой для real-time режима
    private func updateMetricsWithVAD() {
        guard let startTime = startTime, !isInterrupted else { return }
        recordingDuration = Date().timeIntervalSince(startTime)

        // Обновляем длительность чанка на основе реального времени
        if let chunkStart = chunkStartTime {
            currentChunkDuration = Date().timeIntervalSince(chunkStart)
        }

        audioRecorder?.updateMeters()
        guard let power = audioRecorder?.averagePower(forChannel: 0) else { return }

        let normalizedPower = max(0, (power + 60) / 60)
        audioLevel = normalizedPower

        let config = vadConfig

        // VAD логика
        if normalizedPower < config.silenceThreshold {
            // Тишина - увеличиваем счётчик
            silenceDuration += 0.1

            // Проверяем условия для завершения чанка:
            // достаточно тишины И достигнута минимальная длина чанка
            if silenceDuration >= config.silenceDurationThreshold,
               currentChunkDuration >= config.minimumChunkDuration {
                finalizeCurrentChunk()
            }
        } else {
            // Речь - сбрасываем счётчик тишины
            silenceDuration = 0
        }

        // Принудительная отсечка по максимальной длине
        if currentChunkDuration >= config.maximumChunkDuration {
            finalizeCurrentChunk()
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                isRecording = false
                debugLog("Recording finished unsuccessfully", module: "AudioRecorder", level: .error)
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            isRecording = false
            if let error = error {
                debugLog("Encoding error: \(error.localizedDescription)", module: "AudioRecorder", level: .error)
                debugCaptureError(error, context: "Audio encoding")
            }
        }
    }
}

// MARK: - Audio Merging

extension AudioRecorder {
    /// Склеивает два аудиофайла в один
    /// - Parameters:
    ///   - firstURL: URL первого аудиофайла
    ///   - secondURL: URL второго аудиофайла (нового)
    ///   - deleteSecond: Удалить ли второй файл после склейки
    /// - Returns: URL склеенного файла (перезаписывает первый)
    func mergeAudioFiles(firstURL: URL, secondURL: URL, deleteSecond: Bool = true) async throws -> (url: URL, duration: TimeInterval) {
        let composition = AVMutableComposition()

        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioRecorderError.mergeFailed
        }

        // Загружаем первый файл
        let firstAsset = AVURLAsset(url: firstURL)
        let firstTracks = try await firstAsset.loadTracks(withMediaType: .audio)
        guard let firstTrack = firstTracks.first else {
            throw AudioRecorderError.mergeFailed
        }
        let firstDuration = try await firstAsset.load(.duration)

        // Вставляем первый трек
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: firstDuration),
            of: firstTrack,
            at: .zero
        )

        // Загружаем второй файл
        let secondAsset = AVURLAsset(url: secondURL)
        let secondTracks = try await secondAsset.loadTracks(withMediaType: .audio)
        guard let secondTrack = secondTracks.first else {
            throw AudioRecorderError.mergeFailed
        }
        let secondDuration = try await secondAsset.load(.duration)

        // Вставляем второй трек после первого
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: secondDuration),
            of: secondTrack,
            at: firstDuration
        )

        // Создаём временный файл для экспорта
        let tempURL = recordingsDirectory.appendingPathComponent("temp_merged_\(Date().timeIntervalSince1970).m4a")

        // Экспортируем
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioRecorderError.mergeFailed
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                debugLog("Export failed: \(error)", module: "AudioRecorder", level: .error)
            }
            throw AudioRecorderError.mergeFailed
        }

        // Удаляем оригинальный первый файл и переименовываем temp в него
        try? fileManager.removeItem(at: firstURL)
        try fileManager.moveItem(at: tempURL, to: firstURL)

        // Удаляем второй файл если нужно
        if deleteSecond {
            try? fileManager.removeItem(at: secondURL)
        }

        // Вычисляем общую длительность
        let totalDuration = CMTimeGetSeconds(firstDuration) + CMTimeGetSeconds(secondDuration)

        debugLog("Merged audio files, total duration: \(totalDuration)s", module: "AudioRecorder")

        return (firstURL, totalDuration)
    }

    /// Склеивает множество аудиофайлов в один
    /// Оптимизировано для мержа чанков real-time записи
    /// - Parameter urls: Массив URL аудиофайлов в порядке склейки
    /// - Returns: URL результирующего файла
    func mergeMultipleAudioFiles(urls: [URL]) async throws -> URL {
        guard !urls.isEmpty else {
            throw AudioRecorderError.mergeFailed
        }

        // Если один файл - просто возвращаем его
        if urls.count == 1 {
            return urls[0]
        }

        let composition = AVMutableComposition()

        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioRecorderError.mergeFailed
        }

        var currentTime = CMTime.zero

        // Добавляем все треки последовательно
        for (index, url) in urls.enumerated() {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)

            guard let track = tracks.first else {
                debugLog("No audio track in file \(index): \(url.lastPathComponent)", module: "AudioRecorder", level: .warning)
                continue
            }

            let duration = try await asset.load(.duration)

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: track,
                at: currentTime
            )

            currentTime = CMTimeAdd(currentTime, duration)
        }

        // Создаём файл для результата
        let outputURL = recordingsDirectory.appendingPathComponent("merged_\(Date().timeIntervalSince1970).m4a")

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioRecorderError.mergeFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                debugLog("Merge export failed: \(error)", module: "AudioRecorder", level: .error)
                debugCaptureError(error, context: "Merging multiple audio files")
            }
            throw AudioRecorderError.mergeFailed
        }

        let totalDuration = CMTimeGetSeconds(currentTime)
        debugLog("Merged \(urls.count) audio files, total duration: \(totalDuration)s", module: "AudioRecorder")

        return outputURL
    }
}

// MARK: - Errors

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case recordingFailed
    case sessionConfigurationFailed
    case mergeFailed
    case chunkCreationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Доступ к микрофону запрещён. Пожалуйста, разрешите доступ в Настройках."
        case .recordingFailed:
            return "Не удалось начать запись."
        case .sessionConfigurationFailed:
            return "Не удалось настроить аудио сессию для записи."
        case .mergeFailed:
            return "Не удалось склеить аудиофайлы."
        case .chunkCreationFailed:
            return "Не удалось создать аудио-чанк."
        }
    }
}

// MARK: - VAD Configuration

struct VADConfig {
    /// Порог тишины (нормализованный 0-1). audioLevel ниже этого = тишина
    var silenceThreshold: Float = 0.08  // ~-55dB

    /// Длительность тишины для завершения чанка (секунды)
    var silenceDurationThreshold: TimeInterval = 1.5

    /// Минимальная длина чанка с речью (секунды)
    var minimumChunkDuration: TimeInterval = 10.0

    /// Максимальная длина чанка (секунды) - принудительная отсечка
    var maximumChunkDuration: TimeInterval = 60.0
}

// MARK: - Helper Extensions

private extension Float {
    func nonZeroOr(_ defaultValue: Float) -> Float {
        self > 0 ? self : defaultValue
    }
}

private extension Double {
    func nonZeroOr(_ defaultValue: Double) -> Double {
        self > 0 ? self : defaultValue
    }
}
