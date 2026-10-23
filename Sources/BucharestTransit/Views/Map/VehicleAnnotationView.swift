import SwiftUI

public struct VehicleAnnotationView: View {
    public let vehicle: Vehicle
    public let isSelected: Bool

    public var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Crowdedness Halo
                if vehicle.crowdedness == .high {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appleRed.opacity(0.8), lineWidth: 3)
                        .frame(width: 38, height: 26)
                } else if vehicle.crowdedness == .moderate {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appleOrange.opacity(0.7), lineWidth: 2)
                        .frame(width: 36, height: 24)
                }

                // Main Squircle Pin
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(pinBackgroundColor)
                    .frame(width: 32, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isSelected ? Color.white : Color.white.opacity(0.9), lineWidth: isSelected ? 2.5 : 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: isSelected ? 6 : 3, x: 0, y: 2)

                // Line Label
                Text(vehicle.line)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .scaleEffect(isSelected ? 1.25 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

            // Heading pointer if moving
            if let bearing = vehicle.bearing, let speed = vehicle.speed, speed > 3 {
                Image(systemName: "triangle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 5, height: 4)
                    .foregroundColor(pinBackgroundColor)
                    .rotationEffect(.degrees(bearing))
            }
        }
        .opacity(vehicle.isTelemetryStale == true ? 0.6 : 1.0)
    }

    private var pinBackgroundColor: Color {
        switch vehicle.vehicleType {
        case .tram:
            return Color(hex: "#FF3B30") // STB Red
        case .trolley:
            return Color(hex: "#34C759") // STB Green
        case .bus:
            return Color(hex: "#007AFF") // STB Blue
        case .regional:
            return Color(hex: "#5856D6") // Indigo
        case .night:
            return Color(hex: "#AF52DE") // Purple
        case .metro, .none:
            return Color(hex: "#FF9500") // Orange
        }
    }
}
