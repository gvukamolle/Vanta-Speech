import Foundation
import AVFoundation
import Combine

enum RecordingState {
    case idle
    case recording
    case paused
    case stopped
}

@MainActor
class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?

    private var currentFileURL: URL?

    var isRecording: Bool { state == .recording }
    var isPaused: Bool { state == .paused }
    var isActive: Bool { state == .recording || state == .paused }

    func startRecording() -> URL? {
        let recordingsDir = getRecordingsDirectory()
        let fileName = generateFileName()
        let fileURL = recordingsDir.appendingPathComponent(fileName)
        currentFileURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()

            startTime = Date()
            pausedDuration = 0
            state = .recording

            startMetricsTimer()

            return fileURL
        } catch {
            print("Failed to start recording: \(error)")
            return nil
        }
    }

    func pauseRecording() {
        guard state == .recording else { return }

        audioRecorder?.pause()
        pauseStartTime = Date()
        state = .paused
    }

    func resumeRecording() {
        guard state == .paused else { return }

        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
        }

        audioRecorder?.record()
        state = .recording
    }

    func stopRecording() -> (URL, TimeInterval)? {
        guard state != .idle else { return nil }

        let url = currentFileURL
        let finalDuration = duration

        audioRecorder?.stop()
        audioRecorder = nil

        timer?.invalidate()
        timer = nil

        state = .idle
        duration = 0
        audioLevel = 0
        currentFileURL = nil

        if let url = url {
            return (url, finalDuration)
        }
        return nil
    }

    private func startMetricsTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
    }

    private func updateMetrics() {
        guard state == .recording, let start = startTime else { return }

        duration = Date().timeIntervalSince(start) - pausedDuration

        audioRecorder?.updateMeters()
        let level = audioRecorder?.averagePower(forChannel: 0) ?? -160
        // Normalize from dB (-160 to 0) to 0-1
        let normalizedLevel = max(0, (level + 60) / 60)
        audioLevel = normalizedLevel
    }

    private func getRecordingsDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings")

        if !FileManager.default.fileExists(atPath: recordingsPath.path) {
            try? FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        }

        return recordingsPath
    }

    private func generateFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "recording_\(formatter.string(from: Date())).m4a"
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                print("Recording did not finish successfully")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("Recording encode error: \(error)")
            }
        }
    }
}
