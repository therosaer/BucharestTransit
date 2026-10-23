# Claude Code Guidelines for BucharestTransit

## Project Overview
Native iOS public transit application for Bucharest (STB, Metrou, TPBI) written in Swift 6 and SwiftUI. Built and deployed on Linux using `xtool`.

## Build & Test Commands
- **Build App**: `xtool dev build` *(DO NOT run `swift build` directly on Linux host; Linux Swift has no SwiftUI)*
- **Deploy to USB iPhone**: `xtool dev run --usb` *(Deploys to a connected iOS 17+ device)*
- **Clean Build Cache**: `rm -rf .build xtool/*.app && xtool dev build`
- **Device List**: `xtool devices`

## Architecture & Code Guidelines
- **Language**: Swift 6.4.1 (SwiftPM `Package.swift`).
- **Target**: iOS 17.0+
- **Main State**: `AppState.shared` (`@StateObject` / `@Observable`) in `Sources/BucharestTransit/Services/AppState.swift`.
- **Map View**: `OpenStreetMapView.swift` uses a `WKWebView` with bundled Leaflet (`Resources/leaflet/`). Do not replace this with raw MapKit without verifying Linux cross-compilation support.
- **Timetables**: 17,622 station schedules pre-indexed from GTFS in `Resources/line_routes_index.json`. Handled in `Route.swift` via `nextDepartures(limit:)`.
- **Categories**: Keep `Autobuz & Troleibuz` unified together in `LinesDirectoryView.swift`.
- **UI Design**: Strictly follow `docs/apple_design_guide.md` (fluid springs, `.ultraThinMaterial`, instant feedback on tap down, Romanian language UI).
