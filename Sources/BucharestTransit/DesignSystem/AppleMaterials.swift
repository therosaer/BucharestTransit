import SwiftUI

public extension Color {
    // Semantic system colors: adapt to dark mode and Increase Contrast automatically.
    static let appleBlue = Color(uiColor: .systemBlue)
    static let appleGreen = Color(uiColor: .systemGreen)
    static let appleOrange = Color(uiColor: .systemOrange)
    static let appleRed = Color(uiColor: .systemRed)
    static let applePurple = Color(uiColor: .systemPurple)
    static let appleIndigo = Color(uiColor: .systemIndigo)

    /// Page background that stays pure black in dark mode, even inside sheets
    /// (sheets otherwise switch to the elevated dark-gray grouped background).
    static let appBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .systemGroupedBackground
    })

    /// Row/card color that matches the normal (non-sheet) grouped rows. Sheets use the
    /// lighter "elevated" gray in dark mode, so pin it to the base value there.
    static let appCard = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
            : .secondarySystemGroupedBackground
    })

    /// Green for small text: darker in light mode so it meets contrast on white/grey backgrounds.
    static let appleGreenText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemGreen
            : UIColor(red: 0.0, green: 0.48, blue: 0.20, alpha: 1)
    })

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
    /// Plain grouped card for content inside scrolling screens (glass is reserved for floating chrome).
    func groupedCardBackground(cornerRadius: CGFloat = 20) -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground),
                   in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func appleGlassBackground(cornerRadius: CGFloat = 20) -> some View {
        modifier(AppleGlassModifier(cornerRadius: cornerRadius))
    }

    func liquidGlass(cornerRadius: CGFloat = 32) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }

    /// Native system Liquid Glass (refraction + touch response) on iOS 26+, material fallback otherwise.
    func nativeGlass(in shape: Capsule) -> some View {
        modifier(NativeGlassCapsuleModifier())
    }

    func nativeGlass(in shape: Circle) -> some View {
        modifier(NativeGlassCircleModifier())
    }

    func nativeGlass(cornerRadius: CGFloat) -> some View {
        modifier(NativeGlassRoundedModifier(cornerRadius: cornerRadius))
    }
}

public struct NativeGlassCapsuleModifier: ViewModifier {
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 7)
        }
    }
}

public struct NativeGlassCircleModifier: ViewModifier {
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 7)
        }
    }
}

public struct NativeGlassRoundedModifier: ViewModifier {
    var cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 7)
        }
    }
}

/// Groups adjacent native glass elements so they blend and morph together on iOS 26+.
public struct NativeGlassContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    public init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
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
