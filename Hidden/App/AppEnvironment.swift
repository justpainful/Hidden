import Foundation
import Observation
import SwiftData
import SwiftUI

/// Everything long-lived, assembled once and handed down the view tree.
///
/// The one decision that matters here: which pair of services the app runs on. Real PhotoKit
/// for users; the deterministic mock for tests, previews and CI screenshots (`simctl` cannot
/// hide seeded media, so a real simulator library can never photograph the Hidden flows).
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let store: MetadataStore
    let libraryService: PhotoLibraryProviding
    let media: MediaProviding
    let model: LibraryModel
    let lock: AppLockService
    let settings: AppSettings
    let textIndex: TextIndexService

    init(mock: Bool = LaunchOptions.useMockLibrary,
         inMemory: Bool = false) {
        // A mock run must not pollute (or read) the user's real metadata.
        let container = HiddenStore.makeContainer(inMemory: inMemory || mock)
        let store = MetadataStore(context: container.mainContext)
        let settings = AppSettings()
        let lock = AppLockService()

        let library: PhotoLibraryProviding
        let media: MediaProviding
        if mock {
            library = MockPhotoLibrary(count: LaunchOptions.mockCount)
            media = MockMediaProvider()
        } else {
            library = HiddenPhotoLibrary()
            media = PhotoMediaProvider()
        }

        self.container = container
        self.store = store
        self.settings = settings
        self.lock = lock
        self.libraryService = library
        self.media = media
        let model = LibraryModel(library: library, media: media, store: store)
        self.model = model
        self.textIndex = TextIndexService(model: model, store: store)

        store.recordsHistory = !settings.incognito
        store.keepsChangeLog = settings.keepsChangeLog

        if LaunchOptions.skipLock {
            lock.isEnabled = false
        }
    }

    /// Settings toggles that services enforce are pushed here, in one place.
    func applySettings() {
        store.recordsHistory = !settings.incognito
        store.keepsChangeLog = settings.keepsChangeLog
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    @MainActor static let defaultValue = AppEnvironment(mock: true, inMemory: true)
}

extension EnvironmentValues {
    var app: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}

/// Flags CI passes at launch so it can screenshot past permission screens and open a given
/// surface. Read straight from the process arguments rather than through `UserDefaults`, so
/// behaviour does not depend on argument-domain parsing.
enum LaunchOptions {
    private static let arguments = ProcessInfo.processInfo.arguments

    /// Swap PhotoKit for the deterministic mock library.
    static var useMockLibrary: Bool { arguments.contains("-UITestMockLibrary") }

    /// Disable the app lock for automated runs.
    static var skipLock: Bool { arguments.contains("-skipLock") }

    static var mockCount: Int {
        guard let index = arguments.firstIndex(of: "-mockCount"),
              arguments.indices.contains(index + 1),
              let count = Int(arguments[index + 1]) else { return 240 }
        return count
    }

    static var startTab: AppTab? {
        guard let index = arguments.firstIndex(of: "-startTab"),
              arguments.indices.contains(index + 1) else { return nil }
        return AppTab(rawValue: arguments[index + 1])
    }
}
