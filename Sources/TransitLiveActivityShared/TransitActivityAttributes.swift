import ActivityKit
import Foundation

public struct TransitActivityStop: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct TransitActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let stops: [TransitActivityStop]
        public let nextStopIndex: Int?
        public let arrivalEstimate: Date?

        public init(stops: [TransitActivityStop], nextStopIndex: Int?, arrivalEstimate: Date?) {
            self.stops = stops
            self.nextStopIndex = nextStopIndex
            self.arrivalEstimate = arrivalEstimate
        }
    }

    public let line: String
    public let vehicleNumber: String

    public init(line: String, vehicleNumber: String) {
        self.line = line
        self.vehicleNumber = vehicleNumber
    }
}
