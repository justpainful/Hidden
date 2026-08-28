import SwiftUI

enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case inbox, library, discover, shuffle, insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox:    return String(localized: "Inbox")
        case .library:  return String(localized: "Library")
        case .discover: return String(localized: "Discover")
        case .shuffle:  return String(localized: "Shuffle")
        case .insights: return String(localized: "Insights")
        }
    }

    var symbol: String {
        switch self {
        case .inbox:    return "tray"
        case .library:  return "square.grid.2x2"
        case .discover: return "sparkles.rectangle.stack"
        case .shuffle:  return "shuffle"
        case .insights: return "chart.bar.xaxis"
        }
    }
}

/// The launch state machine: privacy cover, app lock, Photos access, then the app.
struct RootView: View {
    @Environment(\.app) private var app
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: AppTab = .inbox
    /// True while the scene is not active, so the app switcher never shows readable media.
    @State private var isCovered = false
    @State private var didApplyLaunchTab = false

    var body: some View {
        ZStack {
            content

            // The cover sits above everything, opaque, before iOS takes the switcher
            // snapshot. It also stands in front while Face ID runs.
            if isCovered || app.lock.isLocked {
                PrivacyCoverView(showsUnlock: app.lock.isLocked && !isCovered)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isCovered)
        .animation(.easeOut(duration: 0.15), value: app.lock.isLocked)
        .preferredColorScheme(app.settings.preferredColorScheme)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                isCovered = false
                app.lock.appWillEnterForeground()
                app.libraryService.refreshAccess()
                if app.accessReady {
                    Task { await app.model.refresh() }
                }
            case .inactive:
                isCovered = true
            case .background:
                isCovered = true
                app.lock.appDidEnterBackground()
            default:
                break
            }
        }
        .task {
            if !didApplyLaunchTab {
                didApplyLaunchTab = true
                selection = LaunchOptions.startTab
                    ?? AppTab(rawValue: app.settings.launchTabRaw)
                    ?? .inbox
            }
            if app.accessReady {
                await app.model.refresh()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.model.accessState {
        case .notDetermined:
            WelcomeView()
        case .denied, .restricted:
            AccessDeniedView()
        default:
            main
        }
    }

    private var main: some View {
        TabView(selection: $selection) {
            Tab(AppTab.inbox.title, systemImage: AppTab.inbox.symbol, value: .inbox) {
                InboxView()
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.symbol, value: .library) {
                LibraryView()
            }
            Tab(AppTab.discover.title, systemImage: AppTab.discover.symbol, value: .discover) {
                DiscoverView()
            }
            Tab(AppTab.shuffle.title, systemImage: AppTab.shuffle.symbol, value: .shuffle) {
                ShuffleView()
            }
            Tab(AppTab.insights.title, systemImage: AppTab.insights.symbol, value: .insights) {
                InsightsView()
            }
        }
        // iOS 26's native behaviour: the bar recedes while scrolling so media keeps the room.
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

extension AppEnvironment {
    /// Whether the app can start fetching without asking the user anything first.
    var accessReady: Bool { model.accessState.canRead }
}

#Preview {
    RootView()
}
