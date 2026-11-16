import SwiftUI
import MapKit
@preconcurrency import CoreLocation

/// One-shot location lookup for the "locate me" button.
@MainActor
final class MapLocationHelper: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending = false
    var onLocation: ((CLLocation) -> Void)?
    var onError: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        pending = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let cached = manager.location, abs(cached.timestamp.timeIntervalSinceNow) < 60,
               cached.horizontalAccuracy >= 0, cached.horizontalAccuracy <= 500 {
                onLocation?(cached)
            }
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            pending = false
            onError?("Activează accesul la locație în Configurări pentru a-ți afișa poziția pe hartă.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pending else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            pending = false
            onError?("Activează accesul la locație în Configurări pentru a-ți afișa poziția pe hartă.")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        pending = false
        onLocation?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard pending else { return }
        pending = false
        onError?("Nu s-a putut obține locația: \(error.localizedDescription)")
    }
}

// MARK: - Annotations

final class VehicleAnnotation: NSObject, MKAnnotation {
    let id: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var line: String
    var colorHex: String
    var crowd: Int      // 0 none, 1 moderate, 2 high
    var stale: Bool
    var typeName: String

    var title: String? { "Linia \(line)" }

    init(id: String, coordinate: CLLocationCoordinate2D, line: String, colorHex: String, crowd: Int, stale: Bool, typeName: String) {
        self.id = id
        self.coordinate = coordinate
        self.line = line
        self.colorHex = colorHex
        self.crowd = crowd
        self.stale = stale
        self.typeName = typeName
    }

    var signature: String { "\(line)|\(colorHex)|\(crowd)|\(stale)" }
}

final class StopAnnotation: NSObject, MKAnnotation {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let name: String
    let colorHex: String
    var title: String? { name }
    init(id: String, name: String, coordinate: CLLocationCoordinate2D, colorHex: String) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.colorHex = colorHex
    }
}

final class StationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let name: String
    let colorHex: String
    var title: String? { name }
    init(name: String, coordinate: CLLocationCoordinate2D, colorHex: String) {
        self.name = name
        self.coordinate = coordinate
        self.colorHex = colorHex
    }
}

final class ArrowAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let bearing: Double
    let colorHex: String
    init(coordinate: CLLocationCoordinate2D, bearing: Double, colorHex: String) {
        self.coordinate = coordinate
        self.bearing = bearing
        self.colorHex = colorHex
    }
}

final class RoutePolyline: MKPolyline {
    var color: UIColor = .systemBlue
}

// MARK: - Cached marker images

@MainActor
enum MapImages {
    private static var cache: [String: UIImage] = [:]

    static func color(_ hex: String) -> UIColor { UIColor(Color(hex: hex)) }

    static func plate(line: String, hex: String, ring: Int) -> UIImage {
        let key = "p|\(line)|\(hex)|\(ring)"
        if let image = cache[key] { return image }
        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let text = NSAttributedString(string: line, attributes: attrs)
        let textSize = text.size()
        let border: CGFloat = ring > 0 ? 2 : 1
        let size = CGSize(width: ceil(textSize.width) + 10 + border * 2, height: ceil(textSize.height) + 2 + border * 2)
        let fill = UIColor(Color(hex: hex).darkenedForWhiteText)
        let borderColor: UIColor = ring == 2 ? .systemRed : (ring == 1 ? .systemOrange : UIColor.white.withAlphaComponent(0.9))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: border / 2, dy: border / 2)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 5)
            fill.setFill()
            path.fill()
            borderColor.setStroke()
            path.lineWidth = border
            path.stroke()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
        }
        cache[key] = image
        return image
    }

    static func dot(hex: String) -> UIImage {
        let key = "d|\(hex)"
        if let image = cache[key] { return image }
        let size = CGSize(width: 28, height: 28)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(x: 8, y: 8, width: 12, height: 12)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
            color(hex).setStroke()
            let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 3
            ring.stroke()
        }
        cache[key] = image
        return image
    }

    static func arrow(hex: String) -> UIImage {
        let key = "a|\(hex)"
        if let image = cache[key] { return image }
        let size = CGSize(width: 22, height: 22)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 11, y: 2))
            path.addLine(to: CGPoint(x: 19, y: 19))
            path.addLine(to: CGPoint(x: 11, y: 14.5))
            path.addLine(to: CGPoint(x: 3, y: 19))
            path.close()
            color(hex).setFill()
            path.fill()
            UIColor.white.setStroke()
            path.lineWidth = 1.5
            path.lineJoinStyle = .round
            path.stroke()
        }
        cache[key] = image
        return image
    }
}

