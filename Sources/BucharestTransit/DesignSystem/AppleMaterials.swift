import SwiftUI

public extension Color {
    static let appleBlue = Color(hex: "#007AFF")
    static let appleGreen = Color(hex: "#34C759")
    static let appleOrange = Color(hex: "#FF9500")
    static let appleRed = Color(hex: "#FF3B30")
    static let applePurple = Color(hex: "#AF52DE")
    static let appleIndigo = Color(hex: "#5856D6")

    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

public struct AppleGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 20

    public func body(content: Content) -> some View {
        content
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

public struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 32

    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        } else {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.03),
                                        Color.black.opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(0.3),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 7)
        }
    }
}

public extension View {
    func appleGlassBackground(cornerRadius: CGFloat = 20) -> some View {
        modifier(AppleGlassModifier(cornerRadius: cornerRadius))
    }

    func liquidGlass(cornerRadius: CGFloat = 32) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

public enum TransitTimeFormatter {
    public static func formatRemaining(seconds: Int) -> String {
        if seconds <= 0 { return "Expirat" }
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60

        let sStr = String(format: "%02d", s)
        let mStr = String(format: "%02d", m)
        let hStr = String(format: "%02d", h)

        if d > 0 {
            let dayText = d > 1 ? "zile" : "zi"
            return "\(d) \(dayText) \(hStr):\(mStr):\(sStr)"
        }
        return "\(hStr):\(mStr):\(sStr)"
    }
}
