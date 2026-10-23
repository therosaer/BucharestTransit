import SwiftUI
@preconcurrency import CoreLocation
#if canImport(WebKit)
import WebKit
#endif

public struct OpenStreetMapView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
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

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "transitBridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        context.coordinator.webView = webView

        let html = OpenStreetMapView.mapHTMLTemplate(
            isDark: colorScheme == .dark,
            mapStyle: MapTileStyle(rawValue: mapTileStyle) ?? .standard
        )
        webView.loadHTMLString(html, baseURL: nil)

        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setMapStyle(
            MapTileStyle(rawValue: mapTileStyle) ?? .standard,
            isDark: colorScheme == .dark
        )
        context.coordinator.syncSelectedLine(selectedLine, direction: lineDirection)
        context.coordinator.setDisplayMode(showStopsInsteadOfVehicles ? "stops" : "vehicles")

        if context.coordinator.lastLocateTrigger != locateTrigger {
            context.coordinator.lastLocateTrigger = locateTrigger
            context.coordinator.requestUserLocation()
        }

        if let sel = selectedVehicle, sel.id != context.coordinator.lastSelectedVehicleId {
            context.coordinator.lastSelectedVehicleId = sel.id
            webView.evaluateJavaScript("window.selectVehicle('\(sel.id)', \(sel.latitude), \(sel.longitude));", completionHandler: nil)
        }

        guard context.coordinator.isMapReady else {
            // Queue pending updates until map reports ready
            context.coordinator.pendingVehicles = vehicles
            context.coordinator.pendingLineData = activeLineData
            context.coordinator.pendingLineDirection = lineDirection
            return
        }

        context.coordinator.syncVehicles(vehicles)
        context.coordinator.syncLine(lineData: activeLineData, direction: lineDirection)
    }

    @MainActor
    public final class Coordinator: NSObject, WKScriptMessageHandler, @preconcurrency CLLocationManagerDelegate {
        var parent: OpenStreetMapView
        weak var webView: WKWebView?
        private let locationManager = CLLocationManager()
        private var locationRequestPending = false
        private var didShowLocationForPendingRequest = false
        private var pendingUserLocation: CLLocation?
        var isMapReady = false
        var pendingVehicles: [Vehicle]?
        var pendingLineData: LineDetails?
        var pendingLineDirection: LineDirection?
        var lastLocateTrigger: Int = 0
        var lastSelectedVehicleId: String? = nil
        private var lastAppliedDarkMode: Bool?
        private var lastAppliedMapStyle: MapTileStyle?
        private var lastAppliedDisplayMode: String?
        private var lastPushedSelectedLineDirection: String?
        private var didPushStops = false
        private var lastPushedVehiclesHash: Int = 0
        private var lastPushedLine: String? = nil

        init(_ parent: OpenStreetMapView) {
            self.parent = parent
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }

        func requestUserLocation() {
            locationRequestPending = true
            didShowLocationForPendingRequest = false
            switch locationManager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if let cachedLocation = locationManager.location, isRecentUsableLocation(cachedLocation) {
                    showUserLocation(cachedLocation)
                    didShowLocationForPendingRequest = true
                }
                locationManager.requestLocation()
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                locationRequestPending = false
                parent.appState.locationError = "Activează accesul la locație în Configurări pentru a-ți afișa poziția pe hartă."
            @unknown default:
                locationRequestPending = false
                parent.appState.locationError = "Starea permisiunii pentru locație nu este disponibilă."
            }
        }

        public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            guard locationRequestPending else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                locationRequestPending = false
                parent.appState.locationError = "Activează accesul la locație în Configurări pentru a-ți afișa poziția pe hartă."
            case .notDetermined:
                break
            @unknown default:
                locationRequestPending = false
                parent.appState.locationError = "Starea permisiunii pentru locație nu este disponibilă."
            }
        }

        public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last else {
                locationRequestPending = false
                parent.appState.locationError = "iPhone-ul nu a returnat o poziție."
                return
            }
            locationRequestPending = false
            didShowLocationForPendingRequest = true
            parent.appState.locationError = nil
            showUserLocation(location)
        }

        public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            locationRequestPending = false
            guard !didShowLocationForPendingRequest else { return }
            parent.appState.locationError = "Nu s-a putut obține locația: \(error.localizedDescription)"
        }

        private func isRecentUsableLocation(_ location: CLLocation) -> Bool {
            let age = Date().timeIntervalSince(location.timestamp)
            return age >= -5 && age <= 60
                && location.horizontalAccuracy >= 0
                && location.horizontalAccuracy <= 500
        }

        private func showUserLocation(_ location: CLLocation) {
            guard isMapReady else {
                pendingUserLocation = location
                return
            }
            let coordinate = location.coordinate
            let accuracy = max(0, location.horizontalAccuracy)
            webView?.evaluateJavaScript(
                "window.showUserLocation(\(coordinate.latitude), \(coordinate.longitude), \(accuracy));",
                completionHandler: nil
            )
        }

        func setMapStyle(_ style: MapTileStyle, isDark: Bool) {
            guard isMapReady else { return }
            guard lastAppliedDarkMode != isDark || lastAppliedMapStyle != style else { return }
            lastAppliedDarkMode = isDark
            lastAppliedMapStyle = style
            webView?.evaluateJavaScript(
                "window.setMapStyle('\(style.rawValue)', \(isDark));",
                completionHandler: nil
            )
        }

        func setDisplayMode(_ mode: String) {
            guard isMapReady, lastAppliedDisplayMode != mode else { return }
            lastAppliedDisplayMode = mode
            webView?.evaluateJavaScript("window.setDisplayMode('\(mode)');", completionHandler: nil)
            if mode == "stops" {
                syncStops(parent.appState.mapStops)
            }
        }

        func syncSelectedLine(_ line: String?, direction: LineDirection) {
            let directionValue: String
            switch direction {
            case .both: directionValue = "both"
            case .tur: directionValue = "tur"
            case .retur: directionValue = "retur"
            }
            let selectionKey = line.map { "\($0)_\(directionValue)" }
            guard isMapReady, lastPushedSelectedLineDirection != selectionKey, let webView else { return }

            let lineLiteral: String
            if let line {
                guard let data = try? JSONSerialization.data(withJSONObject: [line]),
                      let json = String(data: data, encoding: .utf8) else { return }
                lineLiteral = String(json.dropFirst().dropLast())
            } else {
                lineLiteral = "null"
            }

            lastPushedSelectedLineDirection = selectionKey
            webView.evaluateJavaScript("window.setSelectedLine(\(lineLiteral), '\(directionValue)');", completionHandler: nil)
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "transitBridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            if type == "ready" {
                isMapReady = true
                if let location = pendingUserLocation {
                    showUserLocation(location)
                    pendingUserLocation = nil
                }
                setMapStyle(
                    MapTileStyle(rawValue: parent.mapTileStyle) ?? .standard,
                    isDark: parent.colorScheme == .dark
                )
                syncSelectedLine(parent.selectedLine, direction: parent.lineDirection)
                setDisplayMode(parent.showStopsInsteadOfVehicles ? "stops" : "vehicles")
                if let pVeh = pendingVehicles {
                    syncVehicles(pVeh)
                    pendingVehicles = nil
                }
                if let pLine = pendingLineData, let pDir = pendingLineDirection {
                    syncLine(lineData: pLine, direction: pDir)
                    pendingLineData = nil
                    pendingLineDirection = nil
                }
            } else if type == "selectVehicle", let id = body["id"] as? String {
                if let v = parent.appState.vehicles.first(where: { $0.id == id }) {
                    DispatchQueue.main.async {
                        self.parent.onVehicleTapped(v)
                    }
                }
            } else if type == "selectStop", let id = body["id"] as? String {
                DispatchQueue.main.async {
                    self.parent.appState.selectStop(id: id)
                }
            } else if type == "selectStation",
                      let name = body["name"] as? String,
                      let lat = body["lat"] as? Double,
                      let lon = body["lon"] as? Double {
                DispatchQueue.main.async {
                    self.parent.appState.selectStop(name: name, lat: lat, lon: lon)
                }
            }
        }

        private func syncStops(_ stops: [MapStop]) {
            guard isMapReady, !didPushStops, let webView = webView else { return }
            let items: [[String: Any]] = stops.map { stop in
                [
                    "id": stop.id,
                    "name": stop.name,
                    "lat": stop.lat,
                    "lon": stop.lon,
                    "services": stop.services.map { service in
                        [
                            "line": service.line,
                            "direction": service.direction,
                            "typeName": service.typeName ?? ""
                        ]
                    }
                ]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: items),
                  let json = String(data: data, encoding: .utf8) else { return }
            didPushStops = true
            webView.evaluateJavaScript("window.updateStops(\(json));", completionHandler: nil)
        }

        func syncVehicles(_ list: [Vehicle]) {
            guard isMapReady, let webView = webView else { return }

            // Create compact payload
            var items: [[String: Any]] = []
            for v in list {
                let typeStr: String
                switch v.vehicleType {
                case .tram: typeStr = "tram"
                case .trolley: typeStr = "trolley"
                case .bus: typeStr = "bus"
                case .regional: typeStr = "regional"
                case .night: typeStr = "night"
                case .metro: typeStr = "metro"
                default: typeStr = "bus"
                }

                let crowdStr: String
                switch v.crowdedness {
                case .high: crowdStr = "high"
                case .moderate: crowdStr = "moderate"
                default: crowdStr = "low"
                }

                items.append([
                    "id": v.id,
                    "line": v.line,
                    "lat": v.coordinate.latitude,
                    "lon": v.coordinate.longitude,
                    "type": typeStr,
                    "crowded": crowdStr,
                    "stale": v.isTelemetryStale == true
                ])
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: items),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let js = "window.updateVehicles(\(jsonString));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func syncLine(lineData: LineDetails?, direction: LineDirection) {
            guard isMapReady, let webView = webView else { return }

            guard let line = lineData else {
                if lastPushedLine != nil {
                    lastPushedLine = nil
                    webView.evaluateJavaScript("window.clearRouteLines();", completionHandler: nil)
                }
                return
            }

            let lineKey = "\(line.line)_\(direction.rawValue)"
            if lastPushedLine == lineKey { return }
            lastPushedLine = lineKey

            let tur = line.turPath ?? []
            let retur = line.returPath ?? []

            var stationsList: [[String: Any]] = []
            let rawStations: [Station] = {
                switch direction {
                case .both: return (line.turStations ?? []) + (line.returStations ?? [])
                case .tur: return line.turStations ?? []
                case .retur: return line.returStations ?? []
                }
            }()

            for (idx, st) in rawStations.enumerated() {
                var item: [String: Any] = [
                    "name": st.name,
                    "code": st.id,
                    "lat": st.lat,
                    "lon": st.lon,
                    "seq": idx
                ]
                if let wd = st.scheduleWd { item["schedule_wd"] = wd }
                if let we = st.scheduleWe { item["schedule_we"] = we }
                stationsList.append(item)
            }

            guard let turData = try? JSONSerialization.data(withJSONObject: tur),
                  let turStr = String(data: turData, encoding: .utf8),
                  let returData = try? JSONSerialization.data(withJSONObject: retur),
                  let returStr = String(data: returData, encoding: .utf8),
                  let stationsData = try? JSONSerialization.data(withJSONObject: stationsList),
                  let stationsStr = String(data: stationsData, encoding: .utf8),
                  let turTerminalData = try? JSONSerialization.data(
                    withJSONObject: line.turTerminal ?? "Capăt Tur",
                    options: [.fragmentsAllowed]
                  ),
                  let turTerminal = String(data: turTerminalData, encoding: .utf8),
                  let returTerminalData = try? JSONSerialization.data(
                    withJSONObject: line.returTerminal ?? "Capăt Retur",
                    options: [.fragmentsAllowed]
                  ),
                  let returTerminal = String(data: returTerminalData, encoding: .utf8),
                  let lineTypeData = try? JSONSerialization.data(
                    withJSONObject: line.typeName ?? "",
                    options: [.fragmentsAllowed]
                  ),
                  let lineType = String(data: lineTypeData, encoding: .utf8) else { return }

            let dirMode = direction == .tur ? "tur" : (direction == .retur ? "retur" : "both")
            let js = "window.updateRouteLines(\(turStr), \(returStr), \(stationsStr), '\(dirMode)', '\(line.line)', '\(line.color ?? "#007AFF")', \(turTerminal), \(returTerminal), \(lineType));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - Embedded OpenStreetMap / Leaflet HTML Template
    private static func loadLeafletAssets() -> (css: String?, js: String?) {
        var css: String?
        var js: String?

        var candidates: [URL?] = []
        #if SWIFT_PACKAGE
        candidates.append(Bundle.module.bundleURL.appendingPathComponent("Resources/leaflet"))
        candidates.append(Bundle.module.resourceURL?.appendingPathComponent("leaflet"))
        #endif
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("BucharestTransit_BucharestTransit.bundle/Resources/leaflet"))
        candidates.append(Bundle.main.resourceURL?.appendingPathComponent("BucharestTransit_BucharestTransit.bundle/Resources/leaflet"))
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Resources/leaflet"))

        for dir in candidates {
            guard let dir = dir else { continue }
            let cssURL = dir.appendingPathComponent("leaflet.css")
            let jsURL = dir.appendingPathComponent("leaflet.js")
            if FileManager.default.fileExists(atPath: cssURL.path) && FileManager.default.fileExists(atPath: jsURL.path) {
                css = try? String(contentsOf: cssURL, encoding: .utf8)
                js = try? String(contentsOf: jsURL, encoding: .utf8)
                if css != nil && js != nil { break }
            }
        }
        return (css, js)
    }

    public static func mapHTMLTemplate(isDark: Bool, mapStyle: MapTileStyle = .standard) -> String {
        let (localCSS, localJS) = loadLeafletAssets()
        let cssBlock = localCSS.map { "<style>\($0)</style>" } ?? "<link rel=\"stylesheet\" href=\"https://unpkg.com/leaflet@1.9.4/dist/leaflet.css\" />"
        let jsBlock = localJS.map { "<script>\($0)</script>" } ?? "<script src=\"https://unpkg.com/leaflet@1.9.4/dist/leaflet.js\"></script>"

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
          \(cssBlock)
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
            html, body, #map { width: 100%; height: 100%; overflow: hidden; background: #e5e3df; }
            html.dark-map,
            html.dark-map body,
            html.dark-map #map {
              background: #15191e;
            }
            html.dark-map[data-map-style='standard'] .leaflet-tile {
              filter: brightness(0.82) invert(1) hue-rotate(180deg) saturate(0.72);
            }
            
            .vehicle-marker {
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              cursor: pointer;
            }
            .vehicle-pin {
              padding: 2.5px 7px;
              border-radius: 7px;
              font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif;
              font-size: 11px;
              font-weight: 800;
              color: #ffffff;
              box-shadow: 0 3px 8px rgba(0,0,0,0.32), 0 0 0 1.5px rgba(255,255,255,0.95);
              letter-spacing: -0.02em;
              white-space: nowrap;
              text-align: center;
            }
            .vehicle-pin.selected {
              transform: scale(1.22);
              box-shadow: 0 5px 14px rgba(0,0,0,0.45), 0 0 0 2.5px #ffffff, 0 0 12px rgba(0,122,255,0.8);
            }
            .vehicle-pin.crowded-high {
              box-shadow: 0 0 0 3px rgba(255,59,48,0.9), 0 3px 8px rgba(0,0,0,0.32);
            }
            .vehicle-pin.crowded-mod {
              box-shadow: 0 0 0 2px rgba(255,149,0,0.85), 0 3px 8px rgba(0,0,0,0.32);
            }
            .vehicle-pin.stale {
              opacity: 0.55;
            }
            .vehicle-pointer {
              width: 0;
              height: 0;
              border-left: 4px solid transparent;
              border-right: 4px solid transparent;
              border-top: 5px solid currentColor;
              margin-top: -1px;
            }
            .station-marker {
              width: 13px;
              height: 13px;
              border-radius: 50%;
              background: #ffffff;
              border: 2.5px solid #007AFF;
              box-shadow: 0 2px 6px rgba(0,0,0,0.3);
              cursor: pointer;
              transition: transform 0.2s ease;
            }
            .station-marker:hover, .station-marker:active {
              transform: scale(1.35);
            }
            .stop-cluster {
              display: flex;
              width: 34px;
              height: 34px;
              align-items: center;
              justify-content: center;
              border: 2.5px solid #ffffff;
              border-radius: 50%;
              box-shadow: 0 2px 7px rgba(0,0,0,0.35);
              color: #ffffff;
              font: 700 13px -apple-system, BlinkMacSystemFont, sans-serif;
              cursor: pointer;
            }
            .apple-station-popup .leaflet-popup-content-wrapper {
              background: rgba(255, 255, 255, 0.96) !important;
              backdrop-filter: blur(25px) saturate(180%);
              -webkit-backdrop-filter: blur(25px) saturate(180%);
              border-radius: 18px !important;
              box-shadow: 0 12px 36px rgba(0, 0, 0, 0.22), 0 0 0 0.5px rgba(0, 0, 0, 0.08) !important;
              padding: 6px !important;
            }
            html.dark-map .apple-station-popup .leaflet-popup-content-wrapper,
            html.dark-map .apple-station-popup .leaflet-popup-tip {
              background: rgba(35, 39, 45, 0.97) !important;
              color: #f2f2f7 !important;
            }
            html.dark-map .apple-station-popup strong,
            html.dark-map .apple-station-popup div {
              color: #f2f2f7 !important;
            }
            .apple-station-popup .leaflet-popup-tip {
              background: rgba(255, 255, 255, 0.96) !important;
            }
            .leaflet-control-attribution {
              font-size: 9px !important;
              background: rgba(255,255,255,0.7) !important;
              backdrop-filter: blur(8px);
              border-radius: 6px;
              margin: 4px !important;
              padding: 2px 6px !important;
            }
          </style>
          \(jsBlock)
        </head>
        <body>
          <div id="map"></div>
      <script>
        var map = L.map('map', {
          center: [44.4361, 26.1027],
          zoom: 13,
          minZoom: 10,
          maxZoom: 19,
          zoomControl: false,
          doubleClickZoom: false
        });

        var lastMapTap = null;
        var currentMapTap = null;
        var zoomDrag = null;
        var mapContainer = map.getContainer();

        function finishZoomDrag() {
          if (!zoomDrag || !zoomDrag.active) {
            zoomDrag = null;
            currentMapTap = null;
            return;
          }

          if (zoomDrag.wasDraggingEnabled) map.dragging.enable();
          map.options.zoomSnap = zoomDrag.zoomSnap;
          zoomDrag = null;
          currentMapTap = null;
        }

        mapContainer.addEventListener('touchstart', function(event) {
          if (event.touches.length !== 1) {
            currentMapTap = null;
            zoomDrag = null;
            return;
          }

          var touch = event.touches[0];
          var point = { x: touch.clientX, y: touch.clientY };
          var isDoubleTap = lastMapTap &&
            event.timeStamp - lastMapTap.time <= 350 &&
            Math.hypot(point.x - lastMapTap.x, point.y - lastMapTap.y) <= 28;

          currentMapTap = { point: point, moved: false };
          zoomDrag = isDoubleTap ? {
            start: point,
            zoom: map.getZoom(),
            anchor: map.containerPointToLatLng(L.point(
              point.x - mapContainer.getBoundingClientRect().left,
              point.y - mapContainer.getBoundingClientRect().top
            )),
            active: false,
            wasDraggingEnabled: false,
            zoomSnap: map.options.zoomSnap
          } : null;
        }, { capture: true, passive: true });

        mapContainer.addEventListener('touchmove', function(event) {
          if (event.touches.length !== 1) return;

          var touch = event.touches[0];
          if (currentMapTap &&
              Math.hypot(touch.clientX - currentMapTap.point.x, touch.clientY - currentMapTap.point.y) > 10) {
            currentMapTap.moved = true;
          }
          if (!zoomDrag) return;

          var deltaX = touch.clientX - zoomDrag.start.x;
          var deltaY = touch.clientY - zoomDrag.start.y;
          if (!zoomDrag.active) {
            if (Math.abs(deltaY) <= 8 || Math.abs(deltaY) <= Math.abs(deltaX)) {
              if (Math.abs(deltaX) > 8) zoomDrag = null;
              return;
            }

            zoomDrag.active = true;
            zoomDrag.wasDraggingEnabled = map.dragging.enabled();
            if (zoomDrag.wasDraggingEnabled) map.dragging.disable();
            map.options.zoomSnap = 0;
          }

          event.preventDefault();
          event.stopPropagation();
          map.setZoomAround(zoomDrag.anchor, zoomDrag.zoom - deltaY / 120, { animate: false });
        }, { capture: true, passive: false });

        mapContainer.addEventListener('touchend', function(event) {
          if (zoomDrag && zoomDrag.active) {
            event.preventDefault();
            event.stopPropagation();
            finishZoomDrag();
            lastMapTap = null;
            return;
          }

          if (zoomDrag && currentMapTap && !currentMapTap.moved) {
            event.preventDefault();
            event.stopPropagation();
            map.setZoomAround(zoomDrag.anchor, zoomDrag.zoom + 1);
            finishZoomDrag();
            lastMapTap = null;
            return;
          }

          if (currentMapTap && !currentMapTap.moved && event.changedTouches.length === 1) {
            lastMapTap = {
              time: event.timeStamp,
              x: currentMapTap.point.x,
              y: currentMapTap.point.y
            };
          } else {
            lastMapTap = null;
          }
          finishZoomDrag();
        }, { capture: true, passive: false });

        mapContainer.addEventListener('touchcancel', finishZoomDrag, { capture: true });

        var baseTileLayer = null;
        window.setMapStyle = function(style, isDark) {
          if (baseTileLayer) {
            map.removeLayer(baseTileLayer);
          }
          var tileOptions;
          switch (style) {
            case 'satellite':
              tileOptions = {
                url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                attribution: 'Tiles &copy; Esri — Sources: Esri, Maxar, Earthstar Geographics, and the GIS User Community',
                maxZoom: 19
              };
              break;
            case 'terrain':
              tileOptions = {
                url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
                attribution: 'Map data: &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, SRTM | Map style: &copy; <a href="https://opentopomap.org">OpenTopoMap</a>',
                maxZoom: 17,
                subdomains: 'abc'
              };
              break;
            case 'light':
              tileOptions = {
                url: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
                maxZoom: 20,
                subdomains: 'abcd'
              };
              break;
            case 'dark':
              tileOptions = {
                url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
                maxZoom: 20,
                subdomains: 'abcd'
              };
              break;
            default:
              style = 'standard';
              tileOptions = {
                url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
                maxZoom: 19
              };
          }
          document.documentElement.dataset.mapStyle = style;
          document.documentElement.classList.toggle('dark-map', isDark);
          baseTileLayer = L.tileLayer(tileOptions.url, tileOptions).addTo(map);
        };
        window.setMapStyle('\(mapStyle.rawValue)', \(isDark));

        var vehicleMarkers = new Map();
        var stopMarkers = new Map();
        var allStops = [];
        var vehicleMarkerLayer = L.layerGroup().addTo(map);
        var stopMarkerLayer = L.layerGroup();
        var stopClusters = [];
        var stopCanvasRenderer = L.canvas({ padding: 0.5 });
        var routeStationLayer = L.layerGroup().addTo(map);
        var turRouteLayer = null;
        var returRouteLayer = null;
        var stationMarkers = [];
        var routeDirectionMarkers = [];
        var routeDirectionMarkers = [];
        var selectedVehicleId = null;
        var displayMode = 'vehicles';
        var selectedLine = null;
        var selectedLineDirection = 'both';

        function getStopMarkerColor(service) {
          var typeName = (service && service.typeName || '').toLowerCase();
          var line = (service && service.line || '').trim().toUpperCase();
          if (typeName.indexOf('metr') !== -1 || line.indexOf('M') === 0) return '#007AFF';
          if (typeName.indexOf('tram') !== -1) return '#34C759';
          return '#FF3B30';
        }

        function getStopCategory(service) {
          var typeName = (service && service.typeName || '').toLowerCase();
          var line = (service && service.line || '').trim().toUpperCase();
          if (typeName.indexOf('metr') !== -1 || line.indexOf('M') === 0) return 'metro';
          if (typeName.indexOf('tram') !== -1) return 'tram';
          return 'bus';
        }

        function updateVisibleStops() {
          if (displayMode !== 'stops') return;

          var bounds = map.getBounds().pad(0.2);
          var visibleIds = new Set();
          var visibleStops = [];
          stopClusters.forEach(function(cluster) { stopMarkerLayer.removeLayer(cluster); });
          stopClusters = [];
          allStops.forEach(function(st) {
            var services = Array.isArray(st.services) ? st.services : [];
            var service = selectedLine
              ? services.find(function(candidate) {
                  var lineMatches = (candidate.line || '').trim().toUpperCase() === selectedLine;
                  var directionMatches = selectedLineDirection === 'both' ||
                    (candidate.direction || '').trim().toLowerCase() === selectedLineDirection;
                  return lineMatches && directionMatches;
                })
              : services[0];
            if (selectedLine && !service) return;
            if (!bounds.contains([st.lat, st.lon])) return;
            visibleIds.add(st.id);
            var markerColor = getStopMarkerColor(service);
            var marker = stopMarkers.get(st.id);
            if (!marker) {
              marker = L.circleMarker([st.lat, st.lon], {
                renderer: stopCanvasRenderer,
                radius: 6,
                color: markerColor,
                weight: 2.5,
                fillColor: '#ffffff',
                fillOpacity: 1
              });
              marker.on('click', function() {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.transitBridge) {
                  window.webkit.messageHandlers.transitBridge.postMessage({
                    type: 'selectStop',
                    id: st.id
                  });
                }
              });
              stopMarkers.set(st.id, marker);
            } else {
              marker.setStyle({ color: markerColor });
            }
            visibleStops.push({
              stop: st,
              marker: marker,
              color: markerColor,
              category: getStopCategory(service),
              point: map.latLngToLayerPoint([st.lat, st.lon])
            });
          });

          stopMarkers.forEach(function(marker, id) {
            if (!visibleIds.has(id)) {
              stopMarkerLayer.removeLayer(marker);
              stopMarkers.delete(id);
            }
          });

          if (map.getZoom() >= 18) {
            visibleStops.forEach(function(item) { stopMarkerLayer.addLayer(item.marker); });
            return;
          }

          var grid = new Map();
          var groups = [];
          var clusterDistance = 32;
          visibleStops.forEach(function(item) {
            var gridX = Math.floor(item.point.x / clusterDistance);
            var gridY = Math.floor(item.point.y / clusterDistance);
            var matchingGroup = null;
            for (var x = gridX - 1; x <= gridX + 1; x++) {
              for (var y = gridY - 1; y <= gridY + 1; y++) {
                var nearby = grid.get(item.category + ':' + x + ':' + y) || [];
                for (var i = 0; i < nearby.length; i++) {
                  var candidateGroup = groups[nearby[i]];
                  var dx = item.point.x - candidateGroup.anchor.x;
                  var dy = item.point.y - candidateGroup.anchor.y;
                  if (dx * dx + dy * dy <= clusterDistance * clusterDistance) {
                    matchingGroup = candidateGroup;
                    break;
                  }
                }
                if (matchingGroup) break;
              }
            }
            if (matchingGroup) {
              matchingGroup.members.push(item);
              return;
            }

            var groupIndex = groups.length;
            groups.push({ category: item.category, anchor: item.point, members: [item] });
            var key = item.category + ':' + gridX + ':' + gridY;
            if (!grid.has(key)) grid.set(key, []);
            grid.get(key).push(groupIndex);
          });

          groups.forEach(function(group) {
            if (group.members.length < 2) {
              group.members.forEach(function(item) {
                if (!stopMarkerLayer.hasLayer(item.marker)) stopMarkerLayer.addLayer(item.marker);
              });
              return;
            }

            group.members.forEach(function(item) { stopMarkerLayer.removeLayer(item.marker); });
            var clusterBounds = L.latLngBounds(group.members.map(function(item) {
              return [item.stop.lat, item.stop.lon];
            }));
            var cluster = L.marker(clusterBounds.getCenter(), {
              icon: L.divIcon({
                className: 'custom-stop-cluster',
                html: '<div class="stop-cluster" style="background-color:' + group.members[0].color + ';">' + group.members.length + '</div>',
                iconSize: [34, 34],
                iconAnchor: [17, 17]
              })
            }).addTo(stopMarkerLayer);
            cluster.on('click', function() {
              map.setView(clusterBounds.getCenter(), Math.min(map.getMaxZoom() || 20, map.getZoom() + 2), {
                animate: true
              });
            });
            stopClusters.push(cluster);
          });
        }

        map.on('moveend zoomend', updateVisibleStops);

        window.setDisplayMode = function(mode) {
          displayMode = mode === 'stops' ? 'stops' : 'vehicles';
          if (displayMode === 'stops') {
            if (selectedLine) {
              if (!map.hasLayer(vehicleMarkerLayer)) vehicleMarkerLayer.addTo(map);
            } else if (map.hasLayer(vehicleMarkerLayer)) {
              map.removeLayer(vehicleMarkerLayer);
            }
            if (map.hasLayer(routeStationLayer)) map.removeLayer(routeStationLayer);
            if (!map.hasLayer(stopMarkerLayer)) stopMarkerLayer.addTo(map);
            updateVisibleStops();
          } else {
            if (map.hasLayer(stopMarkerLayer)) map.removeLayer(stopMarkerLayer);
            if (!map.hasLayer(vehicleMarkerLayer)) vehicleMarkerLayer.addTo(map);
            if (!map.hasLayer(routeStationLayer)) routeStationLayer.addTo(map);
            stopMarkerLayer.clearLayers();
            stopClusters = [];
            stopMarkers.clear();
          }
        };

        function getPinColor(type) {
          switch(type) {
            case 'tram': return '#FF3B30';
            case 'trolley': return '#34C759';
            case 'bus': return '#007AFF';
            case 'regional': return '#5856D6';
            case 'night': return '#AF52DE';
            default: return '#007AFF';
          }
        }

        function createMarkerHtml(v, isSelected) {
          var color = getPinColor(v.type);
          var selClass = isSelected ? ' selected' : '';
          var crowdClass = v.crowded === 'high' ? ' crowded-high' : (v.crowded === 'moderate' ? ' crowded-mod' : '');
          var staleClass = v.stale ? ' stale' : '';
          return '<div class="vehicle-marker">' +
                   '<div class="vehicle-pin' + selClass + crowdClass + staleClass + '" style="background:' + color + ';">' + v.line + '</div>' +
                   '<div class="vehicle-pointer" style="color:' + color + ';"></div>' +
                 '</div>';
        }

        var currentVehiclesList = [];
        var currentLineName = '';
        var currentLineColor = '#007AFF';

        function getDistanceKm(lat1, lon1, lat2, lon2) {
          var R = 6371;
          var dLat = (lat2 - lat1) * Math.PI / 180;
          var dLon = (lon2 - lon1) * Math.PI / 180;
          var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                  Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                  Math.sin(dLon/2) * Math.sin(dLon/2);
          var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
          return R * c;
        }

        function calculateArrivalsForStation(st, lineName) {
          var now = new Date();
          var curH = now.getHours();
          var curM = now.getMinutes();
          var nowMinutes = curH * 60 + curM;
          var isWeekend = (now.getDay() === 0 || now.getDay() === 6);

          var schedStr = (isWeekend ? st.schedule_we : st.schedule_wd) || st.schedule_wd || st.schedule_we || '';
          var allDepartures = schedStr ? schedStr.split(',').filter(Boolean) : [];

          var upcomingScheduled = [];
          for (var i = 0; i < allDepartures.length; i++) {
            var parts = allDepartures[i].split(':');
            if (parts.length === 2) {
              var depH = parseInt(parts[0], 10);
              var depM = parseInt(parts[1], 10);
              var depMin = depH * 60 + depM;
              if (depMin >= nowMinutes) {
                upcomingScheduled.push({
                  time: allDepartures[i],
                  diffMin: depMin - nowMinutes
                });
              }
            }
          }

          var liveClose = null;
          var minD = Infinity;
          for (var j = 0; j < currentVehiclesList.length; j++) {
            var v = currentVehiclesList[j];
            if (lineName && v.line.toUpperCase() !== lineName.toUpperCase()) continue;
            var d = getDistanceKm(v.lat, v.lon, st.lat, st.lon);
            if (d < minD) {
              minD = d;
              liveClose = { vehicle: v, distKm: d };
            }
          }

          return {
            stName: st.name,
            totalToday: allDepartures.length,
            allDepartures: allDepartures,
            upcoming: upcomingScheduled,
            liveClose: liveClose,
            isWeekend: isWeekend
          };
        }

        function createStationPopupHtml(st, lineName, lineColor, data) {
          var color = lineColor || '#007AFF';
          var lineBadge = lineName ? '<span style="background:' + color + '; color:#fff; font-size:11px; font-weight:800; padding:2px 7px; border-radius:6px; margin-right:6px;">' + lineName + '</span>' : '';
          
          var bodyHtml = '';
          var hasLiveNear = data.liveClose && data.liveClose.distKm < 0.25;

          if (hasLiveNear) {
            bodyHtml += '<div style="margin-top:8px; display:flex; align-items:center; justify-content:space-between; background:rgba(52,199,89,0.12); padding:8px 10px; border-radius:10px; border:1px solid rgba(52,199,89,0.25);">' +
                          '<div>' +
                            '<div style="font-size:14px; font-weight:800; color:#34C759;">🟢 Sosește acum în stație</div>' +
                            '<div style="font-size:10px; color:#555; margin-top:1px;">Vehicul detectat prin GPS la <strong>' + Math.round(data.liveClose.distKm * 1000) + ' m</strong></div>' +
                          '</div>' +
                        '</div>';
          } else if (data.upcoming.length > 0) {
            var next = data.upcoming[0];
            var timeTitle = next.diffMin === 0 ? "Plecare imediată (" + next.time + ")" : (next.diffMin === 1 ? "În 1 min (la " + next.time + ")" : "În " + next.diffMin + " min (la " + next.time + ")");
            
            bodyHtml += '<div style="margin-top:8px; background:rgba(0,122,255,0.08); padding:8px 10px; border-radius:10px; border:1px solid rgba(0,122,255,0.18);">' +
                          '<div style="display:flex; justify-content:space-between; align-items:center;">' +
                            '<div style="font-size:14px; font-weight:800; color:#007AFF;">⏱️ ' + timeTitle + '</div>' +
                            '<span style="font-size:9px; font-weight:700; color:#555; background:rgba(255,255,255,0.85); padding:2px 6px; border-radius:4px;">ORAR OFICIAL</span>' +
                          '</div>';

            if (data.upcoming.length > 1) {
              var pills = data.upcoming.slice(1, 5).map(function(u) {
                return '<span style="display:inline-block; font-size:11px; font-weight:700; color:#007AFF; background:rgba(0,122,255,0.12); padding:2px 6px; border-radius:5px; margin-right:4px; margin-top:4px;">' + u.time + '</span>';
              }).join('');
              bodyHtml += '<div style="margin-top:6px; font-size:10px; color:#666;">Următoarele curse:</div><div style="margin-top:2px;">' + pills + '</div>';
            }
            bodyHtml += '</div>';
          } else if (data.allDepartures.length > 0) {
            var firstTomorrow = data.allDepartures[0];
            bodyHtml += '<div style="margin-top:8px; font-size:12px; color:#555; background:rgba(0,0,0,0.04); padding:7px 10px; border-radius:8px;">' +
                          '🌙 Cursele s-au încheiat pentru azi.<br>Prima plecare mâine la <strong>' + firstTomorrow + '</strong>' +
                        '</div>';
          } else {
            bodyHtml += '<div style="margin-top:8px; font-size:12px; color:#555; background:rgba(0,0,0,0.04); padding:7px 10px; border-radius:8px;">' +
                          '⏱️ Frecvență estimată: <strong>~4-7 min</strong>' +
                        '</div>';
          }

          var dayTypeStr = data.isWeekend ? 'Weekend' : 'Luni - Vineri';
          var totalInfo = data.totalToday > 0 ? '<div style="margin-top:6px; font-size:10px; color:#888; text-align:right;">Orar ' + dayTypeStr + ' • ' + data.totalToday + ' curse/zi</div>' : '';

          return '<div style="min-width:210px; max-width:270px; padding:2px 0; font-family:-apple-system, BlinkMacSystemFont, system-ui, sans-serif;">' +
                   '<div style="font-size:10px; font-weight:700; color:#888; text-transform:uppercase; letter-spacing:0.5px; margin-bottom:3px;">STAȚIE TRANZIT</div>' +
                   '<div style="display:flex; align-items:center;">' +
                     lineBadge +
                     '<strong style="font-size:14px; color:#111; font-weight:700;">' + st.name + '</strong>' +
                   '</div>' +
                   bodyHtml +
                   totalInfo +
                 '</div>';
        }

        window.updateVehicles = function(vehiclesJson) {
          try {
            var vehicles = typeof vehiclesJson === 'string' ? JSON.parse(vehiclesJson) : vehiclesJson;
            currentVehiclesList = vehicles;
            var activeIds = new Set();

            vehicles.forEach(function(v) {
              activeIds.add(v.id);
              var isSel = (v.id === selectedVehicleId);
              var latlng = [v.lat, v.lon];

              if (vehicleMarkers.has(v.id)) {
                var marker = vehicleMarkers.get(v.id);
                marker.setLatLng(latlng);
                var icon = L.divIcon({
                  className: 'custom-vehicle-icon',
                  html: createMarkerHtml(v, isSel),
                  iconSize: [40, 26],
                  iconAnchor: [20, 26]
                });
                marker.setIcon(icon);
              } else {
                var icon = L.divIcon({
                  className: 'custom-vehicle-icon',
                  html: createMarkerHtml(v, isSel),
                  iconSize: [40, 26],
                  iconAnchor: [20, 26]
                });
                var marker = L.marker(latlng, { icon: icon }).addTo(vehicleMarkerLayer);
                marker.on('click', function() {
                  selectedVehicleId = v.id;
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.transitBridge) {
                    window.webkit.messageHandlers.transitBridge.postMessage({ type: 'selectVehicle', id: v.id });
                  }
                });
                vehicleMarkers.set(v.id, marker);
              }
            });

            vehicleMarkers.forEach(function(marker, id) {
              if (!activeIds.has(id)) {
                vehicleMarkerLayer.removeLayer(marker);
                vehicleMarkers.delete(id);
              }
            });
          } catch(e) {
            console.error("Error updating vehicles:", e);
          }
        };

        window.selectVehicle = function(vehicleId, lat, lon) {
          selectedVehicleId = vehicleId;
          if (lat && lon) {
            map.flyTo([lat, lon], Math.max(map.getZoom(), 15), { duration: 0.5 });
          }
        };

        window.updateStops = function(stopsJson) {
          try {
            allStops = typeof stopsJson === 'string' ? JSON.parse(stopsJson) : stopsJson;
            updateVisibleStops();
          } catch(e) {
            console.error("Error updating stops:", e);
          }
        };

        window.setSelectedLine = function(line, direction) {
          selectedLine = line ? String(line).trim().toUpperCase() : null;
          selectedLineDirection = direction || 'both';
          if (displayMode === 'stops') {
            if (selectedLine) {
              if (!map.hasLayer(vehicleMarkerLayer)) vehicleMarkerLayer.addTo(map);
            } else if (map.hasLayer(vehicleMarkerLayer)) {
              map.removeLayer(vehicleMarkerLayer);
            }
          }
          updateVisibleStops();
        };

        window.updateRouteLines = function(turCoords, returCoords, stations, directionMode, lineName, lineColor, turTerminal, returTerminal, lineType) {
          currentLineName = lineName || '';
          currentLineColor = lineColor || '#007AFF';
          if (turRouteLayer) { map.removeLayer(turRouteLayer); turRouteLayer = null; }
          if (returRouteLayer) { map.removeLayer(returRouteLayer); returRouteLayer = null; }
          stationMarkers.forEach(function(m) { routeStationLayer.removeLayer(m); });
          stationMarkers = [];
          routeDirectionMarkers.forEach(function(m) { map.removeLayer(m); });
          routeDirectionMarkers = [];

          var boundsCoords = [];

          var routeColor = currentLineColor;
          var stopColor = getStopMarkerColor({ line: lineName, typeName: lineType });
          if ((directionMode === 'both' || directionMode === 'tur') && turCoords && turCoords.length > 0) {
            turRouteLayer = L.polyline(turCoords, { color: routeColor, weight: 5, opacity: 0.9, lineJoin: 'round' }).addTo(map);
            boundsCoords = boundsCoords.concat(turCoords);
            addRouteDirectionMarker(turCoords, 'Tur → ' + (turTerminal || 'Capăt Tur'), routeColor);
          }
          if ((directionMode === 'both' || directionMode === 'retur') && returCoords && returCoords.length > 0) {
            var returColor = (directionMode === 'both') ? '#34C759' : routeColor;
            returRouteLayer = L.polyline(returCoords, { color: returColor, weight: 5, opacity: 0.9, lineJoin: 'round' }).addTo(map);
            boundsCoords = boundsCoords.concat(returCoords);
            addRouteDirectionMarker(returCoords, 'Retur → ' + (returTerminal || 'Capăt Retur'), returColor);
          }

          if (stations && stations.length > 0) {
            stations.forEach(function(st) {
              var icon = L.divIcon({
                className: 'custom-station-icon',
                html: '<div class="station-marker" style="border-color:' + stopColor + ';"></div>',
                iconSize: [13, 13],
                iconAnchor: [6.5, 6.5]
              });
              var sm = L.marker([st.lat, st.lon], { icon: icon }).addTo(routeStationLayer);

              sm.on('click', function() {
                var data = calculateArrivalsForStation(st, currentLineName);
                var popupHtml = createStationPopupHtml(st, currentLineName, currentLineColor, data);
                sm.bindPopup(popupHtml, { offset: [0, -8], closeButton: false, className: 'apple-station-popup' }).openPopup();

                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.transitBridge) {
                  window.webkit.messageHandlers.transitBridge.postMessage({
                    type: 'selectStation',
                    name: st.name,
                    lat: st.lat,
                    lon: st.lon,
                    line: currentLineName
                  });
                }
              });

              stationMarkers.push(sm);
            });
          }

          if (boundsCoords.length > 0) {
            map.fitBounds(L.polyline(boundsCoords).getBounds(), { padding: [60, 60], maxZoom: 15 });
          }
        };

        function addRouteDirectionMarker(coords, label, color) {
          if (!coords || coords.length < 2) return;
          var end = coords[coords.length - 1];
          var markerInterval = 1000;
          var nextMarkerDistance = markerInterval / 2;
          var distanceAlongRoute = 0;

          function segmentDistance(a, b) {
            var lat1 = a[0] * Math.PI / 180;
            var lat2 = b[0] * Math.PI / 180;
            var deltaLat = lat2 - lat1;
            var deltaLon = (b[1] - a[1]) * Math.PI / 180;
            var h = Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2) +
              Math.cos(lat1) * Math.cos(lat2) *
              Math.sin(deltaLon / 2) * Math.sin(deltaLon / 2);
            return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
          }

          function segmentBearing(a, b) {
            var lat1 = a[0] * Math.PI / 180;
            var lat2 = b[0] * Math.PI / 180;
            var deltaLon = (b[1] - a[1]) * Math.PI / 180;
            var y = Math.sin(deltaLon) * Math.cos(lat2);
            var x = Math.cos(lat1) * Math.sin(lat2) -
              Math.sin(lat1) * Math.cos(lat2) * Math.cos(deltaLon);
            return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
          }

          function addArrow(point, bearing, terminalLabel) {
            var icon = L.divIcon({
              className: 'route-direction-icon',
              html: '<span style="display:block;color:' + color + ';font-size:' +
                (terminalLabel ? '25' : '20') +
                'px;line-height:25px;text-shadow:0 1px 3px #fff;transform:rotate(' +
                bearing + 'deg);">▲</span>',
              iconSize: [25, 25],
              iconAnchor: [12, 12]
            });
            var marker = L.marker(point, { icon: icon, interactive: Boolean(terminalLabel) }).addTo(map);
            if (terminalLabel) {
              marker.bindTooltip(terminalLabel, {
                permanent: true,
                direction: 'top',
                offset: [0, -10],
                className: 'route-direction-label'
              });
            }
            routeDirectionMarkers.push(marker);
          }

          for (var i = 1; i < coords.length; i++) {
            var start = coords[i - 1];
            var finish = coords[i];
            var segmentLength = segmentDistance(start, finish);
            if (segmentLength <= 0) continue;
            var bearing = segmentBearing(start, finish);
            while (nextMarkerDistance <= distanceAlongRoute + segmentLength) {
              var fraction = (nextMarkerDistance - distanceAlongRoute) / segmentLength;
              var point = [
                start[0] + (finish[0] - start[0]) * fraction,
                start[1] + (finish[1] - start[1]) * fraction
              ];
              addArrow(point, bearing, null);
              nextMarkerDistance += markerInterval;
            }
            distanceAlongRoute += segmentLength;
          }

          var finalBearing = segmentBearing(coords[coords.length - 2], end);
          var marker = L.marker(end, {
            icon: L.divIcon({
              className: 'route-direction-icon',
              html: '<span style="display:block;color:' + color + ';font-size:25px;line-height:25px;text-shadow:0 1px 3px #fff;transform:rotate(' + finalBearing + 'deg);">▲</span>',
              iconSize: [25, 25],
              iconAnchor: [12, 12]
            }),
            interactive: true
          }).addTo(map);
          marker.bindTooltip(label, {
            permanent: true,
            direction: 'top',
            offset: [0, -10],
            className: 'route-direction-label'
          });
          routeDirectionMarkers.push(marker);
        }

        window.clearRouteLines = function() {
          if (turRouteLayer) { map.removeLayer(turRouteLayer); turRouteLayer = null; }
          if (returRouteLayer) { map.removeLayer(returRouteLayer); returRouteLayer = null; }
          stationMarkers.forEach(function(m) { routeStationLayer.removeLayer(m); });
          stationMarkers = [];
          routeDirectionMarkers.forEach(function(m) { map.removeLayer(m); });
          routeDirectionMarkers = [];
        };

        var userLocationMarker = null;
        var userAccuracyCircle = null;
        window.showUserLocation = function(lat, lon, accuracy) {
          var location = [lat, lon];
          if (userAccuracyCircle) map.removeLayer(userAccuracyCircle);
          if (userLocationMarker) map.removeLayer(userLocationMarker);
          if (accuracy > 0) {
            userAccuracyCircle = L.circle(location, {
              radius: accuracy,
              color: '#007AFF',
              weight: 1,
              fillColor: '#007AFF',
              fillOpacity: 0.12
            }).addTo(map);
          }
          userLocationMarker = L.circleMarker(location, {
            radius: 8,
            color: '#ffffff',
            weight: 3,
            fillColor: '#007AFF',
            fillOpacity: 1
          }).addTo(map);
          userLocationMarker.bindTooltip('Locația ta');
          map.flyTo(location, Math.max(map.getZoom(), 15), { duration: 0.6 });
        };

        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.transitBridge) {
          window.webkit.messageHandlers.transitBridge.postMessage({ type: 'ready' });
        }
      </script>
    </body>
    </html>
    """
    }
}
