import SwiftUI

struct StopInspectorSheet: View {
    @ObservedObject var appState: AppState
    let stop: MapStop

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STAȚIE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(stop.name)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
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

            Text("Linii și următoarele plecări")
                .font(.system(size: 12, weight: .bold))
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

    private func serviceRow(_ service: StopService) -> some View {
        let station = Station(
            id: service.id,
            name: stop.name,
            lat: stop.lat,
            lon: stop.lon,
            scheduleWd: service.scheduleWd,
            scheduleWe: service.scheduleWe
        )
        let departures = station.nextDepartures(limit: 3)
        let color = Color(hex: service.color ?? "#007AFF")

        return Button {
            HapticFeedback.trigger(.light)
            appState.selectStopService(service)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(service.line)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minWidth: 42, minHeight: 32)
                    .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(service.direction)
                            .font(.system(size: 14, weight: .semibold))
                        if let typeName = service.typeName {
                            Text("· \(typeName)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let next = departures.first {
                        Text(next.minutes == 0 ? "Plecare acum · \(next.time)" : "În \(next.minutes) min · \(next.time)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appleBlue)

                        if departures.count > 1 {
                            Text("Următoarele: \(departures.dropFirst().map(\.time).joined(separator: " · "))")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    } else if station.todayDepartures.isEmpty {
                        Text("Orar indisponibil")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Programul de azi s-a încheiat")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "map")
                    .font(.system(size: 14, weight: .semibold))
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
