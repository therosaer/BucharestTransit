import SwiftUI

public enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "Sistem"
        case .light: return "Luminos"
        case .dark: return "Întunecat"
        }
    }
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var dragX: CGFloat?
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance_mode") private var appearanceMode = AppearanceMode.system.rawValue

    private var preferredScheme: ColorScheme? {
        (AppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme
    }

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch appState.selectedTab {
                case .map:
                    TransitMapView(appState: appState)
                        .overlay(alignment: .topTrailing) {
                            CircleGlassButton(systemImage: "gearshape", label: "Setări") {
                                showSettings = true
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                case .lines:
                    LinesDirectoryView(appState: appState)
                        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
                case .tickets:
                    TicketsView(appState: appState)
                        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating liquid glass tab selector
            NativeGlassContainer(spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    tabPill
                        .frame(maxWidth: .infinity)
                    if appState.selectedTab == .map {
                        VStack(spacing: 12) {
                            locateButton
                            searchButton
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: appState.selectedTab)
        }
        .sensoryFeedback(.selection, trigger: appState.selectedTab)
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showSettings) {
            LayersSettingsView(appState: appState)
                .presentationBackground(Color.appBackground)
                .preferredColorScheme(preferredScheme)
        }
        .onChange(of: appState.selectedTab) { _, _ in
            if appState.isMapSearchPresented { appState.closeMapSearch() }
        }
        .preferredColorScheme(preferredScheme)
        .task {
            // One-time migration from the old dark-mode toggle.
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "appearance_mode") == nil,
               defaults.bool(forKey: "dark_mode_enabled") {
                appearanceMode = AppearanceMode.dark.rawValue
            }
            await appState.loadInitialData()
            appState.setAppIsActive(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            appState.setAppIsActive(phase == .active)
        }
    }

    // MARK: - Tab selector

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
                    .animation(dragX == nil && !reduceMotion ? .smooth(duration: 0.3) : nil, value: indicatorX)

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        tabLabel(tab, isSelected: tab == shownTab)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(tab == appState.selectedTab ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { appState.selectedTab = tab }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragX = value.location.x
                    }
                    .onEnded { value in
                        let tab = tab(at: value.location.x, itemWidth: itemWidth)
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
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
                    .font(.body.weight(.medium))
                    .frame(height: 22)

                if tab == .tickets && appState.biletActiveTickets.count > 0 {
                    Circle()
                        .fill(Color.appleGreen)
                        .frame(width: 6, height: 6)
                        .offset(x: 5, y: -2)
                        .accessibilityHidden(true)
                }
            }

            Text(tab.title)
                .font(.caption2.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.appleBlue : Color.secondary)
        .contentShape(Rectangle())
    }

    // MARK: - Map controls

    private var locateButton: some View {
        CircleGlassButton(systemImage: "location.fill", label: "Localizează-mă", tint: .appleBlue) {
            appState.locateTrigger += 1
        }
    }

    private var searchButton: some View {
        CircleGlassButton(
            systemImage: appState.isMapSearchPresented ? "xmark" : "magnifyingglass",
            label: appState.isMapSearchPresented ? "Închide căutarea" : "Caută"
        ) {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                if appState.isMapSearchPresented {
                    appState.closeMapSearch()
                } else {
                    appState.isMapSearchPresented = true
                }
            }
        }
    }
}
