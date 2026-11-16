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
                                    selectedCategory = category
                                } label: {
                                    Text(category.title)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
                                        .padding(.horizontal, 14)
                                        .frame(height: 32)
                                        .background {
                                            Capsule()
                                                .fill(isSelected ? Color.primary : Color(uiColor: .tertiarySystemGroupedBackground))
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !favoriteRoutes.isEmpty {
                    Section("Favorite") {
                        ForEach(favoriteRoutes) { route in routeRow(route) }
                    }
                }

                Section {
                    ForEach(filteredRoutes) { route in routeRow(route) }
                } header: {
                    Text("\(filteredRoutes.count) linii")
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Linii")
            .searchable(text: $filterText, prompt: "Caută linie")
            .sensoryFeedback(.selection, trigger: selectedCategory)
            .overlay {
                if filteredRoutes.isEmpty && !appState.routes.isEmpty {
                    if filterText.isEmpty {
                        ContentUnavailableView("Nicio linie", systemImage: "bus", description: Text("Nu există linii în această categorie."))
                    } else {
                        ContentUnavailableView.search(text: filterText)
                    }
                }
            }
        }
    }

    private var favoriteRoutes: [Route] {
        guard filterText.isEmpty, selectedCategory == .all else { return [] }
        return appState.routes.filter { appState.favoriteLines.contains($0.line) }
    }

    private func routeRow(_ route: Route) -> some View {
        let isFavorite = appState.favoriteLines.contains(route.line)
        return Button {
            appState.selectLine(route.line)
            appState.selectedTab = .map
        } label: {
            HStack(spacing: 12) {
                LinePlate(line: route.line, color: Color(hex: route.hexColor))
                    .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(routeTitle(for: route))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(statusText(for: route))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if route.activeVehicles > 0 {
                    Circle()
                        .fill(Color.appleGreen)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .leading) {
            Button {
                appState.toggleFavorite(route.line)
            } label: {
                Label(isFavorite ? "Elimină" : "Favorită", systemImage: isFavorite ? "star.slash" : "star")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                appState.toggleFavorite(route.line)
            } label: {
                Label(isFavorite ? "Elimină din favorite" : "Adaugă la favorite", systemImage: isFavorite ? "star.slash" : "star")
            }
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

    private func routeTitle(for route: Route) -> String {
        if let t = route.terminals, t.count >= 2, let first = t.first, let last = t.last {
            return "\(first) – \(last)"
        }
        return route.typeName ?? "Tranzit"
    }

    private func statusText(for route: Route) -> String {
        guard route.activeVehicles > 0 else { return "Fără vehicule active" }
        if route.line.uppercased().hasPrefix("M") {
            return "\(route.activeVehicles) poziții live"
        }
        return route.activeVehicles == 1 ? "1 vehicul în circulație" : "\(route.activeVehicles) vehicule în circulație"
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
