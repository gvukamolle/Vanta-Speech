import SwiftUI

/// Экран деталей события календаря (основной для iPad)
struct EventDetailSheet: View {
    let event: EASCalendarEvent
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Заголовок события
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "calendar")
                                .font(.title2)
                                .foregroundStyle(Color.blueVibrant)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.subject)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            
                            Text(formatDate(event.startTime))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Время
                Section("Время") {
                    HStack {
                        Label("Начало", systemImage: "clock")
                        Spacer()
                        Text(formatTime(event.startTime))
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }
                    
                    HStack {
                        Label("Окончание", systemImage: "clock.fill")
                        Spacer()
                        Text(formatTime(event.endTime))
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }
                    
                    // Длительность
                    HStack {
                        Label("Длительность", systemImage: "hourglass")
                        Spacer()
                        Text(durationString(from: event.startTime, to: event.endTime))
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }
                }
                
                // Организатор
                if let organizer = event.organizer {
                    Section("Организатор") {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.blueVibrant.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: "person.fill")
                                    .font(.body)
                                    .foregroundStyle(Color.blueVibrant)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(organizer.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                
                                Text(organizer.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("Организатор")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.blueVibrant)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blueVibrant.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
                
                // Участники
                let otherAttendees = event.humanAttendees.filter { $0.email != event.organizer?.email }
                if !otherAttendees.isEmpty {
                    Section("Участники (\(otherAttendees.count))") {
                        ForEach(otherAttendees, id: \.email) { attendee in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color(.systemGray5))
                                        .frame(width: 36, height: 36)
                                    
                                    Image(systemName: "person")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attendee.name)
                                        .font(.body)
                                    
                                    Text(attendee.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                // Статус ответа
                                if let status = attendee.status {
                                    statusBadge(for: status)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // Место
                if let location = event.location, !location.isEmpty {
                    Section("Место проведения") {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: "mappin")
                                    .font(.body)
                                    .foregroundStyle(Color.green)
                            }
                            
                            Text(location)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Описание (plain text, без HTML)
                if let plainBody = event.plainBody {
                    Section("Описание") {
                        Text(plainBody)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Событие")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(Color.pinkVibrant)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter.string(from: date).capitalized
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func durationString(from start: Date, to end: Date) -> String {
        let duration = end.timeIntervalSince(start)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 && minutes > 0 {
            return "\(hours) ч \(minutes) мин"
        } else if hours > 0 {
            return "\(hours) ч"
        } else {
            return "\(minutes) мин"
        }
    }
    
    private func statusBadge(for status: EASResponseStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .accepted:
                return ("Принято", .green)
            case .declined:
                return ("Отклонено", .red)
            case .tentative:
                return ("Под вопросом", .orange)
            case .notResponded:
                return ("Нет ответа", .secondary)
            @unknown default:
                return ("Ожидается", .secondary)
            }
        }()
        
        return Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    EventDetailSheet(
        event: EASCalendarEvent(
            id: "test-123",
            subject: "Еженедельный созвон команды",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            location: "Конференц-зал 305",
            body: "Обсуждение текущих задач и планирование спринта.",
            organizer: EASAttendee(
                email: "organizer@company.com",
                name: "Иван Организатор",
                type: .required
            ),
            attendees: [
                EASAttendee(email: "user1@company.com", name: "Петр Участник", type: .required, status: .accepted),
                EASAttendee(email: "user2@company.com", name: "Мария Участник", type: .required, status: .tentative),
                EASAttendee(email: "user3@company.com", name: "Сергей Участник", type: .optional, status: .notResponded)
            ]
        )
    )
}
