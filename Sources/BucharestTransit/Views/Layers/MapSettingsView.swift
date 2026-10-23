import SwiftUI

struct MapSettingsView: View {
    @AppStorage("map_tile_style") private var mapTileStyle = MapTileStyle.standard.rawValue
    @AppStorage("map_show_stops") private var showStopsInsteadOfVehicles = false

    private var selectedStyle: MapTileStyle {
        MapTileStyle(rawValue: mapTileStyle) ?? .standard
    }

    var body: some View {
        Form {
            Section {
                Picker("Stilul hărții", selection: $mapTileStyle) {
                    ForEach(MapTileStyle.allCases) { style in
                        Label(style.title, systemImage: style.symbol)
                            .tag(style.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Hartă de bază")
            } footer: {
                Text("Stilurile hărții nu necesită cheie API. Alege Satelit pentru imagini aeriene.")
            }

            Section("Stil selectat") {
                Label(selectedStyle.title, systemImage: selectedStyle.symbol)
            }

            Section {
                Toggle("Afișează stațiile în locul vehiculelor", isOn: $showStopsInsteadOfVehicles)
            } footer: {
                Text("Atinge o stație de pe hartă pentru a vedea liniile care o deservesc și următoarele plecări.")
            }
        }
        .navigationTitle("Setări hartă")
        .navigationBarTitleDisplayMode(.inline)
    }
}
