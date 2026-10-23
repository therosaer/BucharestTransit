import SwiftUI

public struct VehicleInspectorSheet: View {
    @ObservedObject var appState: AppState
    public let vehicle: Vehicle

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 14) {
                Text(vehicle.line)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.appleBlue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(vehicle.vehicleType?.displayName ?? "Vehicul") #\(vehicle.label ?? vehicle.id)")
                        .font(.system(size: 18, weight: .bold))

                    Text([directionLabel, serviceStatus].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundColor(serviceStatusColor)
                }

                Spacer()

                Button(action: {
                    HapticFeedback.trigger(.light)
                    appState.dismissVehicleInspector()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Metrics Grid
            HStack(spacing: 12) {
                MetricCard(
                    title: "Viteză GPS",
                    value: vehicle.displaySpeed,
                    icon: "speedometer"
                )

                MetricCard(
                    title: "Aglomerare",
                    value: vehicle.crowdedness?.title ?? "Indisponibil",
                    icon: "person.2.fill",
                    valueColor: crowdedColor
                )

                MetricCard(
                    title: "Date GPS",
                    value: gpsStatus,
                    icon: "antenna.radiowaves.left.and.right",
                    valueColor: gpsStatusColor
                )
            }
            .padding(.horizontal, 20)

            Text(vehicle.telemetryStatusDescription)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(vehicle.dataSource == .snapshot || vehicle.isTelemetryStale == true ? .appleOrange : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            // Action Buttons
            HStack(spacing: 12) {
                // Follow Vehicle Button
                Button(action: {
                    HapticFeedback.trigger(.medium)
                    appState.toggleFollowingSelectedVehicle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: appState.isFollowingVehicle ? "location.slash.fill" : "location.fill")
                        Text(appState.isFollowingVehicle ? "Oprește" : "Urmărește")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(appState.isFollowingVehicle ? Color.appleRed : Color.appleBlue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Show Line Route
                Button(action: {
                    HapticFeedback.trigger(.medium)
                    appState.selectLine(vehicle.line)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                        Text("Traseu Linie")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .appleGlassBackground(cornerRadius: 14)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if appState.isFollowingVehicle {
                Text("Urmărirea este disponibilă pe ecranul blocat și în Dynamic Island.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .alert("Urmărirea nu a pornit", isPresented: Binding(
            get: { appState.followingError != nil },
            set: { if !$0 { appState.followingError = nil } }
        )) {
            Button("OK", role: .cancel) {
                appState.followingError = nil
            }
        } message: {
            Text(appState.followingError ?? "")
        }
    }

    private var crowdedColor: Color {
        switch vehicle.crowdedness {
        case .high: return .appleRed
        case .moderate: return .appleOrange
        case .low, .none: return .appleGreen
        }
    }

    private var serviceStatus: String {
        switch vehicle.isOnRoute {
        case true: return "În serviciu comercial"
        case false: return vehicle.depotName ?? "În afara traseului"
        case nil: return "Serviciu necunoscut"
        }
    }

    private var directionLabel: String? {
        vehicle.directionLabel(
            turTerminal: appState.selectedVehicleLineData?.turTerminal,
            returTerminal: appState.selectedVehicleLineData?.returTerminal
        )
    }

    private var serviceStatusColor: Color {
        switch vehicle.isOnRoute {
        case true: return .appleGreen
        case false: return .appleOrange
        case nil: return .secondary
        }
    }

    private var gpsStatus: String {
        switch vehicle.dataSource {
        case .live: return vehicle.isTelemetryStale == true ? "Vechi" : (vehicle.isTelemetryStale == false ? "Live" : "Necunoscut")
        case .snapshot: return "Offline"
        case .none: return "Necunoscut"
        }
    }

    private var gpsStatusColor: Color {
        switch vehicle.dataSource {
        case .live:
            switch vehicle.isTelemetryStale {
            case true: return .appleOrange
            case false: return .appleGreen
            case nil: return .secondary
            }
        case .snapshot: return .appleOrange
        case .none: return .secondary
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .appleGlassBackground(cornerRadius: 14)
    }
}
