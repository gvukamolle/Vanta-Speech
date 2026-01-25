import SwiftUI

extension Color {
    // MARK: - Hex Initializer

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: - Primary Colors

    static let vantaWhite = Color(hex: "#FFFFFF")
    static let vantaGray = Color(hex: "#808080")
    static let vantaCharcoal = Color(hex: "#363636")

    // MARK: - Accent Colors (current app palette)

    static let pinkLight = Color(hex: "#F9B9EB")
    static let pinkVibrant = Color(hex: "#FA68D5")
    static let blueLight = Color(hex: "#B3E5FF")
    static let blueVibrant = Color(hex: "#3DBAFC")

    // MARK: - Corporate Accent (confirm before switching)

    static let accentCorporate = Color(hex: "#0052CC")

    // MARK: - Dark Theme Surfaces

    static let darkBackground = Color(hex: "#1A1A1A")
    static let darkSurface = Color(hex: "#252525")
    static let darkSurfaceElevated = Color(hex: "#2F2F2F")
    static let darkTextSecondary = Color(hex: "#A0A0A0")
}
