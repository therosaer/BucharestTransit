import SwiftUI
import MapKit
#if canImport(_MapKit_SwiftUI)
import _MapKit_SwiftUI
#endif


public struct TransitMapView: View {
    @ObservedObject var appState: AppState
    @AppStorage("map_hide_stale_vehicles") private var hideStaleVehicles = false
    @State private var locateTrigger: Int = 0
    @State private var lineExplorerDetent: PresentationDetent = .fraction(0.42)

    public var body: some View {
        ZStack(alignment: .top) {
            // MARK: - OpenStreetMap / CartoDB Interactive Map
            OpenStreetMapView(
                appState: appState,
                vehicles: filteredVehicles,
                selectedLine: appState.selectedLine,
                activeLineData: appState.activeLineData,
                lineDirection: appState.lineDirection,
                locateTrigger: locateTrigger,
                selectedVehicle: appState.selectedVehicle,
                onVehicleTapped: { v in
                    HapticFeedback.trigger(.medium)
                    appState.selectVehicle(v)
                }
            )
            .ignoresSafeArea()
            .zIndex(0)

            // MARK: - Top Floating UI (Search + Chips)
            VStack(spacing: 8) {
                SearchCapsuleView(appState: appState)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .zIndex(10)

            // MARK: - Floating Apple Action Dock (Locate, Sync, Theme)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            if appState.showLineExplorer {
                                ActionButton(icon: "xmark", color: .secondary) {
                                    HapticFeedback.trigger(.light)
                                    appState.clearLineSelection()
                                }
                                .accessibilityLabel("Închide traseul")
                            }

                            // Locate User
                            ActionButton(icon: "location.fill", color: .appleBlue) {
                                HapticFeedback.trigger(.medium)
                                locateTrigger += 1
                            }
                        }

                        // Sync Refresh
                        ActionButton(icon: "arrow.clockwise", color: .primary, isSpinning: appState.isSyncing) {
                            HapticFeedback.trigger(.medium)
                            Task { await appState.refreshData() }
                        }
                    }
                    .padding(8)
                    .liquidGlass(cornerRadius: 18)
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        // Vehicle Inspector Bottom Sheet
        .sheet(isPresented: $appState.showVehicleInspector) {
            if let v = appState.selectedVehicle {
                VehicleInspectorSheet(appState: appState, vehicle: v)
                    .presentationDetents([.fraction(0.35), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        }
        // Line Explorer Bottom Sheet
        .sheet(
            isPresented: $appState.showLineExplorer,
            onDismiss: { appState.clearLineSelection() }
        ) {
            if let line = appState.selectedLine {
                LineExplorerSheet(
                    appState: appState,
                    line: line,
                    isCompact: lineExplorerDetent == .height(120)
                )
                    .presentationDetents([.height(120), .fraction(0.42), .large], selection: $lineExplorerDetent)
                    .presentationContentInteraction(.resizes)
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(120)))
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    .interactiveDismissDisabled()
            }
        }
        .sheet(
            isPresented: $appState.showStopInspector,
            onDismiss: { appState.showPendingStopService() }
        ) {
            if let stop = appState.selectedStop {
                StopInspectorSheet(appState: appState, stop: stop)
                    .presentationDetents([.fraction(0.4), .medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        }
        .alert("Locație indisponibilă", isPresented: Binding(
            get: { appState.locationError != nil },
            set: { if !$0 { appState.locationError = nil } }
        )) {
            Button("OK", role: .cancel) {
                appState.locationError = nil
            }
        } message: {
            Text(appState.locationError ?? "")
        }
        .onChange(of: appState.showLineExplorer) { _, isShowing in
            if isShowing {
                lineExplorerDetent = .fraction(0.42)
            }
        }
    }

    private var filteredVehicles: [Vehicle] {
        let vehicles = hideStaleVehicles
            ? appState.vehicles.filter { $0.isTelemetryStale != true }
            : appState.vehicles

        if let selLine = appState.selectedLine {
            let lineVehicles = vehicles.filter { vehicle in
                guard vehicle.line.uppercased() == selLine.uppercased() else { return false }
                switch appState.lineDirection {
                case .both:
                    return true
                case .tur:
                    return vehicle.directionId == 0
                case .retur:
                    return vehicle.directionId == 1
                }
            }
            if appState.filterOnRouteOnly {
                return lineVehicles.filter { $0.isOnRoute != false }
            }
            return lineVehicles
        }

        let query = appState.searchQuery.trimmingCharacters(in: .whitespaces).uppercased()
        if !query.isEmpty {
            let exactLine = vehicles.filter { $0.line.uppercased() == query }
            if !exactLine.isEmpty {
                return exactLine
            }
            let partial = vehicles.filter {
                $0.line.uppercased().contains(query) || ($0.label?.uppercased().contains(query) == true)
            }
            if !partial.isEmpty {
                return Array(partial.prefix(75))
            }
        }

        // Leaflet renders up to 350 vehicles at fluid 60/120 FPS
        return Array(vehicles.prefix(350))
    }
}

private struct ActionButton: View {
    let icon: String
    let color: Color
    var isSpinning: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .rotationEffect(Angle(degrees: isSpinning ? 360 : 0))
                .animation(isSpinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isSpinning)
        }
    }
}
