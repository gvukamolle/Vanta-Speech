import SwiftUI

// MARK: - Vanta Glass Card Modifier

struct VantaGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let padding: CGFloat
    let tintOpacity: CGFloat?

    private var isDark: Bool { colorScheme == .dark }
    private var glassTintOpacity: Double {
        if let override = tintOpacity {
            return Double(override)
        }
        return isDark ? 0.15 : 0.30
    }
    private var shadowOpacity: Double { isDark ? 0.25 : 0.06 }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .padding(padding)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.clear)
                }
                .glassEffect(
                    .regular.tint(Color.pinkVibrant.opacity(glassTintOpacity)),
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .modifier(OptionalShadow(radius: shadowRadius, opacity: shadowOpacity))
        } else {
            content
                .padding(padding)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.pinkVibrant.opacity(glassTintOpacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .modifier(OptionalShadow(radius: shadowRadius, opacity: shadowOpacity))
        }
    }
}

// Helper to conditionally apply shadow
private struct OptionalShadow: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        if radius > 0 {
            content.shadow(color: .black.opacity(opacity), radius: radius, x: 0, y: 10)
        } else {
            content
        }
    }
}

// MARK: - Prominent Glass Modifier (for elevated elements)

struct VantaGlassProminentModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let tintOpacity: CGFloat?

    private var isDark: Bool { colorScheme == .dark }
    private var glassTintOpacity: Double {
        if let override = tintOpacity {
            return Double(override)
        }
        return isDark ? 0.15 : 0.30
    }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.clear)
                }
                .glassEffect(
                    .regular.tint(Color.pinkVibrant.opacity(glassTintOpacity)),
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.regularMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.pinkVibrant.opacity(glassTintOpacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Surface Modifier (non-glass)

struct VantaSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(colorScheme == .dark ? Color.darkSurface : Color.vantaWhite)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.pinkLight.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Blue Glass Card Modifier (for events)

struct VantaBlueGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let padding: CGFloat
    let tintOpacity: CGFloat?

    private var isDark: Bool { colorScheme == .dark }
    private var glassTintOpacity: Double {
        if let override = tintOpacity {
            return Double(override)
        }
        return isDark ? 0.12 : 0.25
    }
    private var shadowOpacity: Double { isDark ? 0.25 : 0.06 }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .padding(padding)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.clear)
                }
                .glassEffect(
                    .regular.tint(Color.blueVibrant.opacity(glassTintOpacity)),
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .modifier(OptionalShadow(radius: shadowRadius, opacity: shadowOpacity))
        } else {
            content
                .padding(padding)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.blueVibrant.opacity(glassTintOpacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .modifier(OptionalShadow(radius: shadowRadius, opacity: shadowOpacity))
        }
    }
}

// MARK: - View Extensions

extension View {
    func vantaGlassCard(
        cornerRadius: CGFloat = 24,
        shadowRadius: CGFloat = 20,
        padding: CGFloat = 0,
        tintOpacity: CGFloat? = nil
    ) -> some View {
        modifier(VantaGlassCardModifier(
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            padding: padding,
            tintOpacity: tintOpacity
        ))
    }

    func vantaBlueGlassCard(
        cornerRadius: CGFloat = 24,
        shadowRadius: CGFloat = 0,
        padding: CGFloat = 0,
        tintOpacity: CGFloat? = nil
    ) -> some View {
        modifier(VantaBlueGlassCardModifier(
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            padding: padding,
            tintOpacity: tintOpacity
        ))
    }

    func vantaGlassProminent(cornerRadius: CGFloat = 16, tintOpacity: CGFloat? = nil) -> some View {
        modifier(VantaGlassProminentModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }

    func vantaSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(VantaSurfaceModifier(cornerRadius: cornerRadius))
    }
}
