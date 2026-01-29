import Foundation
import SwiftUI
import Combine

// MARK: - Environment Key for Recording Mode

private struct RecordingModeKey: EnvironmentKey {
    static let defaultValue: String = "standard"
}

extension EnvironmentValues {
    var currentRecordingMode: String {
        get { self[RecordingModeKey.self] }
        set { self[RecordingModeKey.self] = newValue }
    }
}

/// Section showing upcoming calendar meetings from Exchange
struct UpcomingMeetingsSection: View {
    @StateObject private var calendarManager = EASCalendarManager.shared

    /// Filter to show only today's meetings
    private var relevantMeetings: [EASCalendarEvent] {
        let now = Date()
        let calendar = Calendar.current

        // Start of today (00:00)
        let startOfDay = calendar.startOfDay(for: now)

        // End of today (23:59:59)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) ?? now

        return calendarManager.cachedEvents
            .filter { event in
                // Show events that:
                // 1. Are currently ongoing (already started AND not yet ended)
                let isOngoing = event.startTime <= now && event.endTime > now

                // 2. Start today (between 00:00 and 23:59:59)
                let isToday = event.startTime >= startOfDay && event.startTime <= endOfDay

                return isOngoing || isToday
            }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        Group {
            if calendarManager.isConnected {
                if relevantMeetings.isEmpty {
                    emptyStateView
                } else {
                    meetingsSection
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text("Встречи")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            Text("На сегодня встреч нет")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
        }
    }

    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                Text("Встречи сегодня")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                if calendarManager.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 4)

            ForEach(relevantMeetings) { event in
                MeetingCard(event: event)
            }
        }
    }
}

// MARK: - Meeting Card

private struct MeetingCard: View {
    let event: EASCalendarEvent
    @EnvironmentObject var coordinator: RecordingCoordinator
    @Environment(\.currentRecordingMode) private var currentRecordingMode
    @StateObject private var presetSettings = PresetSettings.shared
    @State private var showDetail = false
    @State private var showRecordOptions = false
    @State private var showRealtimeWarning = false
    @State private var pendingRealtimePreset: RecordingPreset?

    private var isOngoing: Bool {
        let now = Date()
        return event.startTime <= now && event.endTime > now
    }
    
    private var isPast: Bool {
        let now = Date()
        return event.endTime <= now
    }

    private var timeDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: event.startTime)
        let end = formatter.string(from: event.endTime)
        return "\(start) – \(end)"
    }

    var body: some View {
        Button {
            if isOngoing {
                showRecordOptions = true
            } else {
                showDetail = true
            }
        } label: {
            HStack(spacing: 12) {
                // Иконка календаря (синяя)
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(Color.blueVibrant)
                }
                
                // Информация о встрече
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.subject)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    // Время (начало – конец)
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(timeDisplay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Участники и место
                    HStack(spacing: 12) {
                        if !event.humanAttendees.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.caption2)
                                Text("\(event.humanAttendees.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if let location = event.location, !location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin")
                                    .font(.caption2)
                                Text(location)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Индикатор текущей встречи (стабильный для iPad)
                if isOngoing {
                    RecordingIndicatorDot(color: .green)
                }
                
                // Стрелка
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .vantaBlueGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.12)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isOngoing ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            EventDetailSheet(event: event)
        }
        .sheet(isPresented: $showRecordOptions) {
            MeetingRecordOptionsSheet(
                event: event,
                presets: presetSettings.enabledPresets,
                isRealtimeMode: isRealtimeMode,
                onSelectPreset: { preset in
                    showRecordOptions = false
                    startRecordingForMeeting(preset: preset)
                },
                onShowDetails: {
                    showRecordOptions = false
                    showDetail = true
                },
                onCancel: {
                    showRecordOptions = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Real-time транскрипция", isPresented: $showRealtimeWarning) {
            Button("Начать запись") {
                if let preset = pendingRealtimePreset {
                    performStartRecording(preset: preset, realtime: true)
                }
                pendingRealtimePreset = nil
            }
            Button("Отмена", role: .cancel) {
                pendingRealtimePreset = nil
            }
        } message: {
            Text("В этом режиме не сворачивайте приложение. При сворачивании запись будет приостановлена.")
        }
        .tint(.primary)
    }

    private var isRealtimeMode: Bool {
        currentRecordingMode == "realtime"
    }

    private func startRecordingForMeeting(preset: RecordingPreset) {
        // Store meeting for linking
        MeetingRecordingLink.shared.pendingMeetingEvent = event

        if isRealtimeMode {
            // Show warning for realtime mode
            pendingRealtimePreset = preset
            showRealtimeWarning = true
        } else {
            performStartRecording(preset: preset, realtime: false)
        }
    }

    private func performStartRecording(preset: RecordingPreset, realtime: Bool) {
        Task {
            do {
                if realtime {
                    try await coordinator.startRealtimeRecording(preset: preset)
                } else {
                    try await coordinator.startRecording(preset: preset)
                }
            } catch {
                debugCaptureError(error, context: "Starting recording for meeting")
            }
        }
    }
}

// MARK: - Recording Indicator Dot (стабильная анимация)

private struct RecordingIndicatorDot: View {
    let color: Color
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Meeting Record Options Sheet

private struct MeetingRecordOptionsSheet: View {
    let event: EASCalendarEvent
    let presets: [RecordingPreset]
    let isRealtimeMode: Bool
    let onSelectPreset: (RecordingPreset) -> Void
    let onShowDetails: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // Meeting info
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.subject)
                            .font(.headline)

                        HStack(spacing: 12) {
                            Label(formattedTime, systemImage: "clock")
                            if !event.humanAttendees.isEmpty {
                                Label("\(event.humanAttendees.count) участн.", systemImage: "person.2")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Запись будет привязана к этой встрече")
                }

                // Preset options
                Section {
                    ForEach(presets, id: \.rawValue) { preset in
                        Button {
                            onSelectPreset(preset)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.displayName)
                                        .foregroundStyle(.primary)
                                    if isRealtimeMode {
                                        Text("Real-time режим")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: preset.icon)
                                    .foregroundStyle(Color.pinkVibrant)
                            }
                        }
                    }
                } header: {
                    Text("Тип записи")
                }

                // Details button
                Section {
                    Button {
                        onShowDetails()
                    } label: {
                        Label("Детали встречи", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Начать запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        onCancel()
                    }
                }
            }
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: event.startTime)
        let end = formatter.string(from: event.endTime)
        return "\(start) — \(end)"
    }
}

// MARK: - Meeting Recording Link

/// Shared state for linking recordings to meetings
@MainActor
final class MeetingRecordingLink: ObservableObject {
    static let shared = MeetingRecordingLink()

    /// Meeting event pending to be linked to next recording
    @Published var pendingMeetingEvent: EASCalendarEvent?

    private init() {}

    /// Link a recording to the pending meeting and clear pending state
    func linkRecordingToPendingMeeting(_ recording: Recording) {
        guard let event = pendingMeetingEvent else { return }
        recording.linkToMeeting(event)
        pendingMeetingEvent = nil
        print("[MeetingLink] Linked recording '\(recording.title)' to meeting '\(event.subject)'")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let startRecordingForMeeting = Notification.Name("startRecordingForMeeting")
}
