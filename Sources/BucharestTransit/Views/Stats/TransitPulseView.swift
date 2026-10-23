import SwiftUI

public struct TransitPulseView: View {
    @ObservedObject var appState: AppState

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Sync Status Banner
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(sourceColor)
                                .frame(width: 8, height: 8)
                            Text(sourceDescription)
                                .font(.footnote.weight(.bold))
                                .foregroundColor(sourceColor)
                        }

                        Spacer()

                        Text(appState.isSyncing ? "Se actualizează..." : "La fiecare 12s · în prim-plan")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .appleGlassBackground(cornerRadius: 14)

                    // Main KPI Cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        KPICard(
                            title: "Vehicule raportate",
                            value: "\(appState.stats?.totalVehicles ?? appState.vehicles.count)",
                            subtitle: "În datele recepționate",
                            color: .appleBlue
                        )

                        KPICard(
                            title: "Linii Active",
                            value: "\(appState.stats?.activeLines ?? appState.routes.count)",
                            subtitle: "Trasee urbane și metropolitane",
                            color: .appleGreen
                        )

                        KPICard(
                            title: "Aglomerate",
                            value: crowdedVehiclesDescription,
                            subtitle: "Grad ridicat raportat",
                            color: .appleRed
                        )
                    }

                    // Distribution by Vehicle Type
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Distribuție pe Tipuri de Transport")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 8) {
                            let byType = appState.stats?.byType ?? [:]

                            TypeRow(name: "Autobuze Urbane & Regionale", count: byType["bus"] ?? 0, color: .appleBlue, icon: "bus.fill")
                            Divider()
                            TypeRow(name: "Tramvaie (Astra Imperio / Tatra)", count: byType["tram"] ?? 0, color: .appleRed, icon: "tram.fill")
                            Divider()
                            TypeRow(name: "Troleibuze (Solaris Trollino)", count: byType["trolley"] ?? 0, color: .appleGreen, icon: "cablecar.fill")
                            Divider()
                            TypeRow(name: "Metrou (Metrorex M1-M5)", count: byType["metro"] ?? (byType["subway"] ?? 0), color: .appleOrange, icon: "tram.tunnel.fill")
                        }
                        .padding(16)
                        .appleGlassBackground(cornerRadius: 18)
                    }

                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .navigationTitle("Statistici Flotă")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        HapticFeedback.trigger(.medium)
                        Task { await appState.refreshData() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var crowdedVehiclesDescription: String {
        guard !appState.vehicles.isEmpty,
              let count = appState.stats?.crowdedVehicles else { return "Indisponibil" }
        return String(count)
    }

    private var sourceDescription: String {
        let liveVehicles = appState.vehicles.filter { $0.dataSource == .live }
        if liveVehicles.contains(where: { $0.isTelemetryStale == false }) {
            return "Date live de la vehicule"
        }
        if !liveVehicles.isEmpty {
            return "Poziții GPS vechi"
        }
        if appState.vehicles.contains(where: { $0.dataSource == .snapshot }) {
            return "Copie offline · poziții posibil vechi"
        }
        return appState.isSyncing ? "Se încarcă datele vehiculelor" : "Date vehicule indisponibile"
    }

    private var sourceColor: Color {
        let liveVehicles = appState.vehicles.filter { $0.dataSource == .live }
        if liveVehicles.contains(where: { $0.isTelemetryStale == false }) {
            return .appleGreen
        }
        if !liveVehicles.isEmpty {
            return .appleOrange
        }
        if appState.vehicles.contains(where: { $0.dataSource == .snapshot }) {
            return .appleOrange
        }
        return .secondary
    }
}

private struct KPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.title2.weight(.bold))
                .foregroundColor(color)

            Text(subtitle)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appleGlassBackground(cornerRadius: 18)
    }
}

private struct TypeRow: View {
    let name: String
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 22)

            Text(name)
                .font(.subheadline)

            Spacer()

            Text("\(count)")
                .font(.headline.weight(.semibold))
                .foregroundColor(.primary)
        }
    }
}
