import SwiftUI

public struct SearchCapsuleView: View {
    @ObservedObject var appState: AppState
    @FocusState private var isSearchFocused: Bool

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.body.weight(.semibold))

                TextField("Caută linie (41, 104, 381) sau vehicul...", text: $appState.searchQuery)
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.search)
                    .font(.body)
                    .onSubmit {
                        let q = appState.searchQuery.trimmingCharacters(in: .whitespaces)
                        guard !q.isEmpty else { return }
                        isSearchFocused = false
                        if let route = matchingRoutes(for: q).first {
                            appState.searchQuery = route.line
                            appState.selectLine(route.line)
                        } else if appState.vehicles.contains(where: { $0.line.uppercased() == q.uppercased() }) {
                            appState.selectLine(q.uppercased())
                        } else if let veh = appState.vehicles.first(where: { $0.label?.uppercased().contains(q.uppercased()) == true }) {
                            appState.selectVehicle(veh)
                        }
                    }

                if !appState.searchQuery.isEmpty {
                    Button(action: {
                        appState.searchQuery = ""
                        isSearchFocused = false
                        appState.clearLineSelection()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.body)
                    }
                }

                // Quick Ticket Countdown Pill lives in TicketCountdownPill (shown when search is closed)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .nativeGlass(in: Capsule())
            .onAppear { isSearchFocused = true }

            // Real-time Autocomplete Dropdown
            if isSearchFocused && !appState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                let matching = matchingRoutes(for: appState.searchQuery.trimmingCharacters(in: .whitespaces))

                if !matching.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(matching.prefix(6)) { route in
                            Button(action: {
                                HapticFeedback.trigger(.medium)
                                isSearchFocused = false
                                appState.searchQuery = route.line
                                appState.selectLine(route.line)
                            }) {
                                HStack(spacing: 12) {
                                    Text(route.line)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(hex: route.hexColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Linia \(route.line) • \(route.typeName ?? "Tranzit")")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.primary)

                                        if let terminals = route.terminals, !terminals.isEmpty {
                                            Text(terminals.joined(separator: " ⇄ "))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Text("\(route.activeVehicles) active")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.appleBlue)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                            }
                            Divider()
                        }
                    }
                    .nativeGlass(cornerRadius: 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func matchingRoutes(for query: String) -> [Route] {
        let q = query.uppercased()
        var routes = appState.routes

        // If routes catalog is still loading, extract unique lines from vehicles
        if routes.isEmpty {
            let uniqueLines = Set(appState.vehicles.map { $0.line })
            routes = uniqueLines.map { line in
                Route(line: line, typeName: "Tranzit", color: "#007AFF", activeVehicles: 1, terminals: nil)
            }
        }

        let filtered = routes.filter {
            $0.line.uppercased().contains(q) ||
            ($0.typeName?.uppercased().contains(q) == true) ||
            ($0.terminals?.contains { $0.uppercased().contains(q) } == true)
        }

        // Rank exact match first, then starts-with, then others
        return filtered.sorted { a, b in
            let aLine = a.line.uppercased()
            let bLine = b.line.uppercased()
            if aLine == q && bLine != q { return true }
            if bLine == q && aLine != q { return false }
            if aLine.hasPrefix(q) && !bLine.hasPrefix(q) { return true }
            if bLine.hasPrefix(q) && !aLine.hasPrefix(q) { return false }
            return a.activeVehicles > b.activeVehicles
        }
    }
}

/// Live countdown for the next active ticket. Renders nothing when there is no active ticket.
public struct TicketCountdownPill: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        if let activeTicket = appState.biletActiveTickets.first, let remaining = activeTicket.remainingSeconds, remaining > 0 {
            Button(action: {
                HapticFeedback.trigger(.medium)
                appState.selectedTab = .tickets
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "ticket.fill")
                        .font(.caption)
                    Text(TransitTimeFormatter.formatRemaining(seconds: remaining))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundColor(.appleGreen)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .nativeGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        }
    }
}
