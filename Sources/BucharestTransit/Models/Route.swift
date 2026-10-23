import Foundation

public struct Route: Identifiable, Codable, Sendable {
    public var id: String { line }
    public let line: String
    public let typeName: String?
    public let color: String?
    public let activeVehicles: Int
    public let terminals: [String]?

    public init(
        line: String,
        typeName: String? = nil,
        color: String? = nil,
        activeVehicles: Int = 0,
        terminals: [String]? = nil
    ) {
        self.line = line
        self.typeName = typeName
        self.color = color
        self.activeVehicles = activeVehicles
        self.terminals = terminals
    }

    enum CodingKeys: String, CodingKey {
        case line
        case typeName
        case color
        case activeVehicles = "active_vehicles"
        case terminals
    }

    public var hexColor: String {
        color ?? "#007AFF"
    }
}

public struct Station: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let lat: Double
    public let lon: Double
    public let scheduleWd: String?
    public let scheduleWe: String?

    public init(id: String, name: String, lat: Double, lon: Double, scheduleWd: String? = nil, scheduleWe: String? = nil) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.scheduleWd = scheduleWd
        self.scheduleWe = scheduleWe
    }

    public var todayDepartures: [String] {
        let isWeekend = Calendar.current.isDateInWeekend(Date())
        let raw = isWeekend ? (scheduleWe ?? scheduleWd) : (scheduleWd ?? scheduleWe)
        guard let s = raw, !s.isEmpty else { return [] }
        return s.split(separator: ",").map(String.init)
    }

    public func nextDepartures(limit: Int = 4) -> [(time: String, minutes: Int)] {
        let cal = Calendar.current
        let comp = cal.dateComponents([.hour, .minute], from: Date())
        guard let curH = comp.hour, let curM = comp.minute else { return [] }
        let nowMinutes = curH * 60 + curM

        var result: [(time: String, minutes: Int)] = []
        for t in todayDepartures {
            let parts = t.split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                let depMinutes = h * 60 + m
                if depMinutes >= nowMinutes {
                    result.append((time: t, minutes: depMinutes - nowMinutes))
                    if result.count >= limit { break }
                }
            }
        }
        return result
    }

    public var nextDepartureDisplay: String? {
        if let next = nextDepartures(limit: 1).first {
            if next.minutes == 0 { return "În stație (\(next.time))" }
            if next.minutes == 1 { return "în 1 min (\(next.time))" }
            return "în \(next.minutes) min (\(next.time))"
        }
        return nil
    }
}

public struct StopService: Identifiable, Sendable {
    public var id: String { "\(line)-\(direction)" }
    public let line: String
    public let direction: String
    public let typeName: String?
    public let color: String?
    public let scheduleWd: String?
    public let scheduleWe: String?

    public init(
        line: String,
        direction: String,
        typeName: String? = nil,
        color: String? = nil,
        scheduleWd: String? = nil,
        scheduleWe: String? = nil
    ) {
        self.line = line
        self.direction = direction
        self.typeName = typeName
        self.color = color
        self.scheduleWd = scheduleWd
        self.scheduleWe = scheduleWe
    }
}

public struct MapStop: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let lat: Double
    public let lon: Double
    public let services: [StopService]

    public init(id: String, name: String, lat: Double, lon: Double, services: [StopService]) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.services = services
    }
}

public struct LineDetails: Codable, Sendable {
    public let line: String
    public let color: String?
    public let typeName: String?
    public let turTerminal: String?
    public let returTerminal: String?
    public let turPath: [[Double]]?
    public let returPath: [[Double]]?
    public let turStations: [Station]?
    public let returStations: [Station]?

    public init(
        line: String,
        color: String? = nil,
        typeName: String? = nil,
        turTerminal: String? = nil,
        returTerminal: String? = nil,
        turPath: [[Double]]? = nil,
        returPath: [[Double]]? = nil,
        turStations: [Station]? = nil,
        returStations: [Station]? = nil
    ) {
        self.line = line
        self.color = color
        self.typeName = typeName
        self.turTerminal = turTerminal
        self.returTerminal = returTerminal
        self.turPath = turPath
        self.returPath = returPath
        self.turStations = turStations
        self.returStations = returStations
    }

    enum CodingKeys: String, CodingKey {
        case line
        case color
        case typeName
        case turTerminal = "tur_terminal"
        case returTerminal = "retur_terminal"
        case turPath = "tur_path"
        case returPath = "retur_path"
        case turStations = "tur_stations"
        case returStations = "retur_stations"
    }
}
