import Foundation
import SwiftUI
import Combine

public enum AppTab: String, CaseIterable, Identifiable {
    case map
    case lines
    case tickets
    case stats
    case layers

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .map: return "Hartă"
        case .lines: return "Linii"
        case .tickets: return "Elevi/Stud."
        case .stats: return "Statistici"
        case .layers: return "Straturi"
        }
    }

    public var systemImage: String {
        switch self {
        case .map: return "map.fill"
        case .lines: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .tickets: return "ticket.fill"
        case .stats: return "chart.bar.xaxis"
        case .layers: return "square.3.layers.3d"
        }
    }
}

public enum LineDirection: String, CaseIterable, Identifiable {
    case both = "Ambele"
    case tur = "Tur"
    case retur = "Retur"

    public var id: String { rawValue }
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // Tab Bar
    @Published public var selectedTab: AppTab = .map

    // Transit Data
    @Published public var vehicles: [Vehicle] = []
    @Published public var routes: [Route] = []
    @Published public var stats: TransitStats? = nil
    @Published public var isSyncing: Bool = false
    @Published public var syncCountdown: Int = 12
    @Published public var locationError: String? = nil
    @Published public var followingError: String? = nil

    // Selection & Filter State
    @Published public var selectedVehicle: Vehicle? = nil
    @Published public var selectedStop: MapStop? = nil
    @Published public var selectedVehicleLineData: LineDetails? = nil
    @Published public var isFollowingVehicle: Bool = false
    @Published public var selectedLine: String? = nil
    @Published public var activeLineData: LineDetails? = nil
    @Published public var lineDirection: LineDirection = .both
    @Published public var filterOnRouteOnly: Bool = true
    @Published public var activeModeFilter: String = "all"
    @Published public var searchQuery: String = ""

    // Sheets Presentation
    @Published public var showVehicleInspector: Bool = false
    @Published public var showLineExplorer: Bool = false
    @Published public var showStopInspector: Bool = false
    private var pendingStopService: StopService?

    // Bilet TB State
    @Published public var biletStatus: BiletStatus = BiletStatus(authenticated: false, account: nil, activeTicketsCount: 0, availableTicketsCount: 0)
    @Published public var biletActiveTickets: [Ticket] = []
    @Published public var biletTicketsError: String?
    @Published public var biletTicketsLoading = false

    private let api = TransitAPIService.shared
    private let liveActivityManager = TransitLiveActivityManager()
    private var backgroundSyncTask: Task<Void, Never>?
    private var followedVehicleID: String?
    private var followedVehicleLineData: LineDetails?

    public var mapStops: [MapStop] {
        LocalTransitDataManager.shared.allMapStops()
    }

    public init() {
        let (initialVehicles, initialStats) = TransitAPIService.getInitialData()
        self.vehicles = initialVehicles
        self.stats = initialStats
        self.routes = LocalTransitDataManager.shared.allRoutes(liveVehicles: initialVehicles)
    }

    // MARK: - Data Synchronization

    public func loadInitialData() async {
        isSyncing = true
        defer { isSyncing = false }

        async let fetchedVehicles = api.fetchVehicles()
        async let fetchedStats = api.fetchStats()
        async let fetchedRoutes = api.fetchRoutes()
        async let fetchedBiletStatus = api.fetchBiletStatus()

        let r = await fetchedRoutes
        let v = await fetchedVehicles
        self.vehicles = v
        self.stats = await fetchedStats
        self.routes = routes(r, updatingVehicleCountsFrom: v)

        let b = await fetchedBiletStatus
        self.biletStatus = b
        if b.authenticated {
            await loadBiletActiveTickets()
        }
    }

    public func refreshData() async {
        isSyncing = true
        defer { isSyncing = false }

        let v = await api.fetchVehicles()
        if !v.isEmpty {
            self.vehicles = v
            self.routes = routes(self.routes, updatingVehicleCountsFrom: v)
        }
        self.stats = await api.fetchStats()

        guard isFollowingVehicle,
              let followedVehicleID,
              let updatedVehicle = vehicles.first(where: { $0.id == followedVehicleID }) else {
            return
        }

        if selectedVehicle?.id == followedVehicleID {
            selectedVehicle = updatedVehicle
        }
        let lineData: LineDetails?
        if let followedVehicleLineData {
            lineData = followedVehicleLineData
        } else {
            lineData = await api.fetchLineDetails(line: updatedVehicle.line)
        }
        guard isFollowingVehicle, self.followedVehicleID == followedVehicleID else { return }
        if let lineData {
            followedVehicleLineData = lineData
        }
        await liveActivityManager.update(vehicle: updatedVehicle, lineDetails: lineData)
    }

    private func routes(_ routes: [Route], updatingVehicleCountsFrom vehicles: [Vehicle]) -> [Route] {
        var counts: [String: Int] = [:]
        for vehicle in vehicles {
            let line = vehicle.line.uppercased().trimmingCharacters(in: .whitespaces)
            counts[line, default: 0] += 1
        }

        return routes.map { route in
            Route(
                line: route.line,
                typeName: route.typeName,
                color: route.color,
                activeVehicles: counts[route.line.uppercased().trimmingCharacters(in: .whitespaces)] ?? 0,
                terminals: route.terminals
            )
        }
    }

    public func setAppIsActive(_ isActive: Bool) {
        if isActive {
            startBackgroundSync()
        } else {
            backgroundSyncTask?.cancel()
            backgroundSyncTask = nil
        }
    }

