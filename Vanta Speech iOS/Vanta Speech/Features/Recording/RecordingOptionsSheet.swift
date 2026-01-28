import SwiftUI

/// Sheet для выбора типа записи с предложением привязки к ближайшим встречам
struct RecordingOptionsSheet: View {
    let upcomingMeetings: [EASCalendarEvent]  // Теперь массив встреч (до 2)
    let presets: [RecordingPreset]
    let isRealtimeMode: Bool
    let onSelectPreset: (RecordingPreset, EASCalendarEvent?) -> Void  // (preset, selectedMeeting)
    let onCancel: () -> Void

    @State private var selectedMeetingId: String?
    
    /// Две ближайшие встречи по времени начала
    private var suggestedMeetings: [EASCalendarEvent] {
        Array(upcomingMeetings.prefix(2))
    }
    
    /// Выбранная встреча (если есть)
    private var selectedMeeting: EASCalendarEvent? {
        suggestedMeetings.first { $0.id == selectedMeetingId }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Секция предлагаемых встреч (только если есть встречи)
                if !suggestedMeetings.isEmpty {
                    Section {
                        ForEach(suggestedMeetings) { meeting in
                            MeetingSelectionRow(
                                meeting: meeting,
                                isSelected: selectedMeetingId == meeting.id
                            ) {
                                if selectedMeetingId == meeting.id {
                                    selectedMeetingId = nil
                                } else {
                                    selectedMeetingId = meeting.id
                                }
                            }
                        }
                    } header: {
                        Text(suggestedMeetings.count == 1 ? "Ближайшая встреча" : "Ближайшие встречи")
                    } footer: {
                        if selectedMeeting != nil {
                            Text("Запись будет автоматически привязана к выбранной встрече")
                        }
                    }
                }

                // MARK: - Секция выбора пресета
                Section {
                    ForEach(presets, id: \.rawValue) { preset in
                        Button {
                            onSelectPreset(preset, selectedMeeting)
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
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } header: {
                    Text("Тип записи")
                } footer: {
                    Text("Тип записи влияет на формат транскрипции и саммари")
                }
            }
            .navigationTitle("Начать запись")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.primary)
        .presentationDragIndicator(.visible)
        .onAppear {
            // По умолчанию выбираем первую встречу если есть
            if selectedMeetingId == nil, let first = suggestedMeetings.first {
                selectedMeetingId = first.id
            }
        }
    }
}

// MARK: - Meeting Selection Row (с круглым чекбоксом)

private struct MeetingSelectionRow: View {
    let meeting: EASCalendarEvent
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Иконка календаря
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
                    Text(meeting.subject)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        Label(formattedTime(meeting.startTime), systemImage: "clock")
                            .font(.caption)
                        if !meeting.humanAttendees.isEmpty {
                            Label("\(meeting.humanAttendees.count)", systemImage: "person.2")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Круглый чекбокс
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 16, height: 16)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    RecordingOptionsSheet(
        upcomingMeetings: [],
        presets: [.projectMeeting, .dailyStandup, .fastIdea],
        isRealtimeMode: false,
        onSelectPreset: { _, _ in },
        onCancel: {}
    )
}
