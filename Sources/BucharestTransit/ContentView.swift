import SwiftUI

public struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var dragX: CGFloat?
    @State private var showSettings = false
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Liquid Glass Bottom Bar
            liquidGlassBottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .overlay(alignment: .topTrailing) {
            if appState.selectedTab == .map {
                settingsButton
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showSettings) {
            LayersSettingsView(appState: appState)
                .preferredColorScheme(darkModeEnabled ? .dark : .light)
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: appState.selectedTab) { _, _ in
            if appState.isMapSearchPresented { appState.closeMapSearch() }
        }
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
        NativeGlassContainer(spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                tabPill
                    .frame(maxWidth: .infinity)
                if appState.selectedTab == .map {
                    VStack(spacing: 10) {
                        locateButton
                        mapSearchButton
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 12)
        .animation(.bouncy(duration: 0.4), value: appState.selectedTab)
    }

    private var locateButton: some View {
        Button {
            HapticFeedback.trigger(.medium)
            appState.locateTrigger += 1
        } label: {
            Image(systemName: "location.fill")
                .font(.title3.weight(.semibold))
                .foregroundColor(Color.appleBlue)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .nativeGlass(in: Circle())
        .accessibilityLabel("Localizează-mă")
    }

    private var settingsButton: some View {
        Button {
            HapticFeedback.trigger(.light)
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title3.weight(.semibold))
                .foregroundColor(Color.primary)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .nativeGlass(in: Circle())
        .accessibilityLabel("Setări")
    }

    private var mapSearchButton: some View {
        Button {
            HapticFeedback.trigger(.light)
            withAnimation(.bouncy(duration: 0.45)) {
                if appState.isMapSearchPresented {
                    appState.closeMapSearch()
                } else {
                    appState.isMapSearchPresented = true
                }
            }
        } label: {
            Image(systemName: appState.isMapSearchPresented ? "xmark" : "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundColor(Color.primary)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .nativeGlass(in: Circle())
        .accessibilityLabel(appState.isMapSearchPresented ? "Închide căutarea" : "Caută")
    }

    /// Glass pill with a draggable glass selector: drag it across tabs, or tap a tab to jump to it.
    private var tabPill: some View {
        GeometryReader { geo in
            let tabs = AppTab.allCases
            let itemWidth = geo.size.width / CGFloat(tabs.count)
            let shownTab = dragX.map { tab(at: $0, itemWidth: itemWidth) } ?? appState.selectedTab
            let selectedIndex = CGFloat(tabs.firstIndex(of: appState.selectedTab) ?? 0)
            let indicatorX = dragX.map { min(max($0 - itemWidth / 2, 0), geo.size.width - itemWidth) }
                ?? selectedIndex * itemWidth

            ZStack(alignment: .leading) {
                Color.clear
                    .frame(width: itemWidth, height: geo.size.height)
                    .nativeGlass(in: Capsule())
                    .offset(x: indicatorX, y: 0)
                    .animation(dragX == nil ? .bouncy(duration: 0.4) : .interactiveSpring(), value: indicatorX)

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        tabLabel(tab, isSelected: tab == shownTab)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newTab = tab(at: value.location.x, itemWidth: itemWidth)
                        if newTab != shownTab {
                            HapticFeedback.trigger(.light)
                        }
                        dragX = value.location.x
                    }
                    .onEnded { value in
                        let tab = tab(at: value.location.x, itemWidth: itemWidth)
                        withAnimation(.bouncy(duration: 0.4)) {
                            appState.selectedTab = tab
                            dragX = nil
                        }
                    }
            )
        }
        .frame(height: 56)
        .padding(.horizontal, 4)
        .nativeGlass(in: Capsule())
    }

    private func tab(at x: CGFloat, itemWidth: CGFloat) -> AppTab {
        let tabs = AppTab.allCases
        let index = Int(x / max(itemWidth, 1))
        return tabs[min(max(index, 0), tabs.count - 1)]
    }

    private func tabLabel(_ tab: AppTab, isSelected: Bool) -> some View {
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
        .contentShape(Rectangle())
    }
}