    private func startBackgroundSync() {
        guard backgroundSyncTask == nil else { return }
        backgroundSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let nextRefresh = ContinuousClock.now.advanced(by: .seconds(12))
                await self.refreshData()
                guard !Task.isCancelled else { break }
                let remaining = ContinuousClock.now.duration(to: nextRefresh)
                guard remaining > .zero else { continue }
                do {
                    try await Task.sleep(for: remaining)
                } catch {
                    break
                }
            }
        }
    }

    // MARK: - Line Selection

    public func selectLine(_ line: String) {
        if selectedLine == line {
            clearLineSelection()
            return
        }

        selectedLine = line
        showLineExplorer = true
        showVehicleInspector = false

        Task {
            if let details = await api.fetchLineDetails(line: line) {
                self.activeLineData = details
            }
        }
    }

    public func clearLineSelection() {
        selectedLine = nil
        activeLineData = nil
        showLineExplorer = false
    }

    // MARK: - Stop Selection

    public func selectStop(id: String) {
        guard let stop = mapStops.first(where: { $0.id == id }) else { return }
        presentStop(stop)
    }

    public func selectStop(name: String, lat: Double, lon: Double) {
        let normalizedName = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingStops = mapStops.filter {
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines) == normalizedName
        }
        let stop = matchingStops.min {
            coordinateDistanceSquared($0, latitude: lat, longitude: lon) <
                coordinateDistanceSquared($1, latitude: lat, longitude: lon)
        } ?? mapStops
            .filter { coordinateDistanceSquared($0, latitude: lat, longitude: lon) < 0.000001 }
            .min {
                coordinateDistanceSquared($0, latitude: lat, longitude: lon) <
                    coordinateDistanceSquared($1, latitude: lat, longitude: lon)
            }

        if let stop {
            presentStop(stop)
        }
    }

    public func dismissStopInspector() {
        selectedStop = nil
        showStopInspector = false
    }

    public func selectStopService(_ service: StopService) {
        pendingStopService = service
        dismissStopInspector()
    }

    public func showPendingStopService() {
        guard let service = pendingStopService else { return }
        pendingStopService = nil

        let direction: LineDirection = service.direction == "Tur" ? .tur : .retur
        selectedLine = service.line
        lineDirection = direction
        activeLineData = nil
        showVehicleInspector = false
        showLineExplorer = false

        Task {
            let details = await api.fetchLineDetails(line: service.line)
            guard selectedLine == service.line, lineDirection == direction else { return }
            activeLineData = details
            showLineExplorer = true
        }
    }

    private func presentStop(_ stop: MapStop) {
        selectedStop = stop
        showVehicleInspector = false
        showLineExplorer = false
        showStopInspector = true
    }

    private func coordinateDistanceSquared(_ stop: MapStop, latitude: Double, longitude: Double) -> Double {
        let latitudeDifference = stop.lat - latitude
        let longitudeDifference = (stop.lon - longitude) * cos(latitude * .pi / 180)
        return latitudeDifference * latitudeDifference + longitudeDifference * longitudeDifference
    }

    // MARK: - Vehicle Inspector

    public func selectVehicle(_ vehicle: Vehicle) {
        selectedVehicle = vehicle
        selectedVehicleLineData = activeLineData?.line.caseInsensitiveCompare(vehicle.line) == .orderedSame
            ? activeLineData
            : nil
        showVehicleInspector = true

        Task {
            guard selectedVehicleLineData == nil,
                  let details = await api.fetchLineDetails(line: vehicle.line),
                  selectedVehicle?.id == vehicle.id else { return }
            selectedVehicleLineData = details
        }
    }

    public func dismissVehicleInspector() {
        selectedVehicle = nil
        selectedVehicleLineData = nil
        showVehicleInspector = false
    }

    public func toggleFollowingSelectedVehicle() {
        guard let vehicle = selectedVehicle else { return }
        if isFollowingVehicle {
            stopFollowingVehicle()
            return
        }

        followingError = nil
        isFollowingVehicle = true
        Task {
            let lineData: LineDetails?
            if let selectedVehicleLineData {
                lineData = selectedVehicleLineData
            } else {
                lineData = await api.fetchLineDetails(line: vehicle.line)
            }
            guard isFollowingVehicle, selectedVehicle?.id == vehicle.id else { return }
            if let lineData {
                selectedVehicleLineData = lineData
            }
            do {
                try await liveActivityManager.start(vehicle: vehicle, lineDetails: lineData)
                followedVehicleID = vehicle.id
                followedVehicleLineData = lineData
            } catch {
                isFollowingVehicle = false
                followingError = error.localizedDescription
            }
        }
    }

    private func stopFollowingVehicle() {
        isFollowingVehicle = false
        followedVehicleID = nil
        followedVehicleLineData = nil
        Task {
            await liveActivityManager.end(vehicle: nil)
        }
    }

    // MARK: - Bilet TB Operations

    public func loadBiletActiveTickets() async {
        biletTicketsError = nil
        biletTicketsLoading = true
        defer { biletTicketsLoading = false }
        do {
            biletActiveTickets = try await api.fetchBiletActiveTickets()
        } catch {
            biletActiveTickets = []
            biletTicketsError = error.localizedDescription
        }
    }

    public func loginBilet(username: String, pass: String) async -> Bool {
        let success = await api.loginBilet(username: username, password: pass)
        if success {
            self.biletStatus = await api.fetchBiletStatus()
            await loadBiletActiveTickets()
        }
        return success
    }

    public func logoutBilet() async {
        guard await api.logoutBilet() else {
            biletTicketsError = "Sesiunea nu a putut fi eliminată din stocarea securizată."
            return
        }
        self.biletStatus = BiletStatus(authenticated: false, account: nil, activeTicketsCount: 0, availableTicketsCount: 0)
        self.biletActiveTickets = []
        self.biletTicketsError = nil
        self.biletTicketsLoading = false
    }
}
