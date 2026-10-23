import ActivityKit
import CoreLocation
import Foundation
import TransitLiveActivityShared

@MainActor
final class TransitLiveActivityManager {
    private var activityID: String?
    private var cachedStations: [Station] = []

    func start(vehicle: Vehicle, lineDetails: LineDetails?) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw ActivityError.disabled
        }
        for activity in Activity<TransitActivityAttributes>.activities {
            await endActivity(id: activity.id)
        }
        activityID = nil
        cachedStations = lineDetails.map { stations(for: vehicle, lineDetails: $0) } ?? []

        let attributes = TransitActivityAttributes(
            line: vehicle.line,
            vehicleNumber: vehicle.label ?? vehicle.id
        )
        let activity: Activity<TransitActivityAttributes>
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: activityContent(for: vehicle, stations: cachedStations),
                pushType: nil
            )
        } catch {
            throw ActivityError.startFailed(error)
        }
        activityID = activity.id
    }

    func update(vehicle: Vehicle, lineDetails: LineDetails?) async {
        guard let activityID else { return }
        if let lineDetails {
            cachedStations = stations(for: vehicle, lineDetails: lineDetails)
        }
        await updateActivity(
            id: activityID,
            content: activityContent(for: vehicle, stations: cachedStations)
        )
    }

    func end(vehicle: Vehicle?) async {
        guard let activityID else { return }
        if let vehicle,
           let activity = Activity<TransitActivityAttributes>.activities.first(where: {
               $0.id == activityID
           }),
           activity.attributes.line != vehicle.line ||
               activity.attributes.vehicleNumber != (vehicle.label ?? vehicle.id) {
            return
        }
        self.activityID = nil
        await endActivity(id: activityID)
    }

    nonisolated private func updateActivity(
        id: String,
        content: ActivityContent<TransitActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<TransitActivityAttributes>.activities.first(where: {
            $0.id == id
        }) else { return }
        await activity.update(content)
    }

    nonisolated private func endActivity(id: String) async {
        guard let activity = Activity<TransitActivityAttributes>.activities.first(where: {
            $0.id == id
        }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private func stations(for vehicle: Vehicle, lineDetails: LineDetails) -> [Station] {
        vehicle.directionId == 1
            ? (lineDetails.returStations ?? [])
            : (lineDetails.turStations ?? [])
    }

    private func contentState(
        for vehicle: Vehicle,
        stations: [Station]
    ) -> TransitActivityAttributes.ContentState {
        let stops = stations.map { TransitActivityStop(id: $0.id, name: $0.name) }
        guard !stations.isEmpty else {
            return TransitActivityAttributes.ContentState(
                stops: [],
                nextStopIndex: nil,
                arrivalEstimate: nil
            )
        }

        let location = CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude)
        let nextStopIndex = findNextStopIndex(
            from: location,
            bearing: vehicle.bearing,
            stations: stations
        )
        let nextStation = stations[nextStopIndex]
        let hasUsableLiveData = vehicle.dataSource == .live && vehicle.isTelemetryStale != true
        let arrivalEstimate: Date?
        if hasUsableLiveData {
            let speed = vehicle.speed.flatMap { $0 > 0.5 ? $0 : nil } ?? estimatedSpeed(for: vehicle.vehicleType)
            let distanceKm = distance(from: location, to: nextStation) / 1_000
            arrivalEstimate = Date().addingTimeInterval(max(0, distanceKm / speed * 3_600))
        } else {
            arrivalEstimate = nil
        }
        return TransitActivityAttributes.ContentState(
            stops: stops,
            nextStopIndex: nextStopIndex,
            arrivalEstimate: arrivalEstimate
        )
    }

    private func activityContent(
        for vehicle: Vehicle,
        stations: [Station]
    ) -> ActivityContent<TransitActivityAttributes.ContentState> {
        let state = contentState(for: vehicle, stations: stations)
        let staleDate = min(
            Date().addingTimeInterval(60),
            (state.arrivalEstimate ?? Date().addingTimeInterval(60)).addingTimeInterval(15)
        )
        return ActivityContent(state: state, staleDate: staleDate)
    }

    private func distance(from location: CLLocation, to station: Station) -> CLLocationDistance {
        CLLocation(latitude: station.lat, longitude: station.lon).distance(from: location)
    }

    private func findNextStopIndex(
        from location: CLLocation,
        bearing: Double?,
        stations: [Station]
    ) -> Int {
        let nearestIndex = stations.indices.min { lhs, rhs in
            distance(from: location, to: stations[lhs]) < distance(from: location, to: stations[rhs])
        } ?? 0
        guard let bearing, bearing.isFinite else { return nearestIndex }

        let heading = bearing * .pi / 180
        let latitudeScale = 111_320.0
        let longitudeScale = latitudeScale * cos(location.coordinate.latitude * .pi / 180)
        let forwardIndices = stations.indices.filter { index in
            let north = (stations[index].lat - location.coordinate.latitude) * latitudeScale
            let east = (stations[index].lon - location.coordinate.longitude) * longitudeScale
            return north * cos(heading) + east * sin(heading) >= 0
        }
        return forwardIndices.min { lhs, rhs in
            distance(from: location, to: stations[lhs]) < distance(from: location, to: stations[rhs])
        } ?? nearestIndex
    }

    private func estimatedSpeed(for vehicleType: VehicleType?) -> Double {
        switch vehicleType {
        case .tram, .trolley: 16
        case .regional: 25
        case .metro: 30
        case .bus, .night, .none: 15
        }
    }

    private enum ActivityError: LocalizedError {
        case disabled
        case startFailed(Error)

        var errorDescription: String? {
            switch self {
            case .disabled:
                return "Activitățile live sunt dezactivate în configurările iPhone-ului."
            case .startFailed(let error):
                return "Activitatea Live nu a putut fi creată: \(error.localizedDescription)"
            }
        }
    }
}
