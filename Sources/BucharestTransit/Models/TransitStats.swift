import Foundation

public struct TransitStats: Codable, Sendable {
    public let totalVehicles: Int
    public let activeLines: Int
    public let crowdedVehicles: Int?
    public let avgSpeed: Double?
    public let byType: [String: Int]?

    public init(
        totalVehicles: Int,
        activeLines: Int,
        crowdedVehicles: Int?,
        avgSpeed: Double?,
        byType: [String: Int]?
    ) {
        self.totalVehicles = totalVehicles
        self.activeLines = activeLines
        self.crowdedVehicles = crowdedVehicles
        self.avgSpeed = avgSpeed
        self.byType = byType
    }

    enum CodingKeys: String, CodingKey {
        case totalVehicles = "total_vehicles"
        case activeLines = "active_lines"
        case crowdedVehicles = "crowded_vehicles"
        case avgSpeed = "avg_speed"
        case byType = "by_type"
    }
}
