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
    
    // Состояние для боковой панели деталей дня
    @State private var selectedDayForDetail: Date?
    @State private var showDayDetailSheet = false

    var body: some View {
        ZStack {
            NavigationStack {
                iPadMainView(
                    selectedRecording: $selectedRecording,
                    selectedDayForDetail: $selectedDayForDetail,
                    showDayDetailSheet: $showDayDetailSheet,
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
        // Боковая панель деталей дня (выезжает справа) - на уровне ZStack чтобы быть поверх всего
        .overlay(
            GeometryReader { geometry in
                ZStack {
                    // Затемнение фона при открытой панели
                    if showDayDetailSheet {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showDayDetailSheet = false
                                }
                            }
                            .transition(.opacity)
                    }
                    
                    // Боковая панель (во всю высоту, без скруглений)
                    if showDayDetailSheet, let date = selectedDayForDetail {
                        HStack(spacing: 0) {
                            Spacer()
                            
                            DayDetailSheet(
                                date: date,
                                onDismiss: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        showDayDetailSheet = false
                                    }
                                },
                                onOpenRecording: { recording in
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        showDayDetailSheet = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        selectedRecording = recording
                                    }
                                }
                            )
                            .environmentObject(coordinator)
                            .frame(width: min(420, geometry.size.width * 0.45))
                            .background(Color(.systemGroupedBackground))
                            .shadow(color: .black.opacity(0.3), radius: 15, x: -5, y: 0)
                        }
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: showDayDetailSheet)
            }
            .ignoresSafeArea()
        )
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
