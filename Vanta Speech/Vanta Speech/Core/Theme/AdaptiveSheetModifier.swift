import SwiftUI

/// Модификатор для адаптивного отображения sheets на разных устройствах
/// - iOS 18+ на iPad: использует .form sizing для центрированных модальных окон
/// - iPhone: стандартные detents
struct AdaptiveSheetModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let detents: Set<PresentationDetent>

    init(detents: Set<PresentationDetent> = [.large]) {
        self.detents = detents
    }

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            // iPad - использовать form sizing для iOS 18+
            content
                .presentationDetents([.large])
                .presentationSizing(.form)
        } else {
            // iPhone - стандартные detents
            content
                .presentationDetents(detents)
        }
    }
}

extension View {
    /// Применяет адаптивные настройки sheet для iPad и iPhone
    /// - Parameter detents: Detents для использования на iPhone (по умолчанию .large)
    func adaptiveSheet(detents: Set<PresentationDetent> = [.large]) -> some View {
        modifier(AdaptiveSheetModifier(detents: detents))
    }
}
