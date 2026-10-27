import SwiftUI

public struct LayersSettingsView: View {
    @ObservedObject var appState: AppState

    @AppStorage("layer_trams") private var layerTrams = true
    @AppStorage("layer_trolleys") private var layerTrolleys = true
    @AppStorage("layer_buses") private var layerBuses = true
    @AppStorage("layer_subway") private var layerSubway = true
    @AppStorage("layer_night") private var layerNight = true
    @AppStorage("map_hide_stale_vehicles") private var hideStaleVehicles = false
    @AppStorage("layer_stations") private var layerStations = true
    @AppStorage("layer_depots") private var layerDepots = true
    @AppStorage("layer_dedicated_lanes") private var layerDedicatedLanes = true
    @AppStorage("dark_mode_enabled") private var darkModeEnabled = false

    public var body: some View {
        NavigationStack {
            List {
                Section("Aspect") {
                    Toggle(isOn: $darkModeEnabled) {
                        Label("Mod întunecat", systemImage: darkModeEnabled ? "moon.fill" : "sun.max.fill")
                    }
                }

                Section("Hartă") {
                    NavigationLink {
                        MapSettingsView()
                    } label: {
                        Label("Setări hartă", systemImage: "map")
                    }
                }

                Section("Straturi Hartă Live") {
                    Toggle(isOn: $layerTrams) {
                        Label("Rețea Tramvaie", systemImage: "tram.fill")
                    }
                    Toggle(isOn: $layerTrolleys) {
                        Label("Rețea Troleibuze", systemImage: "cablecar.fill")
                    }
                    Toggle(isOn: $layerBuses) {
                        Label("Rețea Autobuze", systemImage: "bus.fill")
                    }
                    Toggle(isOn: $layerSubway) {
                        Label("Magistrale Metrou M1-M5", systemImage: "tram.tunnel.fill")
                    }
                    Toggle(isOn: $layerNight) {
                        Label("Linii de noapte (N1-N122)", systemImage: "moon.stars")
                    }
                    Toggle(isOn: $layerStations) {
                        Label("Stații și puncte de îmbarcare", systemImage: "mappin.and.ellipse")
                    }
                    Toggle(isOn: $layerDepots) {
                        Label("Autobaze și depouri STB", systemImage: "building.2")
                    }
                    Toggle(isOn: $layerDedicatedLanes) {
                        Label("Benzi dedicate", systemImage: "arrow.trianglehead.branch")
                    }
                }

                Section("Filtrare & Optimizare") {
                    Toggle("Doar vehicule în serviciu pe traseu", isOn: $appState.filterOnRouteOnly)
                    Text("Ascunde automat vehiculele aflate în probe, la garaj sau în retragere.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Toggle("Ascunde vehiculele cu GPS vechi", isOn: $hideStaleVehicles)
                    Text("Ascunde vehiculele cu poziții GPS mai vechi de 2 minute sau provenite dintr-o copie offline.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Mod Conexiune API") {
                    HStack {
                        Label("Tranzit Live", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text("mo-bi.ro Direct")
                        .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color.appleGreen)
                    }
                    HStack {
                        Label("Ticketing & Bilete", systemImage: "ticket.fill")
                        Spacer()
                        Text("STB SA Direct")
                        .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color.appleBlue)
                    }
                    HStack {
                        Label("Geometrii & Trasee", systemImage: "map.fill")
                        Spacer()
                        Text("Pe Dispozitiv")
                        .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    Button(action: {
                        Task { await appState.refreshData() }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reîmprospătează Datele Live")
                        }
                    }
                    Text("Aplicația rulează 100% autonom pe telefon, conectându-se direct la serverele oficiale STB fără să necesite un server desktop.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Despre Aplicație") {
                    LabeledContent("Versiune", value: "2026.10 • Apple Design Edition")
                    LabeledContent("Sursă Date Live", value: "TPBI • mo-bi.ro Open Data")
                    LabeledContent("Integrare Bilete", value: "STB SA Bilet TB Oficial")
                    LabeledContent("Arhitectură", value: "SwiftUI + MapKit (xtool)")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Straturi și Setări")
        }
    }
}
