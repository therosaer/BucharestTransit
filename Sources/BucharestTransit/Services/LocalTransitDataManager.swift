import Foundation

public struct RouteMetadata: Codable, Sendable {
    public let routeId: String
    public let line: String
    public let type: String
    public let typeName: String?
    public let color: String?
    public let operatorName: String?
    public let terminals: [String]?
    public let maxFleet: Int?
    public let headwayMin: Int?

    enum CodingKeys: String, CodingKey {
        case routeId = "route_id"
        case line
        case type
        case typeName
        case color
        case operatorName = "operator"
        case terminals
        case maxFleet = "max_fleet"
        case headwayMin = "headway_min"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.routeId = try container.decode(String.self, forKey: .routeId)
        self.line = try container.decode(String.self, forKey: .line)
        self.type = try container.decode(String.self, forKey: .type)
        self.typeName = try? container.decodeIfPresent(String.self, forKey: .typeName)
        self.color = try? container.decodeIfPresent(String.self, forKey: .color)
        self.operatorName = try? container.decodeIfPresent(String.self, forKey: .operatorName)
        if let rawTerms = try? container.decodeIfPresent([String?].self, forKey: .terminals) {
            self.terminals = rawTerms.compactMap { $0 }
        } else {
            self.terminals = nil
        }
        self.maxFleet = try? container.decodeIfPresent(Int.self, forKey: .maxFleet)
        self.headwayMin = try? container.decodeIfPresent(Int.self, forKey: .headwayMin)
    }
}

fileprivate struct RawGeometry: Codable, Sendable {
    let type: String?
    let coordinates: [[Double]]?
}

fileprivate struct RawStation: Codable, Sendable {
    let name: String
    let code: String?
    let terminal: String?
    let lat: Double
    let lon: Double
    let schedule_wd: String?
    let schedule_we: String?
}

fileprivate struct RawLineRouteEntry: Codable, Sendable {
    let line: String?
    let tur_geometry: RawGeometry?
    let retur_geometry: RawGeometry?
    let tur_terminal: String?
    let retur_terminal: String?
    let tur_stations: [RawStation]?
    let retur_stations: [RawStation]?
}

private struct MapStopAccumulator {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    var services: [StopService]
}

public final class LocalTransitDataManager: Sendable {
    public static let shared = LocalTransitDataManager()

    private let routesMap: [String: RouteMetadata]
    private let mapStops: [MapStop]
    private static let lineIndex: [String: RawLineRouteEntry] = loadLineIndex()

    private init() {
        var rMap: [String: RouteMetadata] = [:]

        // 1. Load routes_map.json (Bundle or Embedded Fallback)
        if let url = Self.resolveResourceURL(name: "routes_map", ext: "json"),
           let data = try? Data(contentsOf: url),
           let parsed = Self.decodeRoutesMap(from: data) {
            rMap = parsed
        } else if let data = EmbeddedTransitData.routesMapJSON.data(using: .utf8),
                  let parsed = Self.decodeRoutesMap(from: data) {
            rMap = parsed
        }

        self.routesMap = rMap
        self.mapStops = Self.buildMapStops(routesMap: rMap)
    }

