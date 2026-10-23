import SwiftUI

public struct LineExplorerSheet: View {
    @ObservedObject var appState: AppState
    public let line: String
    var isCompact: Bool = false
    @State private var expandedStationId: String? = nil

    public var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 12) {
                Text(line)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(hex: appState.activeLineData?.color ?? "#007AFF"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Linia \(line) • \(appState.activeLineData?.typeName ?? "Tranzit")")
                        .font(.system(size: 16, weight: .bold))

                    if let tur = appState.activeLineData?.turTerminal, let retur = appState.activeLineData?.returTerminal {
                        Text("Tur: → \(tur)\nRetur: → \(retur)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button(action: {
                    HapticFeedback.trigger(.light)
                    appState.clearLineSelection()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            if !isCompact {
                if line.uppercased().hasPrefix("M") {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            MetroHeadwayEstimate.description(for: line)
                                .map { "Estimare orientativă: \($0). Ramurile pot avea intervale diferite; trenurile nu sunt urmărite live." }
                                ?? "Fără poziții live disponibile.",
                            systemImage: "clock"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                        Link(
                            "Program de circulație Metrorex",
                            destination: URL(string: "https://www.metrorex.ro/set-locale/ro/program-de-circulatie-in-zile-lucratoare")!
                        )
                        .font(.system(size: 11, weight: .medium))
                        Link(
                            "Program zile nelucrătoare",
                            destination: URL(string: "https://data.gov.ro/dataset/b5827288-dac1-4846-8712-b724fc51648a/resource/75d265c8-361d-448a-bdb6-c433d5e32864/download/program-de-circulaie-in-zile-nelucrtoare-si-sarbatori-legale.xml")!
                        )
                        .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                }

                // Segmented Controls (Ambele / Tur / Retur)
                Picker("Direcție", selection: $appState.lineDirection) {
                    ForEach(LineDirection.allCases) { dir in
                        Text(dir.rawValue).tag(dir)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)

                // On-route vs All-Assigned filter
                HStack(spacing: 8) {
                let onRouteCount = lineVehicles.filter { $0.isOnRoute == true }.count
                let totalCount = lineVehicles.count

                Button(action: {
                    HapticFeedback.trigger(.light)
                    appState.filterOnRouteOnly = true
                }) {
                    Text("📍 Pe Traseu (\(onRouteCount))")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(appState.filterOnRouteOnly ? Color.appleBlue : Color.secondary.opacity(0.15))
                        .foregroundColor(appState.filterOnRouteOnly ? .white : .primary)
                        .clipShape(Capsule())
                }

                Button(action: {
                    HapticFeedback.trigger(.light)
                    appState.filterOnRouteOnly = false
                }) {
                    Text("Toate Alocate (\(totalCount))")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(!appState.filterOnRouteOnly ? Color.appleBlue : Color.secondary.opacity(0.15))
                        .foregroundColor(!appState.filterOnRouteOnly ? .white : .primary)
                        .clipShape(Capsule())
                }

                Spacer()
                }
                .padding(.horizontal, 18)

                // Assigned Vehicles Horizontal Strip
                if !lineVehicles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                    Text("Vehicule pe Linie")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 18)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(lineVehicles) { v in
                                Button(action: {
                                    HapticFeedback.trigger(.medium)
                                    appState.selectVehicle(v)
                                }) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(v.isOnRoute == true ? Color.appleGreen : (v.isOnRoute == false ? Color.appleOrange : Color.secondary))
                                            .frame(width: 8, height: 8)

                                        Text(v.label ?? v.id)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.primary)

                                        if let direction = v.directionLabel(
                                            turTerminal: appState.activeLineData?.turTerminal,
                                            returTerminal: appState.activeLineData?.returTerminal
                                        ) {
                                            Text(direction)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.secondary)
                                        }

                                        Text(v.displaySpeed)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .appleGlassBackground(cornerRadius: 12)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    }
                }

                // Stations Stop Strip
                if let stations = activeStations, !stations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                    Text("Stații (\(stations.count))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 18)

                    List(stations.indices, id: \.self) { idx in
                        let st = stations[idx]
                        VStack(alignment: .leading, spacing: 6) {
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    if expandedStationId == st.id {
                                        expandedStationId = nil
                                    } else {
                                        expandedStationId = st.id
                                    }
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(hex: appState.activeLineData?.color ?? "#007AFF"))
                                        .frame(width: 7, height: 7)

                                    Text(st.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if let eta = line.uppercased().hasPrefix("M")
                                        ? MetroHeadwayEstimate.description(for: line, stationName: st.name)
                                        : estimatedArrival(for: st) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock.fill")
                                                .font(.system(size: 10))
                                            Text(eta)
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                        }
                                        .foregroundColor(eta.contains("În stație") ? .appleGreen : .appleBlue)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background((eta.contains("În stație") ? Color.appleGreen : Color.appleBlue).opacity(0.12), in: Capsule())
                                    } else {
                                        Text("#\(idx + 1)")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            if expandedStationId == st.id {
                                let upcoming = st.nextDepartures(limit: 5)
                                VStack(alignment: .leading, spacing: 4) {
                                    if !upcoming.isEmpty {
                                        Text("Următoarele plecări programate:")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)

                                        HStack(spacing: 6) {
                                            ForEach(upcoming, id: \.time) { item in
                                                Text(item.time)
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.appleBlue)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 3)
                                                    .background(Color.appleBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                            }
                                        }
                                    }
                                    if !st.todayDepartures.isEmpty {
                                        Text("Total: \(st.todayDepartures.count) plecări azi (orar oficial GTFS)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .padding(.top, 2)
                                    }
                                }
                                .padding(.leading, 17)
                                .padding(.vertical, 4)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                    }
                    .listStyle(.plain)
                    }
                }

                Spacer()
            }
        }
    }

    private func estimatedArrival(for station: Station) -> String? {
        for v in lineVehicles {
            let dLat = (station.lat - v.latitude) * .pi / 180.0
            let dLon = (station.lon - v.longitude) * .pi / 180.0
            let a = sin(dLat / 2) * sin(dLat / 2) +
                    cos(v.latitude * .pi / 180.0) * cos(station.lat * .pi / 180.0) *
                    sin(dLon / 2) * sin(dLon / 2)
            let dKm = 6371.0 * (2 * atan2(sqrt(a), sqrt(1 - a)))
            if dKm < 0.22 {
                return "În stație"
            }
        }

        if let display = station.nextDepartureDisplay {
            return display
        }

        return nil
    }

    private var lineVehicles: [Vehicle] {
        appState.vehicles.filter { vehicle in
            guard vehicle.line.uppercased() == line.uppercased() else { return false }
            switch appState.lineDirection {
            case .both:
                return true
            case .tur:
                return vehicle.directionId == 0
            case .retur:
                return vehicle.directionId == 1
            }
        }
    }

    private var activeStations: [Station]? {
        guard let data = appState.activeLineData else { return nil }
        switch appState.lineDirection {
        case .both:
            return (data.turStations ?? []) + (data.returStations ?? [])
        case .tur:
            return data.turStations
        case .retur:
            return data.returStations
        }
    }
}
