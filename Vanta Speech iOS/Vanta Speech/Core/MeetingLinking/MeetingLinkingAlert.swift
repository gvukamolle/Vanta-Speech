import SwiftUI
import SwiftData

/// Двухуровневая система предупреждений при отправке записи без привязки к встрече
/// Использует внешнее состояние для второго уровня для корректной работы на iOS 17+
struct MeetingLinkingAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var showSecondLevel: Bool
    let recording: Recording
    let onSend: () -> Void
    let onLink: () -> Void
    
    func body(content: Content) -> some View {
        content
            // Первый уровень алерта
            .alert("Привязка к встрече", isPresented: $isPresented) {
                Button("Привязать встречу") {
                    onLink()
                }
                Button("Отправить без привязки") {
                    // Показываем второй уровень через небольшую задержку
                    // чтобы первый алерт успел закрыться
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showSecondLevel = true
                    }
                }
            } message: {
                Text("Рекомендуем привязать запись к событию календаря, чтобы получить более качественное саммари с учётом контекста встречи.")
            }
            // Второй уровень алерта (отдельный) - без кнопки Cancel, только выбор действия
            .alert("Контекст встречи", isPresented: $showSecondLevel) {
                Button("Выбрать встречу") {
                    showSecondLevel = false
                    onLink()
                }
                Button("Отправить как есть") {
                    showSecondLevel = false
                    onSend()
                }
            } message: {
                Text("Привязка встречи позволит приложению получить информацию об участниках, их ролях и текущих задачах. Это поможет избежать путаницы в именах и терминах при генерации саммари.")
            }
    }
}

// MARK: - View Extension

extension View {
    /// Добавляет двухуровневую систему предупреждений при отправке без привязки к встрече
    /// - Parameters:
    ///   - isPresented: Binding для первого уровня алерта
    ///   - showSecondLevel: Binding для второго уровня алерта (должен быть @State в View)
    ///   - recording: Запись для которой показывается предупреждение
    ///   - onSend: Действие при отправке без привязки
    ///   - onLink: Действие при выборе привязки
    func meetingLinkingAlert(
        isPresented: Binding<Bool>,
        showSecondLevel: Binding<Bool>,
        for recording: Recording,
        onSend: @escaping () -> Void,
        onLink: @escaping () -> Void
    ) -> some View {
        self.modifier(MeetingLinkingAlertModifier(
            isPresented: isPresented,
            showSecondLevel: showSecondLevel,
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
