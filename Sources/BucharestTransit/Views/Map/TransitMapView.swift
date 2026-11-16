import SwiftUI
import MapKit
#if canImport(_MapKit_SwiftUI)
import _MapKit_SwiftUI
#endif


public struct TransitMapView: View {
    @ObservedObject var appState: AppState
    @AppStorage("map_hide_stale_vehicles") private var hideStaleVehicles = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineExplorerDetent: PresentationDetent = .fraction(0.42)

    public var body: some View {
        ZStack(alignment: .top) {
            // MARK: - OpenStreetMap / CartoDB Interactive Map
            AppleMapView(
                appState: appState,
                vehicles: filteredVehicles,
                selectedLine: appState.selectedLine,
                activeLineData: appState.activeLineData,
                lineDirection: appState.lineDirection,
                locateTrigger: appState.locateTrigger,
                selectedVehicle: appState.selectedVehicle,
                onVehicleTapped: { v in
                    HapticFeedback.trigger(.medium)
                    appState.selectVehicle(v)
                }
            )
            .ignoresSafeArea()
            .zIndex(0)

            // MARK: - Top Floating UI (Search, toggled from the dock)
            VStack(spacing: 8) {
                if appState.isMapSearchPresented {
                    SearchCapsuleView(appState: appState)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    HStack {
                        TicketCountdownPill(appState: appState)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: appState.isMapSearchPresented)
            .zIndex(10)
        }
        // Vehicle Inspector Bottom Sheet
        .sheet(isPresented: $appState.showVehicleInspector) {
            if let v = appState.selectedVehicle {
                VehicleInspectorSheet(appState: appState, vehicle: v)
                    .presentationDetents([.fraction(0.35), .medium])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationBackground(.regularMaterial)
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
                    isCompact: lineExplorerDetent == .height(92)
                )
                    .presentationDetents([.height(92), .fraction(0.42), .large], selection: $lineExplorerDetent)
                    .presentationContentInteraction(.resizes)
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(92)))
                    .presentationBackground(.regularMaterial)
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
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationBackground(.regularMaterial)
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
