import SwiftData
import SwiftUI

/// iPad-оптимизированный интерфейс без sidebar
/// Главный экран + Settings через sheet
struct iPadContentView: View {
    @EnvironmentObject var audioRecorder: AudioRecorder
    @EnvironmentObject var coordinator: RecordingCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @State private var selectedRecording: Recording?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            iPadMainView(
                selectedRecording: $selectedRecording,
                onOpenInNewWindow: openRecordingInNewWindow
            )
            .navigationTitle("Vanta Speech")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    settingsButton
                }
            }
        }
        .sheet(item: $selectedRecording) { recording in
            NavigationStack {
                RecordingDetailView(recording: recording)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                selectedRecording = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showSettings) {
            NavigationStack {
                iPadSettingsContentView()
                    .navigationTitle("Настройки")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showSettings = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
        }
        .tint(.pinkVibrant)
        .preferredColorScheme(colorScheme)
    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gear")
                .font(.title3)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Stage Manager Support

    private func openRecordingInNewWindow(_ recording: Recording) {
        if supportsMultipleWindows {
            openWindow(id: "recording", value: recording.id)
        }
    }

    // MARK: - Theme

    private var colorScheme: ColorScheme? {
        switch AppTheme(rawValue: appTheme) ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

#Preview {
    iPadContentView()
        .environmentObject(AudioRecorder())
        .environmentObject(RecordingCoordinator.shared)
        .modelContainer(for: Recording.self, inMemory: true)
}
