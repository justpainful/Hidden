import Foundation

/// A plain-value description of one media item the app can see, safe to hand to background
/// work, to tests, and to CI where PhotoKit does not exist.
///
/// The real library builds these from `PHAsset`; the mock builds them from a seed. Everything
/// downstream — filters, sorting, shuffle, the inbox diff — works on this value and never on
/// a live PhotoKit object.
struct HiddenAsset: Sendable, Hashable, Identifiable {
    var id: String { localIdentifier }

    var localIdentifier: String
    var kind: MediaKind
    var creationDate: Date
    var modificationDate: Date?
    var pixelWidth: Int
    var pixelHeight: Int
    /// Seconds; zero for stills.
    var duration: TimeInterval
    /// Apple's favourite state, as PhotoKit reports it.
    var isFavorite: Bool
    var subtypes: MediaSubtypes
    var latitude: Double?
    var longitude: Double?

    var isVideo: Bool { kind == .video }
    var hasLocation: Bool { latitude != nil && longitude != nil }

    var orientation: AssetOrientation {
        if pixelWidth == pixelHeight { return .square }
        return pixelWidth > pixelHeight ? .landscape : .portrait
    }

    /// Megapixels, for resolution-range filters.
    var megapixels: Double { Double(pixelWidth) * Double(pixelHeight) / 1_000_000 }
}

enum MediaKind: String, Sendable, Hashable, Codable {
    case photo
    case video
}

enum AssetOrientation: String, Sendable, Hashable, CaseIterable, Codable {
    case portrait, landscape, square
}

/// The public PhotoKit subtypes the app cares about, carried as an option set of our own so
/// the value stays `Sendable` and mock-constructible without importing Photos.
struct MediaSubtypes: OptionSet, Sendable, Hashable {
    let rawValue: Int

    static let livePhoto      = MediaSubtypes(rawValue: 1 << 0)
    static let screenshot     = MediaSubtypes(rawValue: 1 << 1)
    static let panorama       = MediaSubtypes(rawValue: 1 << 2)
    static let hdr            = MediaSubtypes(rawValue: 1 << 3)
    static let depthEffect    = MediaSubtypes(rawValue: 1 << 4)
    static let slowMotion     = MediaSubtypes(rawValue: 1 << 5)
    static let timeLapse      = MediaSubtypes(rawValue: 1 << 6)
    static let cinematic      = MediaSubtypes(rawValue: 1 << 7)
}

extension HiddenAsset {
    var isLivePhoto: Bool { subtypes.contains(.livePhoto) }
    var isScreenshot: Bool { subtypes.contains(.screenshot) }
}
