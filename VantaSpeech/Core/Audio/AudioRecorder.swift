import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isConverting = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?

    private let fileManager = FileManager.default
    private let converter = AudioConverter(quality: .low)  // 64k - optimal for voice

    var recordingsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)

        if !fileManager.fileExists(atPath: recordingsPath.path) {
            try? fileManager.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        }

        return recordingsPath
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() async throws -> URL {
        guard await requestPermission() else {
            throw AudioRecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let fileURL = recordingsDirectory.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.delegate = self
        audioRecorder?.record()

        isRecording = true
        startTime = Date()
        startTimer()

        return fileURL
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let recorder = audioRecorder, isRecording else { return nil }

        let url = recorder.url
        let duration = recordingDuration

        recorder.stop()
        stopTimer()

        isRecording = false
        recordingDuration = 0
        audioRecorder = nil

        return (url, duration)
    }

    /// Stop recording and convert to OGG format
    /// - Returns: Result with OGG file URL and duration, or error
    func stopRecordingAndConvert() async -> Result<(url: URL, duration: TimeInterval), Error> {
        guard let result = stopRecording() else {
            return .failure(AudioRecorderError.recordingFailed)
        }

        isConverting = true
        defer { isConverting = false }

        do {
            let oggURL = try await converter.convertToOGG(
                inputURL: result.url,
                deleteSource: true  // Delete M4A after successful conversion
            )
            return .success((oggURL, result.duration))
        } catch {
            // If conversion fails, return original M4A
            print("OGG conversion failed: \(error.localizedDescription). Using M4A.")
            return .success(result)
        }
    }

    /// Stop recording with optional OGG conversion
    /// - Parameter convertToOGG: Whether to convert to OGG format
    /// - Returns: Result with file URL and duration
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
    }

    func resumeRecording() {
        audioRecorder?.record()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
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
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                isRecording = false
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            isRecording = false
            if let error = error {
                print("Recording error: \(error.localizedDescription)")
            }
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Please enable it in Settings."
        case .recordingFailed:
            return "Failed to start recording."
        }
    }
}
