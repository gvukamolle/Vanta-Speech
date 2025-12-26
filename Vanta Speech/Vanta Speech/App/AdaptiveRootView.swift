import SwiftUI

/// Корневой view, который адаптируется под размер экрана:
/// - iPhone (compact width): показывает TabView
/// - iPad (regular width): показывает NavigationSplitView
struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var audioRecorder: AudioRecorder
    @EnvironmentObject var coordinator: RecordingCoordinator

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                ContentView()
            } else {
                iPadContentView()
            }
        }
        .recordingKeyboardShortcuts()
    }
}

#Preview("iPhone") {
    AdaptiveRootView()
        .environmentObject(AudioRecorder())
        .environmentObject(RecordingCoordinator.shared)
        .environment(\.horizontalSizeClass, .compact)
}

#Preview("iPad") {
    AdaptiveRootView()
        .environmentObject(AudioRecorder())
        .environmentObject(RecordingCoordinator.shared)
        .environment(\.horizontalSizeClass, .regular)
}
