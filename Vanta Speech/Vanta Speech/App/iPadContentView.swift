import SwiftData
import SwiftUI

/// iPad-оптимизированный интерфейс с overlay sidebar
struct iPadContentView: View {
    @EnvironmentObject var audioRecorder: AudioRecorder
    @EnvironmentObject var coordinator: RecordingCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @State private var selectedSection: SidebarSection = .library
    @State private var selectedRecording: Recording?
    @State private var isSidebarVisible = false

    private let sidebarWidth: CGFloat = 280

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

    var body: some View {
        ZStack(alignment: .leading) {
            // Основной контент (полноэкранный)
            mainContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Overlay sidebar
            if isSidebarVisible {
                // Затемнение фона
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSidebarVisible = false
                        }
                    }
                    .transition(.opacity)

                // Sidebar контент
                sidebarView
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .fill(Color.pinkVibrant.opacity(0.05))
                    )
                    .clipShape(
                        .rect(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 24,
                            topTrailingRadius: 24
                        )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 5, y: 0)
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isSidebarVisible)
        .tint(.pinkVibrant)
        .preferredColorScheme(colorScheme)
        .onChange(of: selectedSection) { _, _ in
            selectedRecording = nil
        }
    }

    // MARK: - Main Content View

    @ViewBuilder
    private var mainContentView: some View {
        Group {
            if selectedRecording != nil && selectedSection != .settings {
                // 2-колоночный layout с detail
                NavigationSplitView {
                    contentView
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                sidebarToggleButton
                            }
                        }
                } detail: {
                    if let recording = selectedRecording {
                        RecordingDetailView(recording: recording)
                            .id(recording.id)
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                // Одноколоночный layout
                NavigationStack {
                    contentView
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                sidebarToggleButton
                            }
                        }
                }
            }
        }
    }

    // MARK: - Sidebar Toggle Button

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isSidebarVisible.toggle()
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Vanta Speech")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Menu items
            VStack(spacing: 4) {
                ForEach(SidebarSection.allCases) { section in
                    sidebarButton(for: section)
                }
            }
            .padding(12)

            Spacer()

            // Version info
            VStack(spacing: 4) {
                Divider()
                Text("iPad Edition")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
            }
        }
    }

    private func sidebarButton(for section: SidebarSection) -> some View {
        Button {
            selectedSection = section
            // Закрываем sidebar после выбора
            withAnimation(.easeInOut(duration: 0.25)) {
                isSidebarVisible = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.body)
                    .frame(width: 24)

                Text(section.rawValue)
                    .font(.body)

                Spacer()

                if selectedSection == section {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.pinkVibrant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedSection == section
                    ? Color.pinkVibrant.opacity(0.15)
                    : Color.clear)
        )
        .foregroundStyle(selectedSection == section ? Color.pinkVibrant : .primary)
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
            .navigationTitle("История")
        case .recording:
            iPadRecordingContentView(selectedRecording: $selectedRecording)
                .navigationTitle("Запись")
        case .settings:
            iPadSettingsContentView()
                .navigationTitle("Настройки")
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
