import Foundation
import AVFoundation
import Combine

enum PlaybackState {
    case idle
    case playing
    case paused
    case stopped
}

@MainActor
class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var progress: Float = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var currentURL: URL?

    var isPlaying: Bool { state == .playing }
    var formattedCurrentTime: String { formatTime(currentTime) }
    var formattedDuration: String { formatTime(duration) }

    func load(url: URL) {
        if currentURL == url && audioPlayer != nil { return }

        stop()
        currentURL = url

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            state = .idle
        } catch {
            print("Failed to load audio: \(error)")
        }
    }

    func play() {
        audioPlayer?.play()
        startTimer()
        state = .playing
    }

    func pause() {
        audioPlayer?.pause()
        timer?.invalidate()
        state = .paused
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        timer?.invalidate()
        timer = nil
        currentTime = 0
        progress = 0
        state = .stopped
    }

    func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, duration))
        audioPlayer?.currentTime = clampedTime
        currentTime = clampedTime
        updateProgress()
    }

    func seekToProgress(_ progress: Float) {
        let time = TimeInterval(progress) * duration
        seek(to: time)
    }

    func skipForward(seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }

    func skipBackward(seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    private func updateProgress() {
        currentTime = audioPlayer?.currentTime ?? 0
        if duration > 0 {
            progress = Float(currentTime / duration)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            timer?.invalidate()
            currentTime = 0
            progress = 0
            state = .stopped
        }
    }
}
