# BucharestTransit — System Architecture & Data Flow

This document details the internal systems, data schemas, and runtime lifecycles of the BucharestTransit iOS application.

---

## 1. High-Level Architecture

The app is built as a 100% on-device client with no mandatory cloud proxy. It talks directly to public STB / TPBI endpoints and embeds all static route geometries and GTFS timetables locally.

```
                    ┌───────────────────────────┐
                    │  Bucharest Transit Client │
                    └─────────────┬─────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
┌──────────────────┐    ┌──────────────────┐     ┌──────────────────┐
│ STB Live API     │    │ Local GTFS Index │     │ Leaflet Engine   │
│ (GPS telemetry)  │    │ (Timetables)     │     │ (WKWebView OSM)  │
└──────────────────┘    └──────────────────┘     └──────────────────┘
```

---

## 2. Data Sources & Storage

### A. GTFS Static Timetables (`Resources/line_routes_index.json`)
* **Size**: ~18.8 MB
* **Contents**: 201 public transit lines (buses, trams, trolleys, metro).
* **Station Schema**:
  ```json
  {
    "id": "10023",
    "name": "Piața Romană",
    "lat": 44.4447,
    "lng": 26.0975,
    "schedule_wd": ["05:12", "05:25", "05:38", "05:50", "06:02", "06:14", ...],
    "schedule_we": ["05:30", "05:50", "06:10", "06:30", ...]
  }
  ```
  - `schedule_wd`: Weekday departure timestamps (sorted, 24-hour format).
  - `schedule_we`: Weekend departure timestamps (Saturday/Sunday).
* **Parsing**: Handled by `LocalTransitDataManager.swift`. Loaded once into memory on app launch.

### B. Route Geometries (`Resources/routes_map.json`)
* **Contents**: Encoded polyline coordinates for every line in both directions (Tur and Retur).
* Used by Leaflet in `OpenStreetMapView.swift` to render transit lines on top of OpenStreetMap tiles.

### C. Live Fleet Telemetry (`TransitAPIService.swift`)
* **Target**: STB / mo-bi API (`https://api.stb.ro` / open data endpoints).
* **Payload**: Vehicle ID, Route Number, Latitude, Longitude, Heading/Bearing, Speed, Delay (seconds), AC Status.
* **Polling Interval**: Every 8–10 seconds.
* **Offline Fallback**: If the device loses internet or the STB endpoint times out, the service loads `Resources/snapshot_vehicles.json` with dead-reckoning extrapolation so the UI never crashes or displays a blank screen.

---

## 3. The Arrival Estimation Engine

Rather than using crude Euclidean distance, station arrivals rely on exact GTFS schedules with live adjustments:

1. **Station Tapped**: User taps a station pin or views a station in the Line Explorer.
2. **Current Time Resolution**:
   - `Calendar.current` resolves the day of the week in `Europe/Bucharest`.
   - If Saturday/Sunday: selects `schedule_we`.
   - If Monday–Friday: selects `schedule_wd`.
3. **Filtering**:
   - Compares departure strings (`HH:mm`) against `currentTime` (`HH * 60 + MM`).
   - Finds the first departure `minDiff >= 0`.
4. **Display Logic**:
   - If `minDiff == 0`: `"Pleacă acum"`
   - If `minDiff < 60`: `"⏱️ În \(minDiff) min (la \(timeStr))"`
   - If `minDiff >= 60`: `"la \(timeStr)"`
5. **Upcoming Departures**:
   - Takes the next 4 departure times and renders them as horizontal pills.
6. **Station Presence Detection**:
   - If `userLocation` is available and distance to station is `< 250m`, appends `● Ești în stație`.

---

## 4. Map & Rendering Optimizations (`OpenStreetMapView.swift`)

Because rendering thousands of vehicles and station markers on mobile can throttle GPU performance:
1. **Marker Capping**:
   - Only the **75 nearest vehicles** relative to the map viewport center are drawn on the DOM at any given moment.
   - Off-screen vehicles are culled from DOM elements to prevent memory leaks and frame drops.
2. **Offline Assets**:
   - `leaflet.js` and `leaflet.css` are bundled inside the app bundle (`Resources/leaflet/`).
   - The map loads instantly even with zero network connectivity.
3. **Two-Way Bridge**:
   - Swift -> JS: `evaluateJavaScript("updateVehicles(\(json))")`
   - JS -> Swift: `window.webkit.messageHandlers.transitBridge.postMessage({ type: 'stationSelected', id: ... })`

---

## 5. Directory & Tab Navigation

* **Floating Glass Tab Bar**: Floating pill with `.ultraThinMaterial` background and custom icons:
  1. `Hărți` (`map.fill`): Fullscreen interactive map with search capsule and vehicle inspector.
  2. `Linii` (`tram.fill`): Line browser grouped into `Autobuz & Troleibuz`, `Tramvai`, and `Metrou`.
  3. `Bilete` (`ticket.fill`): Simulated wallet with countdown timers and animated QR code generator.
  4. `Puls` (`waveform.path.ecg`): Live fleet operational stats and active vehicle counts.
