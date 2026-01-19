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

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.startTime)
    }

    private var timeUntilStart: String {
        let now = Date()
        if isOngoing {
            return "Сейчас"
        }

        let interval = event.startTime.timeIntervalSince(now)
        let minutes = Int(interval / 60)

        if minutes < 1 {
            return "\(formattedStartTime) — начинается"
        } else if minutes < 60 {
            return "\(formattedStartTime) (через \(minutes) мин)"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(formattedStartTime) (через \(hours) ч)"
            }
            return "\(formattedStartTime) (через \(hours) ч \(remainingMinutes) мин)"
        }
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
                // Time indicator
                VStack(spacing: 2) {
                    if isOngoing {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .modifier(PulseAnimation())
                    } else {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24)

                // Event info
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.subject)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(timeUntilStart)
                            .font(.caption)
                            .foregroundStyle(isOngoing ? .green : .secondary)
                            .fontWeight(isOngoing ? .semibold : .regular)

                        if !event.attendees.isEmpty {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(event.humanAttendees.count) участн.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let location = event.location, !location.isEmpty {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Record button for ongoing meetings
                if isOngoing {
                    Image(systemName: "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOngoing ? Color.green.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOngoing ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            MeetingDetailSheet(event: event)
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

// MARK: - Meeting Detail Sheet

struct MeetingDetailSheet: View {
    let event: EASCalendarEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Basic info
                Section {
                    // Название встречи жирным без label
                    Text(event.subject)
                        .font(.headline)
                        .fontWeight(.bold)

                    // Дата в русском формате
                    LabeledContent("Дата") {
                        Text(formattedRussianDate(event.startTime))
                    }

                    // Время как промежуток
                    LabeledContent("Время") {
                        Text(formattedTimeRange())
                    }

                    LabeledContent("Длительность", value: event.formattedDuration)

                    if let location = event.location, !location.isEmpty {
                        LabeledContent("Место", value: location)
                    }
                }

                // Organizer
                if let organizer = event.organizer {
                    Section("Организатор") {
                        Label {
                            VStack(alignment: .leading) {
                                Text(organizer.name)
                                Text(organizer.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Attendees
                if !event.humanAttendees.isEmpty {
                    Section("Участники (\(event.humanAttendees.count))") {
                        ForEach(Array(event.humanAttendees.enumerated()), id: \.offset) { _, attendee in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(attendee.name)
                                    if !attendee.email.isEmpty {
                                        Text(attendee.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: attendee.type == .optional ? "person.badge.minus" : "person.fill")
                                    .foregroundStyle(attendee.type == .optional ? .secondary : .primary)
                            }
                        }
                    }
                }

                // Description
                if let body = event.body, !body.isEmpty {
                    Section("Описание") {
                        Text(body.htmlStripped)
                            .font(.body)
                    }
                }
            }
            .navigationTitle("Встреча")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formattedRussianDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEE. d MMMM yyyy"
        let result = formatter.string(from: date)
        // Capitalize first letter
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    private func formattedTimeRange() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: event.startTime)
        let end = formatter.string(from: event.endTime)
        return "\(start) - \(end)"
    }
}

// MARK: - String Extension for HTML

private extension String {
    /// Strip HTML tags from string (safe implementation without NSAttributedString)
    var htmlStripped: String {
        // Simple regex strip - safer and faster than NSAttributedString
        var result = self
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&ndash;", "–"),
            ("&mdash;", "—"),
        ]

        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        // Clean up multiple newlines
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    UpcomingMeetingsSection()
        .padding()
}
