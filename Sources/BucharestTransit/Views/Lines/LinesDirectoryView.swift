import SwiftUI

public struct LinesDirectoryView: View {
    @ObservedObject var appState: AppState
    @State private var filterText = ""
    @State private var selectedCategory: RouteCategory = .all

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RouteCategory.allCases) { category in
                                let isSelected = selectedCategory == category
                                Button {
                                    HapticFeedback.trigger(.light)
                                    selectedCategory = category
                                } label: {
                                    Label(category.title, systemImage: category.symbol)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background {
                                            Capsule()
                                                .fill(isSelected ? Color.appleBlue : Color(uiColor: .tertiarySystemGroupedBackground))
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(filteredRoutes) { route in
                        Button {
                            HapticFeedback.trigger(.medium)
                            appState.selectLine(route.line)
                            appState.selectedTab = .map
                        } label: {
                            HStack(spacing: 12) {
                                Text(route.line)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 48, minHeight: 36)
                                    .background(
                                        Color(hex: route.hexColor),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(route.typeName ?? "Tranzit")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text(route.activeVehicles > 0 ? activeVehicleDescription(for: route) : "Fără vehicule active")
                                        .font(.caption)
                                        .foregroundStyle(route.activeVehicles > 0 ? Color.appleBlue : Color.secondary)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Linii · \(filteredRoutes.count)")
                }
            }
            .listStyle(.insetGrouped)
            .listRowSpacing(6)
            .navigationTitle("Catalog Linii")
            .searchable(text: $filterText, prompt: "Caută linie (ex. 41, 104, 381)...")
        }
    }

    private var filteredRoutes: [Route] {
        appState.routes.filter { route in
            let matchesSearch = filterText.isEmpty || route.line.localizedCaseInsensitiveContains(filterText)
            let matchesCategory: Bool
            switch selectedCategory {
            case .trams:
                matchesCategory = route.typeName?.localizedCaseInsensitiveContains("tram") ?? false
            case .buses:
                let typeName = route.typeName?.lowercased() ?? ""
                matchesCategory = typeName.contains("auto") || typeName.contains("bus") || typeName.contains("trol") ||
                    (!typeName.contains("tram") && !typeName.contains("metr"))
            case .metro:
                matchesCategory = (route.typeName?.localizedCaseInsensitiveContains("metr") ?? false) ||
                    route.line.uppercased().hasPrefix("M")
            case .all:
                matchesCategory = true
            }
            return matchesSearch && matchesCategory
        }
    }

    private func activeVehicleDescription(for route: Route) -> String {
        if route.line.uppercased().hasPrefix("M") {
            return "\(route.activeVehicles) poziții live"
        }
        return "\(route.activeVehicles) active"
    }
}

private enum RouteCategory: String, CaseIterable, Identifiable {
    case all
    case trams
    case buses
    case metro

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Toate"
        case .trams: "Tramvaie"
        case .buses: "Autobuz & Troleibuz"
        case .metro: "Metrou"
        }
    }

    var symbol: String {
        switch self {
        case .all: "line.3.horizontal.decrease"
        case .trams: "tram.fill"
        case .buses: "bus.fill"
        case .metro: "tram.tunnel.fill"
        }
    }
}
