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
    @AppStorage("appearance_mode") private var appearanceMode = AppearanceMode.system.rawValue

    public var body: some View {
        NavigationStack {
            Form {
                Section("Aspect") {
                    Picker("Temă", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.appCard)

                Section("Hartă") {
                    NavigationLink {
                        MapSettingsView()
                    } label: {
                        Label("Setări hartă", systemImage: "map")
                    }
                }
                .listRowBackground(Color.appCard)

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
                .listRowBackground(Color.appCard)

                Section {
                    Toggle("Doar vehicule în serviciu pe traseu", isOn: $appState.filterOnRouteOnly)
                    Toggle("Ascunde vehiculele cu GPS vechi", isOn: $hideStaleVehicles)
                } header: {
                    Text("Filtrare & Optimizare")
                } footer: {
                    Text("Primul comutator ascunde vehiculele aflate în probe, la garaj sau în retragere. Al doilea ascunde pozițiile GPS mai vechi de 2 minute sau provenite dintr-o copie offline.")
                }
                .listRowBackground(Color.appCard)

                Section {
                    HStack {
                        Label("Tranzit Live", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text("mo-bi.ro Direct")
                        .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appleGreenText)
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
                } header: {
                    Text("Mod Conexiune API")
                } footer: {
                    Text("Aplicația rulează 100% autonom pe telefon, conectându-se direct la serverele oficiale STB fără să necesite un server desktop.")
                }
                .listRowBackground(Color.appCard)

                Section("Despre Aplicație") {
                    LabeledContent("Versiune", value: "V1.3.1")
                    LabeledContent("Sursă Date Live", value: "TPBI • mo-bi.ro Open Data")
                    LabeledContent("Integrare Bilete", value: "STB SA Bilet TB Oficial")
                    LabeledContent("Arhitectură", value: "SwiftUI + MapKit (xtool)")
                }
                .listRowBackground(Color.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Straturi și Setări")
        }
    }
}
