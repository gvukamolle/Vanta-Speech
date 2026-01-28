import SwiftUI

struct CalendarDayView: View {
    let day: Date?
    let isToday: Bool
    let hasRecordings: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let calendar = Calendar.current

    /// Размер ячейки: 44pt на iPad, 38pt на iPhone (для лучшей компоновки)
    private var cellSize: CGFloat {
        horizontalSizeClass == .regular ? 44 : 38
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if hasRecordings {
                    Circle()
                        .fill(Color.pinkVibrant.opacity(0.2))
                }

                if isSelected {
                    Circle()
                        .fill(Color.pinkVibrant)
                }

                if isToday && !isSelected {
                    Circle()
                        .stroke(Color.pinkVibrant, lineWidth: 2)
                }

                if let day = day {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(horizontalSizeClass == .regular ? .body : .caption, weight: hasRecordings || isSelected ? .semibold : .regular))
                        .foregroundStyle(textColor)
                }
            }
            .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
    }

    private var textColor: Color {
        if isSelected {
            return .white
        } else if hasRecordings {
            return .primary
        } else if day != nil {
            return .secondary
        } else {
            return .clear
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        CalendarDayView(day: Date(), isToday: true, hasRecordings: false, isSelected: false, onTap: {})
        CalendarDayView(day: Date(), isToday: false, hasRecordings: true, isSelected: false, onTap: {})
        CalendarDayView(day: Date(), isToday: false, hasRecordings: false, isSelected: true, onTap: {})
        CalendarDayView(day: nil, isToday: false, hasRecordings: false, isSelected: false, onTap: {})
    }
    .padding()
}
