import Foundation
import CoreLocation

public enum VehicleType: String, Codable, CaseIterable, Identifiable, Sendable {
    case tram = "tram"
    case trolley = "trolley"
    case bus = "bus"
    case regional = "regional"
    case metro = "metro"
    case night = "night"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tram: return "Tramvai"
        case .trolley: return "Troleibuz"
        case .bus: return "Autobuz"
        case .regional: return "Regional"
        case .metro: return "Metrou"
        case .night: return "Noapte"
        }
    }

    public var icon: String {
        switch self {
        case .tram: return "tram.fill"
        case .trolley: return "cablecar.fill"
        case .bus: return "bus.fill"
        case .regional: return "bus.doubledecker.fill"
        case .metro: return "tram.tunnel.fill"
        case .night: return "moon.stars.fill"
        }
    }
}

public enum CrowdednessLevel: String, Codable, Sendable {
    case low = "low"
    case moderate = "moderate"
    case high = "high"

    public var title: String {
        switch self {
        case .low: return "Scăzut"
        case .moderate: return "Moderat"
        case .high: return "Aglomerat"
        }
    }
}

public enum VehicleDataSource: String, Codable, Sendable {
    case live
    case snapshot
}

public struct Vehicle: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let label: String?
    public let line: String
    public let routeId: String?
    public let directionId: Int?
    public let latitude: Double
    public let longitude: Double
    public let bearing: Double?
    public let speed: Double?
    public let crowdedness: CrowdednessLevel?
    public let isOnRoute: Bool?
    public let isOffRoute: Bool?
    public let distanceToRouteKm: Double?
    public let depotName: String?
    public let gpsTimestamp: String?
    public let gpsAgeMinutes: Int?
    public let lastPositionUpdate: Date?
    public let isStaleGps: Bool?
    public let vehicleType: VehicleType?
    public let dataSource: VehicleDataSource?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case line
        case routeId = "route_id"
        case directionId = "direction_id"
        case latitude
        case longitude
        case bearing
        case speed
        case crowdedness
        case isOnRoute = "is_on_route"
        case isOffRoute = "is_off_route"
        case distanceToRouteKm = "distance_to_route_km"
        case depotName = "depot_name"
        case gpsTimestamp = "gps_timestamp"
        case gpsAgeMinutes = "gps_age_minutes"
        case lastPositionUpdate = "last_position_update"
        case isStaleGps = "is_stale_gps"
        case vehicleType = "vehicle_type"
        case dataSource = "data_source"
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var displaySpeed: String {
        if let s = speed, s >= 0 {
            return String(format: "%.0f km/h", s)
        }
        return "Indisponibil"
    }

    public var directionLabel: String? {
        directionLabel(turTerminal: nil, returTerminal: nil)
    }

    public func directionLabel(turTerminal: String?, returTerminal: String?) -> String? {
        switch directionId {
        case 0:
            return Self.directionLabel("Tur", terminal: turTerminal)
        case 1:
            return Self.directionLabel("Retur", terminal: returTerminal)
        default: return nil
        }
    }

    private static func directionLabel(_ direction: String, terminal: String?) -> String {
        guard let terminal, !terminal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return direction
        }
        return "\(direction) (→ \(terminal))"
    }

    public var currentGpsAgeMinutes: Int? {
        guard let lastPositionUpdate else { return gpsAgeMinutes }
        return max(0, Int(Date().timeIntervalSince(lastPositionUpdate) / 60))
    }

    public var isTelemetryStale: Bool? {
        switch dataSource {
        case .snapshot: return true
        case .live:
            guard let lastPositionUpdate else { return nil }
            return Date().timeIntervalSince(lastPositionUpdate) > 120
        case .none: return isStaleGps
        }
    }

    public var telemetryStatusDescription: String {
        switch dataSource {
        case .live:
            if isTelemetryStale == true, let age = currentGpsAgeMinutes {
                return "GPS vechi · \(age == 0 ? "sub 1 min" : "\(age) min")"
            }
            if gpsTimestamp != nil {
                return "Date GPS live"
            }
            return "GPS live · timpul necunoscut"
        case .snapshot:
            if let age = currentGpsAgeMinutes {
                return "Copie offline · \(age == 0 ? "sub 1 min" : "\(age) min") veche"
            }
            return "Copie offline · poziție salvată"
        case .none:
            return "Sursa datelor necunoscută"
        }
    }

    public init(
        id: String,
        label: String? = nil,
        line: String,
        routeId: String? = nil,
        directionId: Int? = nil,
        latitude: Double,
        longitude: Double,
        bearing: Double? = nil,
        speed: Double? = nil,
        crowdedness: CrowdednessLevel? = nil,
        isOnRoute: Bool? = true,
        isOffRoute: Bool? = false,
        distanceToRouteKm: Double? = nil,
        depotName: String? = nil,
        gpsTimestamp: String? = nil,
        gpsAgeMinutes: Int? = nil,
        lastPositionUpdate: Date? = nil,
        isStaleGps: Bool? = false,
        vehicleType: VehicleType? = .bus,
        dataSource: VehicleDataSource? = nil
    ) {
        self.id = id
        self.label = label
        self.line = line
        self.routeId = routeId
        self.directionId = directionId
        self.latitude = latitude
        self.longitude = longitude
        self.bearing = bearing
        self.speed = speed
        self.crowdedness = crowdedness
        self.isOnRoute = isOnRoute
        self.isOffRoute = isOffRoute
        self.distanceToRouteKm = distanceToRouteKm
        self.depotName = depotName
        self.gpsTimestamp = gpsTimestamp
        self.gpsAgeMinutes = gpsAgeMinutes
        self.lastPositionUpdate = lastPositionUpdate
        self.isStaleGps = isStaleGps
        self.vehicleType = vehicleType
        self.dataSource = dataSource
    }

    public static func == (lhs: Vehicle, rhs: Vehicle) -> Bool {
        lhs.id == rhs.id &&
        lhs.latitude == rhs.latitude &&
        lhs.longitude == rhs.longitude &&
        lhs.speed == rhs.speed &&
        lhs.dataSource == rhs.dataSource &&
        lhs.gpsTimestamp == rhs.gpsTimestamp &&
        lhs.lastPositionUpdate == rhs.lastPositionUpdate
    }
}
