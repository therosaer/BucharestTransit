import SwiftUI

struct StopInspectorSheet: View {
    @ObservedObject var appState: AppState
    let stop: MapStop

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STAȚIE")
                        .font(.system(.caption2, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(stop.name)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    appState.dismissStopInspector()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .accessibilityLabel("Închide")
            }

            if stop.services.contains(where: { $0.line.uppercased().hasPrefix("M") }),
               let facilities = MetroGTFSStore.shared.facilities(name: stop.name, lat: stop.lat, lon: stop.lon) {
                metroFacilitiesView(facilities)
            }

            Text("Linii și următoarele plecări")
                .font(.system(.caption, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(stop.services) { service in
                        serviceRow(service)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func metroFacilitiesView(_ facilities: MetroFacilities) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Facilități (GTFS)")
                .font(.system(.caption, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            if !facilities.entrances.isEmpty {
                Label(
                    "\(facilities.entrances.count) intrări: \(facilities.entrances.prefix(3).joined(separator: " · "))",
                    systemImage: "door.left.hand.open"
                )
            }

            let pathwayText = facilities.pathways
                .sorted { $0.key < $1.key }
                .map { "\($0.value) \(MetroGTFSStore.pathwayLabels[$0.key] ?? $0.key)" }
                .joined(separator: " · ")
            if !pathwayText.isEmpty {
                Label(pathwayText, systemImage: "figure.walk")
            }

            if !facilities.transfers.isEmpty {
                Label("Transfer: \(facilities.transfers.joined(separator: ", "))", systemImage: "arrow.triangle.swap")
            }

            Label(
                facilities.hasRestrooms ? "Toalete publice" : "Fără toalete publice raportate",
                systemImage: "toilet"
            )
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appleGlassBackground(cornerRadius: 14)
    }

    private func serviceRow(_ service: StopService) -> some View {
        let station = Station(
            id: service.id,
            name: stop.name,
            lat: stop.lat,
            lon: stop.lon,
            scheduleWd: service.scheduleWd,
            scheduleWe: service.scheduleWe
        )
        let isMetro = service.line.uppercased().hasPrefix("M")
        let gtfsNext = isMetro
            ? MetroGTFSStore.shared.upcomingDepartures(line: service.line, stationName: stop.name, lat: stop.lat, lon: stop.lon, limit: 3)
            : nil
        let departures: [UpcomingDeparture] = gtfsNext
            ?? station.nextDepartures(limit: 3).map { UpcomingDeparture(minutes: $0.minutes, time: $0.time) }
        let color = Color(hex: service.color ?? "#007AFF")

        return Button {
            HapticFeedback.trigger(.light)
            appState.selectStopService(service)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(service.line)
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(minWidth: 42, minHeight: 32)
                    .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(service.direction)
                            .font(.system(.subheadline, weight: .semibold))
                        if let typeName = service.typeName {
                            Text("· \(typeName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let next = departures.first {
                        Text(next.minutes == 0 ? "Plecare acum · \(next.time)" : "În \(next.minutes) min · \(next.time)")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundColor(.appleBlue)

                        if departures.count > 1 {
                            Text("Următoarele: \(departures.dropFirst().map(\.time).joined(separator: " · "))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if station.todayDepartures.isEmpty {
                        Text("Orar indisponibil")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Programul de azi s-a încheiat")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "map")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .appleGlassBackground(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Afișează linia \(service.line), direcția \(service.direction) pe hartă")
    }
}
