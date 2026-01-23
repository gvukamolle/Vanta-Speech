import SwiftUI

/// Sheet для выбора типа записи с предложением привязки к ближайшей встрече
struct RecordingOptionsSheet: View {
    let upcomingMeeting: EASCalendarEvent?
    let presets: [RecordingPreset]
    let isRealtimeMode: Bool
    let onSelectPreset: (RecordingPreset, Bool) -> Void  // (preset, linkToMeeting)
    let onCancel: () -> Void

    @State private var linkToMeeting = true

    var body: some View {
        NavigationStack {
            List {
                // Секция встречи (если есть ближайшая)
                if let meeting = upcomingMeeting {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(meeting.subject)
                                .font(.headline)

                            HStack(spacing: 12) {
                                Label(formattedTime(meeting), systemImage: "clock")
                                if !meeting.humanAttendees.isEmpty {
                                    Label("\(meeting.humanAttendees.count) участн.", systemImage: "person.2")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            Toggle("Привязать к встрече", isOn: $linkToMeeting)
                                .tint(Color.pinkVibrant)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(isMeetingOngoing(meeting) ? "Текущая встреча" : "Ближайшая встреча")
                    } footer: {
                        if linkToMeeting {
                            Text("Запись будет автоматически привязана к этой встрече")
                        }
                    }
                }

                // Секция выбора пресета
                Section {
                    ForEach(presets, id: \.rawValue) { preset in
                        Button {
                            onSelectPreset(preset, linkToMeeting && upcomingMeeting != nil)
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

    private func formattedTime(_ event: EASCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: event.startTime)
        let end = formatter.string(from: event.endTime)
        return "\(start) — \(end)"
    }

    private func isMeetingOngoing(_ event: EASCalendarEvent) -> Bool {
        let now = Date()
        return event.startTime <= now && event.endTime > now
    }
}
