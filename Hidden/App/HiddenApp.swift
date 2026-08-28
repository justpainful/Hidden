import SwiftUI

@main
struct HiddenApp: App {
    /// Owned here so there is exactly one of it, and so the real on-disk store is what the
    /// app runs on — the environment's default value is an in-memory mock for previews.
    @State private var app = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.app, app)
                .modelContainer(app.container)
                .tint(Palette.accent)
        }
    }
}
