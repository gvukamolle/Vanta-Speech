import SwiftUI

struct CalendarView: View {
    @Binding var selectedDate: Date?
    @Binding var displayedMonth: Date
    let recordingDates: Set<DateComponents>

    private let calendar = Calendar.current
    private let weekdaySymbols = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        VStack(spacing: 16) {
            monthNavigationHeader

            weekdayHeaderRow

            daysGrid
        }
    }

    // MARK: - Month Navigation

    private var monthNavigationHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }

            Spacer()

            Text(monthYearString)
                .font(.headline)

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .frame(maxWidth: .infinity)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Days Grid

    private var daysGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
            ForEach(daysInMonth, id: \.self) { day in
                CalendarDayView(
                    day: day,
                    isToday: isToday(day),
                    hasRecordings: hasRecordings(for: day),
                    isSelected: isSelected(day),
                    onTap: {
                        if day != nil {
                            selectedDate = day
                        }
                    }
                )
            }
        }
        .frame(height: 280) // Уменьшаем высоту сетки дней
    }

    // MARK: - Helpers

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth).capitalized
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            return []
        }

        let startOfGrid = monthFirstWeek.start
        var days: [Date?] = []

        // Adjust for Monday start (Russian calendar)
        var adjustedStart = startOfGrid
        let weekday = calendar.component(.weekday, from: startOfGrid)
        if weekday == 1 { // Sunday
            adjustedStart = calendar.date(byAdding: .day, value: -6, to: startOfGrid) ?? startOfGrid
        } else {
            adjustedStart = calendar.date(byAdding: .day, value: 2 - weekday, to: startOfGrid) ?? startOfGrid
        }

        // Generate 6 weeks (42 days)
        for dayOffset in 0..<42 {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: adjustedStart) {
                let isInDisplayedMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
                days.append(isInDisplayedMonth ? date : nil)
            }
        }

        return days
    }

    private func isToday(_ date: Date?) -> Bool {
        guard let date = date else { return false }
        return calendar.isDateInToday(date)
    }

    private func hasRecordings(for date: Date?) -> Bool {
        guard let date = date else { return false }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return recordingDates.contains(components)
    }

    private func isSelected(_ date: Date?) -> Bool {
        guard let date = date, let selected = selectedDate else { return false }
        return calendar.isDate(date, inSameDayAs: selected)
    }

    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedDate: Date?
        @State private var displayedMonth = Date()

        var body: some View {
            CalendarView(
                selectedDate: $selectedDate,
                displayedMonth: $displayedMonth,
                recordingDates: [
                    Calendar.current.dateComponents([.year, .month, .day], from: Date()),
                    Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(-86400)),
                    Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(-86400 * 3))
                ]
            )
            .padding()
        }
    }

    return PreviewWrapper()
}
