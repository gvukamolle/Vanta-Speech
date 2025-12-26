import SwiftUI

/// Модификатор для добавления глобальных keyboard shortcuts
/// Поддерживает базовые команды для управления записью
struct KeyboardShortcutsModifier: ViewModifier {
    @EnvironmentObject var coordinator: RecordingCoordinator
    @EnvironmentObject var audioRecorder: AudioRecorder
    @StateObject private var presetSettings = PresetSettings.shared

    func body(content: Content) -> some View {
        content
            .focusable()
            .onKeyPress(characters: CharacterSet(charactersIn: "r"), phases: .down) { keyPress in
                // Проверяем, что нажата команда (⌘)
                guard keyPress.modifiers.contains(.command) else {
                    return .ignored
                }
                toggleRecording()
                return .handled
            }
    }

    private func toggleRecording() {
        Task { @MainActor in
            if audioRecorder.isRecording {
                _ = await coordinator.stopRecording()
            } else if let firstPreset = presetSettings.enabledPresets.first {
                try? await coordinator.startRecording(preset: firstPreset)
            }
        }
    }
}

/// Модификатор для управления воспроизведением (Space для play/pause)
struct PlaybackKeyboardShortcutsModifier: ViewModifier {
    @Binding var isPlaying: Bool
    let onToggle: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .onKeyPress(.space) {
                onToggle()
                return .handled
            }
    }
}

extension View {
    /// Добавляет глобальные keyboard shortcuts для управления записью
    /// - ⌘R: Старт/Стоп записи
    func recordingKeyboardShortcuts() -> some View {
        modifier(KeyboardShortcutsModifier())
    }

    /// Добавляет keyboard shortcut для управления воспроизведением
    /// - Space: Play/Pause
    func playbackKeyboardShortcuts(isPlaying: Binding<Bool>, onToggle: @escaping () -> Void) -> some View {
        modifier(PlaybackKeyboardShortcutsModifier(isPlaying: isPlaying, onToggle: onToggle))
    }
}
