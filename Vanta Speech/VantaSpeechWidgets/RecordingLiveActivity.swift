import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Circle Icon Button

/// Универсальная кнопка-кружок с иконкой и белой обводкой
struct CircleIconButton: View {
    let icon: String
    let color: Color
    let size: CGFloat

    init(icon: String, color: Color, size: CGFloat = 52) {
        self.icon = icon
        self.color = color
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: size > 50 ? 3 : 2)
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

struct RecordingLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock Screen / Banner View
            LockScreenLiveActivityView(context: context)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded View
                expandedContent(context: context)
            } compactLeading: {
                compactLeadingView(context: context)
            } compactTrailing: {
                compactTrailingView(context: context)
            } minimal: {
                minimalView(context: context)
            }
        }
    }

    // MARK: - Dynamic Island Expanded

    @DynamicIslandExpandedContentBuilder
    private func expandedContent(
        context: ActivityViewContext<RecordingActivityAttributes>
    ) -> DynamicIslandExpandedContent<some View> {

        DynamicIslandExpandedRegion(.leading) {
            // Левая кнопка: Пауза/Продолжить или Транскрипция
            leftActionButton(context: context)
        }

        DynamicIslandExpandedRegion(.center) {
            // Таймер по центру
            Text(formatDuration(context.state.duration))
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(context.state.status == .recording ? .red : .primary)
        }

        DynamicIslandExpandedRegion(.trailing) {
            // Правая кнопка: Стоп или Окей
            rightActionButton(context: context)
        }
    }

    // MARK: - Expanded Action Buttons

    @ViewBuilder
    private func leftActionButton(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        switch context.state.status {
        case .recording:
            // Пауза
            Button(intent: PauseRecordingIntent()) {
                CircleIconButton(icon: "pause.fill", color: .white)
            }
            .buttonStyle(.plain)

        case .paused:
            // Продолжить
            Button(intent: ResumeRecordingIntent()) {
                CircleIconButton(icon: "play.fill", color: .green)
            }
            .buttonStyle(.plain)

        case .stopped:
            // Транскрипция
            Button(intent: StartTranscriptionIntent()) {
                CircleIconButton(icon: "sparkles", color: .purple)
            }
            .buttonStyle(.plain)

        case .transcribing:
            // Прогресс
            ProgressView()
                .scaleEffect(0.8)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func rightActionButton(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        switch context.state.status {
        case .recording, .paused:
            // Стоп
            Button(intent: StopRecordingIntent()) {
                CircleIconButton(icon: "stop.fill", color: .red)
            }
            .buttonStyle(.plain)

        case .stopped:
            // Окей (закрыть)
            Button(intent: DismissActivityIntent()) {
                CircleIconButton(icon: "checkmark", color: .white)
            }
            .buttonStyle(.plain)

        case .transcribing:
            // Скрыть
            Button(intent: HideActivityIntent()) {
                CircleIconButton(icon: "xmark", color: .gray)
            }
            .buttonStyle(.plain)

        case .completed:
            EmptyView()
        }
    }

    // MARK: - Compact Views

    @ViewBuilder
    private func compactLeadingView(
        context: ActivityViewContext<RecordingActivityAttributes>
    ) -> some View {
        // Иконка статуса
        Image(systemName: context.state.status.systemImage)
            .font(.caption)
            .foregroundStyle(statusColor(context.state.status))
    }

    @ViewBuilder
    private func compactTrailingView(
        context: ActivityViewContext<RecordingActivityAttributes>
    ) -> some View {
        switch context.state.status {
        case .recording, .paused, .stopped:
            Text(formatDuration(context.state.duration))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(context.state.status == .recording ? .red : .primary)

        case .transcribing:
            ProgressView()
                .scaleEffect(0.6)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func minimalView(
        context: ActivityViewContext<RecordingActivityAttributes>
    ) -> some View {
        switch context.state.status {
        case .recording:
            Image(systemName: "waveform")
                .foregroundStyle(.pink)
        case .paused:
            Image(systemName: "pause.fill")
                .foregroundStyle(.blue)
        case .stopped:
            Image(systemName: "stop.fill")
                .foregroundStyle(.orange)
        case .transcribing:
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func statusColor(_ status: RecordingActivityStatus) -> Color {
        switch status {
        case .recording: return .pink
        case .paused: return .white
        case .stopped: return .white
        case .transcribing: return .purple
        case .completed: return .green
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    private let buttonSize: CGFloat = 52

    var body: some View {
        HStack {
            // Левая кнопка
            leftButton
                .frame(width: buttonSize, height: buttonSize)

            Spacer()

            // Таймер по центру
            Text(formatDuration(context.state.duration))
                .font(.title)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(context.state.status == .recording ? .red : .primary)

            Spacer()

            // Правая кнопка
            rightButton
                .frame(width: buttonSize, height: buttonSize)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.9))
    }

    @ViewBuilder
    private var leftButton: some View {
        switch context.state.status {
        case .recording:
            // Пауза
            Button(intent: PauseRecordingIntent()) {
                CircleIconButton(icon: "pause.fill", color: .white, size: buttonSize)
            }
            .buttonStyle(.plain)

        case .paused:
            // Продолжить
            Button(intent: ResumeRecordingIntent()) {
                CircleIconButton(icon: "play.fill", color: .green, size: buttonSize)
            }
            .buttonStyle(.plain)

        case .stopped:
            // Транскрипция
            Button(intent: StartTranscriptionIntent()) {
                CircleIconButton(icon: "sparkles", color: .purple, size: buttonSize)
            }
            .buttonStyle(.plain)

        case .transcribing:
            // Прогресс
            ProgressView()
                .scaleEffect(1.2)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var rightButton: some View {
        switch context.state.status {
        case .recording, .paused:
            // Стоп
            Button(intent: StopRecordingIntent()) {
                CircleIconButton(icon: "stop.fill", color: .red, size: buttonSize)
            }
            .buttonStyle(.plain)

        case .stopped:
            // Окей (закрыть)
            Button(intent: DismissActivityIntent()) {
                CircleIconButton(icon: "checkmark", color: .white, size: buttonSize)
            }
            .buttonStyle(.plain)

        case .transcribing:
            // Скрыть
            Button(intent: HideActivityIntent()) {
                CircleIconButton(icon: "xmark", color: .gray, size: buttonSize)
            }
            .buttonStyle(.plain)

        case .completed:
            EmptyView()
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
