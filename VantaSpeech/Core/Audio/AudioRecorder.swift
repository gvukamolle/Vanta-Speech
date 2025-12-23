import AVFoundation
import Foundation

/// Audio recorder with background recording support
/// Continues recording when app is backgrounded or screen is locked
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isConverting = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var isInterrupted = false

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    private var pausedDuration: TimeInterval = 0

    private let fileManager = FileManager.default
    private let converter = AudioConverter(quality: .low)  // 64k - optimal for voice

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
            print("Failed to deactivate audio session: \(error)")
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
                // Interruption started (phone call, etc.)
                // Recording automatically pauses
                isInterrupted = true
                print("[AudioRecorder] Interruption began - recording paused")

            case .ended:
                // Interruption ended
                isInterrupted = false

                // Check if we should resume
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        // Resume recording
                        resumeRecording()
                        print("[AudioRecorder] Interruption ended - recording resumed")
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
            print("[AudioRecorder] Audio route changed: old device unavailable")
        case .newDeviceAvailable:
            // New device connected
            print("[AudioRecorder] Audio route changed: new device available")
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
            print("[AudioRecorder] App backgrounded - timer stopped, recording continues")
        }
    }

    @objc private func handleAppDidBecomeActive() {
        // App returned to foreground
        if isRecording {
            // Restart UI timer
            startTimer()
            // Duration is calculated from startTime, so it's accurate
            print("[AudioRecorder] App foregrounded - timer restarted")
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
        isInterrupted = false
        startTime = Date()
        pausedDuration = 0
        startTimer()

        print("[AudioRecorder] Recording started: \(fileURL.lastPathComponent)")

        return fileURL
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let recorder = audioRecorder, isRecording else { return nil }

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

        print("[AudioRecorder] Recording stopped: \(url.lastPathComponent), duration: \(duration)s")

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
            print("[AudioRecorder] OGG conversion failed: \(error.localizedDescription). Using M4A.")
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
        print("[AudioRecorder] Recording paused")
    }

    func resumeRecording() {
        audioRecorder?.record()
        // Adjust startTime to account for pause
        if pausedDuration > 0 {
            startTime = Date().addingTimeInterval(-pausedDuration)
        }
        print("[AudioRecorder] Recording resumed")
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
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
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                isRecording = false
                print("[AudioRecorder] Recording finished unsuccessfully")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            isRecording = false
            if let error = error {
                print("[AudioRecorder] Encoding error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Errors

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case recordingFailed
    case sessionConfigurationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Please enable it in Settings."
        case .recordingFailed:
            return "Failed to start recording."
        case .sessionConfigurationFailed:
            return "Failed to configure audio session for recording."
        }
    }
}
