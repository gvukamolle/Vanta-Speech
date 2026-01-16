import SwiftUI
import Combine

/// Section showing upcoming calendar meetings from Exchange
struct UpcomingMeetingsSection: View {
    @StateObject private var calendarManager = EASCalendarManager.shared

    /// Filter to show only meetings happening soon (within 2 hours) or currently ongoing
    private var relevantMeetings: [EASCalendarEvent] {
        let now = Date()
        let twoHoursFromNow = Calendar.current.date(byAdding: .hour, value: 2, to: now) ?? now
        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now

        return calendarManager.cachedEvents
            .filter { event in
                // Show events that:
                // 1. Start within next 2 hours, OR
                // 2. Are currently ongoing (started up to 1 hour ago and not yet ended)
                let startsInFuture = event.startTime >= now && event.startTime <= twoHoursFromNow
                let isOngoing = event.startTime >= oneHourAgo && event.endTime > now
                return startsInFuture || isOngoing
            }
            .sorted { $0.startTime < $1.startTime }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        Group {
            if calendarManager.isConnected && !relevantMeetings.isEmpty {
                meetingsSection
            }
        }
    }

    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                Text("Ближайшие встречи")
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
    @State private var showDetail = false
    @State private var showRecordOptions = false

    private var isOngoing: Bool {
        let now = Date()
        return event.startTime <= now && event.endTime > now
    }

    private var timeUntilStart: String {
        let now = Date()
        if isOngoing {
            return "Сейчас"
        }

        let interval = event.startTime.timeIntervalSince(now)
        let minutes = Int(interval / 60)

        if minutes < 1 {
            return "Начинается"
        } else if minutes < 60 {
            return "Через \(minutes) мин"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "Через \(hours) ч"
            }
            return "Через \(hours) ч \(remainingMinutes) мин"
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
        .confirmationDialog(
            event.subject,
            isPresented: $showRecordOptions,
            titleVisibility: .visible
        ) {
            Button("Начать запись") {
                // Store meeting ID for linking - will be picked up by RecordingCoordinator
                MeetingRecordingLink.shared.pendingMeetingEvent = event
                // Notify to show preset picker in RecordingView
                NotificationCenter.default.post(name: .startRecordingForMeeting, object: event)
            }
            Button("Детали встречи") {
                showDetail = true
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Запись будет привязана к этой встрече (\(event.humanAttendees.count) участн.)")
        }
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
                    LabeledContent("Название", value: event.subject)

                    LabeledContent("Начало") {
                        Text(event.startTime, style: .date)
                        Text(event.startTime, style: .time)
                    }

                    LabeledContent("Окончание") {
                        Text(event.endTime, style: .time)
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
                        ForEach(event.humanAttendees, id: \.email) { attendee in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(attendee.name)
                                    Text(attendee.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
}

// MARK: - String Extension for HTML

private extension String {
    /// Strip HTML tags from string
    var htmlStripped: String {
        guard let data = self.data(using: .utf8) else { return self }

        if let attributedString = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributedString.string
        }

        // Fallback: simple regex strip
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

#Preview {
    UpcomingMeetingsSection()
        .padding()
}