// MARK: - Map view

/// Apple Maps version of the live transit map. Same interface as the Leaflet map.
public struct AppleMapView: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("map_tile_style") private var mapTileStyle = MapTileStyle.standard.rawValue
    @AppStorage("map_show_stops") private var showStopsInsteadOfVehicles = false
    @ObservedObject var appState: AppState
    let vehicles: [Vehicle]
    let selectedLine: String?
    let activeLineData: LineDetails?
    let lineDirection: LineDirection
    let locateTrigger: Int
    let selectedVehicle: Vehicle?
    let onVehicleTapped: (Vehicle) -> Void

    public init(
        appState: AppState,
        vehicles: [Vehicle],
        selectedLine: String?,
        activeLineData: LineDetails?,
        lineDirection: LineDirection,
        locateTrigger: Int = 0,
        selectedVehicle: Vehicle? = nil,
        onVehicleTapped: @escaping (Vehicle) -> Void
    ) {
        self.appState = appState
        self.vehicles = vehicles
        self.selectedLine = selectedLine
        self.activeLineData = activeLineData
        self.lineDirection = lineDirection
        self.locateTrigger = locateTrigger
        self.selectedVehicle = selectedVehicle
        self.onVehicleTapped = onVehicleTapped
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsScale = false
        map.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.4375, longitude: 26.0975),
            span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16)
        )
        context.coordinator.locator.onError = { [weak appState] message in appState?.locationError = message }
        context.coordinator.locator.onLocation = { [weak map] location in
            map?.setRegion(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ), animated: true)
        }
        return map
    }

    public func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.applyStyle(map, satellite: mapTileStyle == MapTileStyle.satellite.rawValue)
        c.syncVehicles(map)
        c.syncRoute(map)
        c.syncStops(map)
        c.syncSelection(map)
        if c.lastLocateTrigger != locateTrigger {
            c.lastLocateTrigger = locateTrigger
            c.locator.request()
        }
    }

    @MainActor
    public final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AppleMapView
        let locator = MapLocationHelper()
        var lastLocateTrigger = 0
        private var lastSatellite: Bool?
        private var vehicleAnns: [String: VehicleAnnotation] = [:]
        private var stopAnns: [String: StopAnnotation] = [:]
        private var routeOverlays: [MKOverlay] = []
        private var routeAnns: [MKAnnotation] = []
        private var lastRouteKey = ""
        private var lastSelectedId: String?
        private var lastStopsKey = ""

        init(_ parent: AppleMapView) { self.parent = parent }

        // MARK: Style

        func applyStyle(_ map: MKMapView, satellite: Bool) {
            guard lastSatellite != satellite else { return }
            lastSatellite = satellite
            if satellite {
                map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
            } else {
                let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
                config.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = config
            }
        }

        // MARK: Vehicles

        private static func hex(for v: Vehicle) -> String {
            switch v.vehicleType {
            case .tram: return "#FF3B30"
            case .trolley: return "#34C759"
            case .bus: return "#007AFF"
            case .regional: return "#5856D6"
            case .night: return "#AF52DE"
            case .metro, .none: return "#FF9500"
            }
        }

        func syncVehicles(_ map: MKMapView) {
            let showVehicles = !parent.showStopsInsteadOfVehicles || parent.selectedLine != nil
            let list = showVehicles ? parent.vehicles : []
            var seen = Set<String>()
            var toAdd: [VehicleAnnotation] = []
            for v in list {
                seen.insert(v.id)
                let coordinate = CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude)
                let crowd = v.crowdedness == .high ? 2 : (v.crowdedness == .moderate ? 1 : 0)
                if let ann = vehicleAnns[v.id] {
                    let moved = abs(ann.coordinate.latitude - coordinate.latitude) > 0.000005
                        || abs(ann.coordinate.longitude - coordinate.longitude) > 0.000005
                    let before = ann.signature
                    ann.line = v.line
                    ann.colorHex = Self.hex(for: v)
                    ann.crowd = crowd
                    ann.stale = v.isTelemetryStale == true
                    if moved {
                        UIView.animate(withDuration: 0.4) { ann.coordinate = coordinate }
                    }
                    if let view = map.view(for: ann), before != ann.signature || view.image == nil {
                        configure(view, for: ann)
                    }
                } else {
                    let ann = VehicleAnnotation(
                        id: v.id, coordinate: coordinate, line: v.line, colorHex: Self.hex(for: v),
                        crowd: crowd, stale: v.isTelemetryStale == true,
                        typeName: v.vehicleType?.displayName ?? "vehicul"
                    )
                    vehicleAnns[v.id] = ann
                    toAdd.append(ann)
                }
            }
            let gone = vehicleAnns.keys.filter { !seen.contains($0) }
            if !gone.isEmpty {
                map.removeAnnotations(gone.compactMap { vehicleAnns[$0] })
                for id in gone { vehicleAnns[id] = nil }
            }
            if !toAdd.isEmpty { map.addAnnotations(toAdd) }
        }

        private func configure(_ view: MKAnnotationView, for ann: VehicleAnnotation) {
            view.image = MapImages.plate(line: ann.line, hex: ann.colorHex, ring: ann.crowd)
            view.alpha = ann.stale ? 0.55 : 1
            view.displayPriority = .required
            view.collisionMode = .none
            view.canShowCallout = false
            view.isAccessibilityElement = true
            view.accessibilityLabel = "Linia \(ann.line), \(ann.typeName)"
            view.transform = ann.id == lastSelectedId ? CGAffineTransform(scaleX: 1.18, y: 1.18) : .identity
        }

        // MARK: Selection

        func syncSelection(_ map: MKMapView) {
            let id = parent.selectedVehicle?.id
            guard id != lastSelectedId else { return }
            let previous = lastSelectedId
            lastSelectedId = id
            for key in [previous, id].compactMap({ $0 }) {
                if let ann = vehicleAnns[key], let view = map.view(for: ann) {
                    UIView.animate(withDuration: 0.18) { self.configure(view, for: ann) }
                }
            }
            if let v = parent.selectedVehicle {
                map.setRegion(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                ), animated: true)
            }
        }

        // MARK: Route

        private static func coordinates(_ path: [[Double]]?) -> [CLLocationCoordinate2D] {
            (path ?? []).compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
        }

        private static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
            let dLon = (b.longitude - a.longitude) * .pi / 180
            let y = sin(dLon) * cos(lat2)
            let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
            return atan2(y, x)
        }

        func syncRoute(_ map: MKMapView) {
            let key = parent.activeLineData.map { "\($0.line)_\(parent.lineDirection.rawValue)" } ?? ""
            guard key != lastRouteKey else { return }
            lastRouteKey = key
            map.removeOverlays(routeOverlays)
            map.removeAnnotations(routeAnns)
            routeOverlays = []
            routeAnns = []
            guard let data = parent.activeLineData else { return }

            let main = data.color ?? "#007AFF"
            var paths: [(coords: [CLLocationCoordinate2D], hex: String)] = []
            if parent.lineDirection != .retur { paths.append((Self.coordinates(data.turPath), main)) }
            if parent.lineDirection != .tur {
                paths.append((Self.coordinates(data.returPath), parent.lineDirection == .both ? "#34C759" : main))
            }

            var rect = MKMapRect.null
            for (coords, hex) in paths where coords.count > 1 {
                var c = coords
                let line = RoutePolyline(coordinates: &c, count: c.count)
                line.color = MapImages.color(hex)
                routeOverlays.append(line)
                rect = rect.union(line.boundingMapRect)
                routeAnns += arrows(along: coords, hex: hex)
            }

            let stations: [Station] = {
                switch parent.lineDirection {
                case .both: return (data.turStations ?? []) + (data.returStations ?? [])
                case .tur: return data.turStations ?? []
                case .retur: return data.returStations ?? []
                }
            }()
            for st in stations {
                routeAnns.append(StationAnnotation(
                    name: st.name,
                    coordinate: CLLocationCoordinate2D(latitude: st.lat, longitude: st.lon),
                    colorHex: main
                ))
            }

            map.addOverlays(routeOverlays, level: .aboveRoads)
            map.addAnnotations(routeAnns)
            if !rect.isNull {
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 110, left: 40, bottom: 330, right: 40), animated: true)
            }
        }

        private func arrows(along coords: [CLLocationCoordinate2D], hex: String) -> [ArrowAnnotation] {
            var cumulative: [Double] = [0]
            for i in 1..<coords.count {
                let a = MKMapPoint(coords[i - 1]), b = MKMapPoint(coords[i])
                cumulative.append(cumulative[i - 1] + a.distance(to: b))
            }
            guard let total = cumulative.last, total > 0 else { return [] }
            let metersPerPoint = MKMetersPerMapPointAtLatitude(coords[0].latitude)
            let count = min(10, max(3, Int(total * metersPerPoint / 1200)))
            var result: [ArrowAnnotation] = []
            var segment = 1
            for n in 0..<count {
                let target = total * (Double(n) + 0.5) / Double(count)
                while segment < cumulative.count - 1 && cumulative[segment] < target { segment += 1 }
                let a = coords[segment - 1], b = coords[segment]
                let span = max(cumulative[segment] - cumulative[segment - 1], 0.0001)
                let t = min(max((target - cumulative[segment - 1]) / span, 0), 1)
                let point = CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                )
                result.append(ArrowAnnotation(coordinate: point, bearing: Self.bearing(a, b), colorHex: hex))
            }
            return result
        }

        // MARK: Stops (clustered)

        func syncStops(_ map: MKMapView) {
            guard parent.showStopsInsteadOfVehicles else {
                if !stopAnns.isEmpty {
                    map.removeAnnotations(Array(stopAnns.values))
                    stopAnns = [:]
                    lastStopsKey = ""
                }
                return
            }
            let region = map.region
            guard region.span.latitudeDelta > 0 else { return }
            let pad = 1.4
            let minLat = region.center.latitude - region.span.latitudeDelta / 2 * pad
            let maxLat = region.center.latitude + region.span.latitudeDelta / 2 * pad
            let minLon = region.center.longitude - region.span.longitudeDelta / 2 * pad
            let maxLon = region.center.longitude + region.span.longitudeDelta / 2 * pad
            let line = parent.selectedLine?.uppercased()
            let wanted = parent.appState.mapStops.filter { stop in
                stop.lat >= minLat && stop.lat <= maxLat && stop.lon >= minLon && stop.lon <= maxLon
                    && (line == nil || stop.services.contains { $0.line.uppercased() == line })
            }.prefix(4000)

            var wantedIds = Set<String>()
            var toAdd: [StopAnnotation] = []
            for stop in wanted {
                wantedIds.insert(stop.id)
                if stopAnns[stop.id] == nil {
                    let ann = StopAnnotation(
                        id: stop.id, name: stop.name,
                        coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon),
                        colorHex: stop.services.first?.color ?? "#007AFF"
                    )
                    stopAnns[stop.id] = ann
                    toAdd.append(ann)
                }
            }
            let gone = stopAnns.keys.filter { !wantedIds.contains($0) }
            if !gone.isEmpty {
                map.removeAnnotations(gone.compactMap { stopAnns[$0] })
                for id in gone { stopAnns[id] = nil }
            }
            if !toAdd.isEmpty { map.addAnnotations(toAdd) }
        }

        // MARK: MKMapViewDelegate

        public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            syncStops(mapView)
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? RoutePolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.color.withAlphaComponent(0.9)
            renderer.lineWidth = 5
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation is MKClusterAnnotation { return nil }
            if let ann = annotation as? VehicleAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "vehicle")
                    ?? MKAnnotationView(annotation: ann, reuseIdentifier: "vehicle")
                view.annotation = ann
                configure(view, for: ann)
                return view
            }
            if let ann = annotation as? StopAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "stop")
                    ?? MKAnnotationView(annotation: ann, reuseIdentifier: "stop")
                view.annotation = ann
                view.image = MapImages.dot(hex: ann.colorHex)
                view.clusteringIdentifier = "stop"
                view.displayPriority = .defaultLow
                view.canShowCallout = false
                view.isAccessibilityElement = true
                view.accessibilityLabel = "Stația \(ann.name)"
                return view
            }
            if let ann = annotation as? StationAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "station")
                    ?? MKAnnotationView(annotation: ann, reuseIdentifier: "station")
                view.annotation = ann
                view.image = MapImages.dot(hex: ann.colorHex)
                view.displayPriority = .defaultHigh
                view.canShowCallout = false
                view.isAccessibilityElement = true
                view.accessibilityLabel = "Stația \(ann.name)"
                return view
            }
            if let ann = annotation as? ArrowAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "arrow")
                    ?? MKAnnotationView(annotation: ann, reuseIdentifier: "arrow")
                view.annotation = ann
                view.image = MapImages.arrow(hex: ann.colorHex)
                view.transform = CGAffineTransform(rotationAngle: ann.bearing)
                view.displayPriority = .required
                view.collisionMode = .none
                view.isEnabled = false
                view.isAccessibilityElement = false
                return view
            }
            return nil
        }

        public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            defer { mapView.deselectAnnotation(view.annotation, animated: false) }
            if let ann = view.annotation as? VehicleAnnotation,
               let v = parent.appState.vehicles.first(where: { $0.id == ann.id }) {
                parent.onVehicleTapped(v)
            } else if let ann = view.annotation as? StopAnnotation {
                parent.appState.selectStop(id: ann.id)
            } else if let ann = view.annotation as? StationAnnotation {
                parent.appState.selectStop(name: ann.name, lat: ann.coordinate.latitude, lon: ann.coordinate.longitude)
            } else if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            }
        }
    }
}
