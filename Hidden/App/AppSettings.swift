import Foundation
import Observation
import SwiftUI

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light:  return String(localized: "Light")
        case .dark:   return String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// User-facing preferences. Everything here is stored in `UserDefaults` on this device;
/// there is no account to sync it to and no server to send it to.
@MainActor
@Observable
final class AppSettings {
    // Privacy
    /// While on, nothing about viewing is recorded anywhere.
    var incognito: Bool { didSet { store(incognito, "incognito") } }
    /// Thumbnails stay blurred until tapped.
    var blurThumbnails: Bool { didSet { store(blurThumbnails, "blurThumbnails") } }
    /// The app makes no changes to Apple Photos at all.
    var readOnlyMode: Bool { didSet { store(readOnlyMode, "readOnlyMode") } }
    /// No delete control is offered anywhere.
    var noDeleteMode: Bool { didSet { store(noDeleteMode, "noDeleteMode") } }
    /// Record the local change journal.
    var keepsChangeLog: Bool { didSet { store(keepsChangeLog, "keepsChangeLog") } }

    // Playback
    var photoDuration: TimeInterval { didSet { store(photoDuration, "photoDuration") } }
    var muteByDefault: Bool { didSet { store(muteByDefault, "muteByDefault") } }
    var autoplayNext: Bool { didSet { store(autoplayNext, "autoplayNext") } }

    // Library
    var defaultSortRaw: String { didSet { store(defaultSortRaw, "defaultSort") } }
    /// Columns in the library grid at launch.
    var gridColumns: Int { didSet { store(gridColumns, "gridColumns") } }

    // Appearance
    var appearance: AppearanceChoice { didSet { store(appearance.rawValue, "appearance") } }

    var defaultSort: LibrarySort {
        get { LibrarySort(rawValue: defaultSortRaw) ?? .recentlyObserved }
        set { defaultSortRaw = newValue.rawValue }
    }

    var preferredColorScheme: ColorScheme? { appearance.colorScheme }

    private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        incognito = defaults.object(forKey: "incognito") as? Bool ?? false
        blurThumbnails = defaults.object(forKey: "blurThumbnails") as? Bool ?? false
        readOnlyMode = defaults.object(forKey: "readOnlyMode") as? Bool ?? false
        noDeleteMode = defaults.object(forKey: "noDeleteMode") as? Bool ?? false
        keepsChangeLog = defaults.object(forKey: "keepsChangeLog") as? Bool ?? true
        photoDuration = defaults.object(forKey: "photoDuration") as? TimeInterval ?? 3
        muteByDefault = defaults.object(forKey: "muteByDefault") as? Bool ?? true
        autoplayNext = defaults.object(forKey: "autoplayNext") as? Bool ?? true
        defaultSortRaw = defaults.string(forKey: "defaultSort") ?? LibrarySort.recentlyObserved.rawValue
        gridColumns = defaults.object(forKey: "gridColumns") as? Int ?? 3
        appearance = AppearanceChoice(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
