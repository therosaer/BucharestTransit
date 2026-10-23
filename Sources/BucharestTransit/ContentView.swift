import SwiftUI

public struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @Namespace private var tabNamespace
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("dark_mode_enabled") private var darkModeEnabled = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Main Tab Content
            Group {
                switch appState.selectedTab {
                case .map:
                    TransitMapView(appState: appState)
                case .lines:
                    LinesDirectoryView(appState: appState)
                        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
                case .tickets:
                    TicketsView(appState: appState)
                        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
                case .stats:
                    TransitPulseView(appState: appState)
                        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
                case .layers:
                    LayersSettingsView(appState: appState)
                        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Liquid Glass Bottom Bar
            liquidGlassBottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(darkModeEnabled ? .dark : .light)
        .task {
            await appState.loadInitialData()
            appState.setAppIsActive(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            appState.setAppIsActive(phase == .active)
        }
    }

    // MARK: - Liquid Glass Dock
    private var liquidGlassBottomBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = appState.selectedTab == tab

                Button(action: {
                    HapticFeedback.trigger(.light)
                    appState.selectedTab = tab
                }) {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.systemImage)
                                .font(isSelected ? .title3.weight(.semibold) : .body.weight(.medium))
                                .frame(height: 22)

                            // Active Tickets Red Dot Indicator
                            if tab == .tickets && appState.biletActiveTickets.count > 0 {
                                Circle()
                                    .fill(Color.appleRed)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 5, y: -2)
                            }
                        }

                        Text(tab.title)
                            .font(.caption.weight(isSelected ? .bold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(isSelected ? Color.appleBlue : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.appleBlue.opacity(0.14))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.appleBlue.opacity(0.25), lineWidth: 0.8)
                                )
                                .matchedGeometryEffect(id: "activeTabPill", in: tabNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .liquidGlass(cornerRadius: 32)
    }
}
