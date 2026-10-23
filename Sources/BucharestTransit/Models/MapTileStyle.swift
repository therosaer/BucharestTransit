import Foundation

public enum MapTileStyle: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case terrain
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Implicită"
        case .satellite: return "Satelit"
        case .terrain: return "Relief"
        case .light: return "Deschisă"
        case .dark: return "Întunecată"
        }
    }

    public var symbol: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.europe.africa"
        case .terrain: return "mountain.2"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}
