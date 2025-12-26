import SwiftUI

/// Стиль hover эффекта
enum VantaHoverStyle {
    /// Эффект подъёма с тенью (для карточек)
    case lift
    /// Подсветка фона (для кнопок и элементов списка)
    case highlight
    /// Небольшое увеличение масштаба (для иконок)
    case scale
}

/// Модификатор для добавления hover эффектов на iPad с trackpad/mouse
struct VantaHoverModifier: ViewModifier {
    let style: VantaHoverStyle
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(scaleValue)
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                y: shadowY
            )
            .background(backgroundColor)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .hoverEffect(hoverEffectShape)
    }

    private var scaleValue: CGFloat {
        guard isHovered else { return 1.0 }
        switch style {
        case .lift: return 1.01
        case .scale: return 1.08
        case .highlight: return 1.0
        }
    }

    private var shadowColor: Color {
        guard isHovered, style == .lift else { return .clear }
        return .black.opacity(0.12)
    }

    private var shadowRadius: CGFloat {
        guard isHovered, style == .lift else { return 0 }
        return 16
    }

    private var shadowY: CGFloat {
        guard isHovered, style == .lift else { return 0 }
        return 8
    }

    private var backgroundColor: Color {
        guard isHovered, style == .highlight else { return .clear }
        return Color.pinkVibrant.opacity(0.08)
    }

    private var hoverEffectShape: HoverEffect {
        switch style {
        case .lift: return .lift
        case .highlight: return .highlight
        case .scale: return .lift
        }
    }
}

extension View {
    /// Добавляет hover эффект для iPad с trackpad/mouse
    /// - Parameter style: Стиль hover эффекта
    func vantaHover(_ style: VantaHoverStyle = .lift) -> some View {
        modifier(VantaHoverModifier(style: style))
    }
}
