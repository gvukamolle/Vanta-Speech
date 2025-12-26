import SwiftData
import SwiftUI

/// iPad-оптимизированный интерфейс с NavigationSplitView
struct iPadContentView: View {
    @EnvironmentObject var audioRecorder: AudioRecorder
    @EnvironmentObject var coordinator: RecordingCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @State private var selectedSection: SidebarSection = .library
    @State private var selectedRecording: Recording?

    /// Секции бокового меню
    enum SidebarSection: String, CaseIterable, Identifiable {
        case library = "История"
        case recording = "Запись"
        case settings = "Настройки"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .library: return "calendar"
            case .recording: return "mic.fill"
            case .settings: return "gear"
            }
        }
    }

    /// Нужен ли detail column (3-колоночный layout)
    private var needsDetailColumn: Bool {
        selectedSection != .settings && selectedRecording != nil
    }

    var body: some View {
        Group {
            if needsDetailColumn {
                // 3-колоночный layout когда есть выбранная запись
                NavigationSplitView {
                    sidebarView
                } content: {
                    contentView
                } detail: {
                    if let recording = selectedRecording {
                        RecordingDetailView(recording: recording)
                            .id(recording.id)
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                // 2-колоночный layout (settings или нет выбранной записи)
                NavigationSplitView {
                    sidebarView
                } detail: {
                    contentView
                }
            }
        }
        .tint(.pinkVibrant)
        .preferredColorScheme(colorScheme)
        .onChange(of: selectedSection) { _, _ in
            selectedRecording = nil
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List {
            ForEach(SidebarSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.rawValue, systemImage: section.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selectedSection == section
                            ? Color.pinkVibrant.opacity(0.15)
                            : Color.clear)
                )
                .foregroundStyle(selectedSection == section ? Color.pinkVibrant : .primary)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .navigationTitle("Vanta Speech")
        .listStyle(.sidebar)
    }

    // MARK: - Content Column

    @ViewBuilder
    private var contentView: some View {
        switch selectedSection {
        case .library:
            iPadLibraryContentView(
                selectedRecording: $selectedRecording,
                onOpenInNewWindow: openRecordingInNewWindow
            )
        case .recording:
            iPadRecordingContentView(selectedRecording: $selectedRecording)
        case .settings:
            iPadSettingsContentView()
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
