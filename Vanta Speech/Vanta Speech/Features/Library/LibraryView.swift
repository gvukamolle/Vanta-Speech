import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?
    @State private var showDayRecordings = false

    private let calendar = Calendar.current

    private var recordingDates: Set<DateComponents> {
        Set(recordings.map { recording in
            calendar.dateComponents([.year, .month, .day], from: recording.createdAt)
        })
    }

    private var recordingsCountForMonth: Int {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? displayedMonth

        return recordings.filter { recording in
            recording.createdAt >= startOfMonth && recording.createdAt < endOfMonth
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    calendarCard

                    if !recordings.isEmpty {
                        statsView
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("История")
            .onChange(of: selectedDate) { _, newValue in
                if newValue != nil {
                    showDayRecordings = true
                }
            }
            .sheet(isPresented: $showDayRecordings, onDismiss: {
                selectedDate = nil
            }) {
                if let date = selectedDate {
                    DayRecordingsSheet(date: date)
                        .adaptiveSheet()
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }

    // MARK: - Calendar Card

    private var calendarCard: some View {
        VStack(spacing: 0) {
            CalendarView(
                selectedDate: $selectedDate,
                displayedMonth: $displayedMonth,
                recordingDates: recordingDates
            )
            .padding()
        }
        .vantaGlassCard(cornerRadius: 24, shadowRadius: 0, tintOpacity: 0.15)
    }

    // MARK: - Stats View

    private var statsView: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Всего",
                value: "\(recordings.count)",
                icon: "waveform",
                color: .pinkVibrant
            )

            StatCard(
                title: "За месяц",
                value: "\(recordingsCountForMonth)",
                icon: "calendar",
                color: .blueVibrant
            )
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(Color.pinkVibrant.opacity(0.15))
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .vantaGlassCard(cornerRadius: 20, shadowRadius: 0, tintOpacity: 0.15)
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: Recording.self, inMemory: true)
}
