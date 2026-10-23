# AGENT_GUIDE.md — AI Agent Onboarding & Codebase Manual

> **For any AI Agent (Cursor, Windsurf, Claude Code, Cline, Roo Code, Aider, Hermes, etc.):**  
> Read this document completely before modifying or executing code. It contains the environment setup, build requirements, architectural rules, and data schemas needed to develop this project without breakages.

---

## 1. Environment & Build System (CRITICAL)

* **Host OS**: Linux (`x86_64`)
* **Target OS**: iOS 17+ (arm64 iPhone)
* **Swift Toolchain**: Swift 6.4.1
* **Build System**: **`xtool`**, available on `PATH`
* **Connected Hardware**: An iOS 17+ iPhone connected by USB for device deployment.

### ⚠️ Common Pitfalls:
1. **DO NOT run `swift build` alone on Linux.**
   - On Linux, the standard Swift toolchain does not have `SwiftUI` or `WebKit`.
   - Running `swift build` directly will fail with `error: no such module 'SwiftUI'`.
2. **ALWAYS use `xtool dev build` or `xtool dev run --usb`**:
   - `xtool dev build`: Cross-compiles using the Darwin SDK for iOS and outputs to `xtool/BucharestTransit.app`.
   - `xtool dev run --usb`: Compiles, signs, installs, and launches the app on a connected physical iPhone.
3. **If build cache gets corrupted or references old paths**:
   - Run: `rm -rf .build xtool/*.app && xtool dev build`

---

## 2. Core Architecture & State Flow

```
[STB / mo-bi.ro Live API]          [line_routes_index.json (GTFS)]
          │                                      │
          ▼                                      ▼
[TransitAPIService.swift]           [LocalTransitDataManager.swift]
          │ (Polls every 8-10s)                  │ (Loads 201 lines + schedules)
          └─────────────────┬────────────────────┘
                            │
                            ▼
                    [AppState.swift] (ObservableObject / StateObject)
                      ├── vehicles: [Vehicle]
                      ├── selectedRoute: Route?
                      ├── selectedStation: Station?
                      ├── searchFilter: String
                      └── userLocation: CLLocationCoordinate2D?
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
   [OpenStreetMapView] [LineExplorer] [VehicleInspector]
   (WKWebView Leaflet)   (Timetables)    (Live Telemetry)
```

---

## 3. Key Files & Responsibilities

| File Path | Responsibility |
| :--- | :--- |
| `Sources/BucharestTransit/BucharestTransitApp.swift` | `@main` entrypoint. Instantiates `@StateObject var appState = AppState.shared`. |
| `Sources/BucharestTransit/ContentView.swift` | Root tab interface (`Hărți`, `Linii`, `Bilete`, `Puls`), custom floating liquid glass bottom bar. |
| `Sources/BucharestTransit/Models/Route.swift` | Data structures for `Route`, `Station`, and `LineDetails`. Contains **GTFS Timetable calculation logic** (`nextDepartures(limit:)`, `nextDepartureDisplay`). |
| `Sources/BucharestTransit/Models/Vehicle.swift` | `Vehicle` model with coordinates, bearing, route ID, delay, AC status, speed, and `VehicleType` categorization. |
| `Sources/BucharestTransit/Services/LocalTransitDataManager.swift` | Singleton loader for `line_routes_index.json` (18.8 MB) and `routes_map.json`. Maps GTFS departure arrays into `Station` models. |
| `Sources/BucharestTransit/Services/TransitAPIService.swift` | Network service for STB live feeds. Implements automatic fallback to `snapshot_vehicles.json` when network is unreachable or offline. |
| `Sources/BucharestTransit/Services/AppState.swift` | Central reactive store holding vehicle collections, active filters, selected stations, and location state. |
| `Sources/BucharestTransit/Views/Map/OpenStreetMapView.swift` | **The Core Map Engine**: Uses `WKWebView` with bundled Leaflet (`Resources/leaflet/`). Bridges Swift to JS to render smooth vehicle markers (capped at 75 nearby for 60fps), route polylines, and station timetable popups. |
| `Sources/BucharestTransit/Views/Lines/LineExplorerSheet.swift` | Interactive sheet displaying all stations for a route, direction toggle (Tur/Retur), and expandable departure schedules. |
| `Sources/BucharestTransit/Views/Lines/LinesDirectoryView.swift` | Searchable directory grouped into: **Autobuz & Troleibuz**, **Tramvai**, and **Metrou**. |

---

## 4. Timetable & GTFS Implementation Details

* **Source**: Official Bucharest TPBI GTFS `stop_times.txt` (processed into `Resources/line_routes_index.json`).
* **Station Schema**:
  ```json
  {
    "id": "10023",
    "name": "Piața Romană",
    "lat": 44.4447,
    "lng": 26.0975,
    "schedule_wd": ["05:12", "05:25", "05:38", "05:50", "06:02", ...],
    "schedule_we": ["05:30", "05:50", "06:10", "06:30", ...]
  }
  ```
* **Schedule Resolution**:
  - `schedule_wd`: Weekday departures (Monday–Friday).
  - `schedule_we`: Weekend departures (Saturday–Sunday).
  - The model `Station.nextDepartures(limit: 4)` checks current system time in `Europe/Bucharest`, selects the matching day schedule, and computes:
    - `minutesUntil`: Minutes until arrival.
    - `displayTime`: `HH:mm`.
    - If departure is `< 1 min`, returns `"Pleacă acum"`.
    - If departure is `< 60 min`, returns `"⏱️ În X min (la HH:mm)"`.
* **Station Popup UI in Leaflet**:
  - When a station marker is tapped on the map, Leaflet renders custom HTML:
    - Station name and badge.
    - "● Ești în stație" if user GPS is within 250m.
    - Next immediate departure countdown.
    - Next 4 upcoming departure pills.

---

## 5. User Preferences & UI Conventions

1. **Unified Bus & Trolley Category**:
   - The user explicitly requested that `Autobuz` and `Troleibuz` be compacted together into **"Autobuz & Troleibuz"** in the directory view. Do not split them back apart.
2. **Apple Design Language**:
   - Translucent frosted glass materials (`.ultraThinMaterial`), subtle borders (`Color.white.opacity(0.15)`), smooth spring animations (`.spring(response: 0.35, dampingFraction: 0.8)`).
   - Instant touch feedback on press (`.scaleEffect(isPressed ? 0.97 : 1.0)`).
   - Read `docs/apple_design_guide.md` for full principles.
3. **Romanian Localization**:
   - All user-facing strings must remain in Romanian:
     - `Hărți`, `Linii`, `Bilete`, `Puls`
     - `Căutare stație sau linie...`
     - `Următoarele plecări`
     - `Pleacă acum`

---

## 6. How to Deploy Changes

When you make changes to Swift files:
```bash
# 1. Build and verify there are no compile errors:
xtool dev build

# 2. Deploy directly to the user's USB-connected iPhone:
xtool dev run --usb
```
If `xtool dev run --usb` succeeds, the app will compile, sign, transfer, and launch on the connected phone.