    private static func buildMapStops(routesMap: [String: RouteMetadata]) -> [MapStop] {
        var metadataByLine: [String: RouteMetadata] = [:]
        for metadata in routesMap.values {
            let key = metadata.line.uppercased().trimmingCharacters(in: .whitespaces)
            if metadataByLine[key] == nil {
                metadataByLine[key] = metadata
            }
        }

        var grouped: [String: MapStopAccumulator] = [:]
        for (lineKey, entry) in lineIndex {
            let line = entry.line ?? lineKey
            let metadata = metadataByLine[line.uppercased().trimmingCharacters(in: .whitespaces)]
            let directions: [(String, [RawStation]?)] = [
                ("Tur", entry.tur_stations),
                ("Retur", entry.retur_stations)
            ]

            for (direction, stations) in directions {
                for station in stations ?? [] {
                    let name = station.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalizedName = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    let latitudeKey = Int((station.lat * 100_000).rounded())
                    let longitudeKey = Int((station.lon * 100_000).rounded())
                    let id = "\(normalizedName)|\(latitudeKey)|\(longitudeKey)"
                    let service = StopService(
                        line: line,
                        direction: direction,
                        typeName: metadata?.typeName,
                        color: metadata?.color,
                        scheduleWd: station.schedule_wd,
                        scheduleWe: station.schedule_we
                    )

                    var stop = grouped[id] ?? MapStopAccumulator(
                        id: id,
                        name: name,
                        lat: station.lat,
                        lon: station.lon,
                        services: []
                    )
                    if !stop.services.contains(where: { $0.id == service.id }) {
                        stop.services.append(service)
                    }
                    grouped[id] = stop
                }
            }
        }

        return grouped.values
            .map { stop in
                MapStop(
                    id: stop.id,
                    name: stop.name,
                    lat: stop.lat,
                    lon: stop.lon,
                    services: stop.services.sorted {
                        if $0.line != $1.line {
                            return $0.line.localizedStandardCompare($1.line) == .orderedAscending
                        }
                        return $0.direction.localizedStandardCompare($1.direction) == .orderedAscending
                    }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func loadLineIndex() -> [String: RawLineRouteEntry] {
        guard let url = resolveResourceURL(name: "line_routes_index", ext: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode([String: RawLineRouteEntry].self, from: data) else {
            return [:]
        }
        return parsed
    }

    public func loadDataIfNeeded() {
        // Data already loaded in init
    }

    private static func resolveResourceURL(name: String, ext: String) -> URL? {
        #if SWIFT_PACKAGE
        if let u = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources") {
            return u
        }
        if let u = Bundle.module.url(forResource: name, withExtension: ext) {
            return u
        }
        let moduleSub = Bundle.module.bundleURL.appendingPathComponent("Resources/\(name).\(ext)")
        if FileManager.default.fileExists(atPath: moduleSub.path) {
            return moduleSub
        }
        #endif

        if let u = Bundle.main.url(forResource: name, withExtension: ext) {
            return u
        }

        let mainSub = Bundle.main.bundleURL.appendingPathComponent("BucharestTransit_BucharestTransit.bundle/Resources/\(name).\(ext)")
        if FileManager.default.fileExists(atPath: mainSub.path) {
            return mainSub
        }

        return nil
    }

    private static func decodeRoutesMap(from data: Data) -> [String: RouteMetadata]? {
        if let parsed = try? JSONDecoder().decode([String: RouteMetadata].self, from: data), !parsed.isEmpty {
            return parsed
        }
        if let topObj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            var map: [String: RouteMetadata] = [:]
            for (k, v) in topObj {
                if let itemData = try? JSONSerialization.data(withJSONObject: v),
                   let item = try? JSONDecoder().decode(RouteMetadata.self, from: itemData) {
                    map[k] = item
                }
            }
            if !map.isEmpty { return map }
        }
        return nil
    }

    public func routeMetadata(for routeId: String) -> RouteMetadata? {
        loadDataIfNeeded()
        return routesMap[routeId]
    }

    public func metadataForLine(_ line: String) -> RouteMetadata? {
        loadDataIfNeeded()
        let q = line.uppercased().trimmingCharacters(in: .whitespaces)
        return routesMap.values.first { $0.line.uppercased() == q }
    }

    public func allRoutes(liveVehicles: [Vehicle] = []) -> [Route] {
        loadDataIfNeeded()

        var vehicleCounts: [String: Int] = [:]
        for v in liveVehicles {
            let l = v.line.uppercased().trimmingCharacters(in: .whitespaces)
            vehicleCounts[l, default: 0] += 1
        }

        var seenLines = Set<String>()
        var result: [Route] = []

        for meta in routesMap.values {
            let l = meta.line.uppercased()
            if seenLines.contains(l) { continue }
            seenLines.insert(l)

            let count = vehicleCounts[l] ?? 0
            result.append(Route(
                line: meta.line,
                typeName: meta.typeName ?? (l.hasPrefix("M") ? "Metrou" : "Autobuz"),
                color: meta.color ?? (l.hasPrefix("M") ? "#ffa502" : "#1e90ff"),
                activeVehicles: count,
                terminals: meta.terminals
            ))
        }

        // Sort: Active lines first, then by line natural sorting
        result.sort { a, b in
            if (a.activeVehicles > 0) != (b.activeVehicles > 0) {
                return a.activeVehicles > b.activeVehicles
            }
            if let aNum = Int(a.line), let bNum = Int(b.line) {
                return aNum < bNum
            }
            return a.line.localizedStandardCompare(b.line) == .orderedAscending
        }

        return result
    }

    public func allMapStops() -> [MapStop] {
        mapStops
    }

    public func lineDetails(line: String, liveVehicles: [Vehicle] = []) -> LineDetails? {
        loadDataIfNeeded()
        let key = line.uppercased().trimmingCharacters(in: .whitespaces)
        guard let raw = Self.lineIndex[key] else { return nil }

        let meta = metadataForLine(key)

        // Coordinates in line_routes_index.json are [lon, lat], convert to [lat, lon] for Apple Maps
        let turCoords = raw.tur_geometry?.coordinates?.map { [$0[1], $0[0]] }
        let returCoords = raw.retur_geometry?.coordinates?.map { [$0[1], $0[0]] }

        let turSt = raw.tur_stations?.map {
            Station(id: $0.code ?? UUID().uuidString, name: $0.name, lat: $0.lat, lon: $0.lon, scheduleWd: $0.schedule_wd, scheduleWe: $0.schedule_we)
        }
        let returSt = raw.retur_stations?.map {
            Station(id: $0.code ?? UUID().uuidString, name: $0.name, lat: $0.lat, lon: $0.lon, scheduleWd: $0.schedule_wd, scheduleWe: $0.schedule_we)
        }

        return LineDetails(
            line: line,
            color: meta?.color ?? "#007AFF",
            typeName: meta?.typeName ?? "Tranzit",
            turTerminal: raw.tur_terminal,
            returTerminal: raw.retur_terminal,
            turPath: turCoords,
            returPath: returCoords,
            turStations: turSt,
            returStations: returSt
        )
    }

}
