import SwiftUI
import SwiftData

/// Двухуровневая система предупреждений при отправке записи без привязки к встрече
struct MeetingLinkingAlert {
    
    // MARK: - Alert Types
    
    /// Первый уровень: Мягкое предупреждение
    static func firstLevelAlert(
        onLink: @escaping () -> Void,
        onContinueWithoutLink: @escaping () -> Void
    ) -> Alert {
        Alert(
            title: Text("Привязка к встрече"),
            message: Text("Рекомендуем привязать запись к событию календаря, чтобы получить более качественное саммари с учётом контекста встречи."),
            primaryButton: .default(Text("Привязать встречу"), action: onLink),
            secondaryButton: .default(Text("Отправить без привязки"), action: onContinueWithoutLink)
        )
    }
    
    /// Второй уровень: Яркое предупреждение с объяснением
    static func secondLevelAlert(
        onLink: @escaping () -> Void,
        onSendAnyway: @escaping () -> Void
    ) -> Alert {
        Alert(
            title: Text("Контекст встречи"),
            message: Text("Привязка встречи позволит приложению получить информацию об участниках, их ролях и текущих задачах. Это поможет избежать путаницы в именах и терминах при генерации саммари."),
            primaryButton: .default(Text("Выбрать встречу"), action: onLink),
            secondaryButton: .destructive(Text("Отправить как есть"), action: onSendAnyway)
        )
    }
}

// MARK: - View Modifier

/// ViewModifier для управления двухуровневыми алертами привязки встречи
struct MeetingLinkingAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let recording: Recording
    let onSend: () -> Void
    let onLink: () -> Void
    
    @State private var alertLevel: AlertLevel = .first
    
    enum AlertLevel {
        case first
        case second
    }
    
    func body(content: Content) -> some View {
        content
            .alert(isPresented: $isPresented) {
                switch alertLevel {
                case .first:
                    return MeetingLinkingAlert.firstLevelAlert(
                        onLink: {
                            isPresented = false
                            onLink()
                        },
                        onContinueWithoutLink: {
                            alertLevel = .second
                            // Alert stays presented with new content
                        }
                    )
                case .second:
                    return MeetingLinkingAlert.secondLevelAlert(
                        onLink: {
                            alertLevel = .first // Reset for next time
                            isPresented = false
                            onLink()
                        },
                        onSendAnyway: {
                            alertLevel = .first // Reset for next time
                            isPresented = false
                            onSend()
                        }
                    )
                }
            }
            .onChange(of: isPresented) { _, newValue in
                if !newValue {
                    // Reset level when alert is dismissed
                    alertLevel = .first
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Добавляет двухуровневую систему предупреждений при отправке без привязки к встрече
    func meetingLinkingAlert(
        isPresented: Binding<Bool>,
        for recording: Recording,
        onSend: @escaping () -> Void,
        onLink: @escaping () -> Void
    ) -> some View {
        self.modifier(MeetingLinkingAlertModifier(
            isPresented: isPresented,
            recording: recording,
            onSend: onSend,
            onLink: onLink
        ))
    }
}

// MARK: - Helper for Checking Link Status

extension Recording {
    /// Проверяет нужно ли показывать предупреждение о привязке
    var needsMeetingLinkWarning: Bool {
        !hasLinkedMeeting
    }
}
