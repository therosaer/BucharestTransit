import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public enum HapticFeedback {
    public static func trigger(_ style: UIImpactStyle = .light) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style.feedbackStyle)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    public static func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }
}

public enum UIImpactStyle {
    case light, medium, heavy, rigid, soft

    #if canImport(UIKit)
    var feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        case .rigid: return .rigid
        case .soft: return .soft
        }
    }
    #endif
}
