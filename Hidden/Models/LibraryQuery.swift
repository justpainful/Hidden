import Foundation

/// How the library is ordered. Every case is a pure comparator over the asset and the app's
/// metadata for it, so the whole menu is unit-testable.
enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case recentlyObserved      // when Hidden first saw the asset — the honest "recently added"
    case newestCaptured
    case oldestCaptured
    case newestModified
    case oldestModified
    case observedFavorite
    case shortestVideo
    case longestVideo
    case photosFirst
    case videosFirst
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyObserved: return String(localized: "Recently Observed")
        case .newestCaptured:   return String(localized: "Newest Captured")
        case .oldestCaptured:   return String(localized: "Oldest Captured")
        case .newestModified:   return String(localized: "Latest Modified")
        case .oldestModified:   return String(localized: "Oldest Modified")
        case .observedFavorite: return String(localized: "Recently Favorited")
        case .shortestVideo:    return String(localized: "Shortest First")
        case .longestVideo:     return String(localized: "Longest First")
        case .photosFirst:      return String(localized: "Photos First")
        case .videosFirst:      return String(localized: "Videos First")
        case .random:           return String(localized: "Random")
        }
    }
}

/// One composable predicate over an asset and its metadata. Filters are ANDed together;
/// several values within one criterion (e.g. two media kinds) are ORed.
///
/// Codable because a smart collection is exactly this struct serialized: the rules survive
/// as JSON, so adding a criterion never needs a database migration.
struct LibraryFilter: Sendable, Equatable, Codable {
    var kinds: Set<MediaKind> = []
    var onlyFavorites = false
    var onlyAppFavorites = false
    var onlyLivePhotos = false
    var onlyScreenshots = false
    var onlyPanoramas = false
    var onlySlowMotion = false
    var onlyTimeLapse = false
    var onlyCinematic = false
    var onlyDepthEffect = false
    var hasLocation: Bool?
    var orientations: Set<AssetOrientation> = []
    var capturedRange: ClosedRange<Date>?
    var observedHiddenRange: ClosedRange<Date>?
    /// Video duration bounds in seconds; either side open.
    var minDuration: TimeInterval?
    var maxDuration: TimeInterval?
    var minMegapixels: Double?
    var viewed: Bool?
    var reviewStates: Set<ReviewState> = []
    var onlyPinned = false
    var onlyRated = false
    var minRating: Int?
    var onlyTagged = false
    var tagName: String?
    /// Videos the user started but never finished.
    var neverFinished = false

    static let none = LibraryFilter()

    var isActive: Bool { self != .none }

    /// How many distinct criteria are switched on, for the filter button's badge.
    var activeCount: Int {
        var count = 0
        if !kinds.isEmpty { count += 1 }
        if onlyFavorites { count += 1 }
        if onlyAppFavorites { count += 1 }
        if onlyLivePhotos { count += 1 }
        if onlyScreenshots { count += 1 }
        if onlyPanoramas { count += 1 }
        if onlySlowMotion { count += 1 }
        if onlyTimeLapse { count += 1 }
        if onlyCinematic { count += 1 }
        if onlyDepthEffect { count += 1 }
        if hasLocation != nil { count += 1 }
        if !orientations.isEmpty { count += 1 }
        if capturedRange != nil { count += 1 }
        if observedHiddenRange != nil { count += 1 }
        if minDuration != nil || maxDuration != nil { count += 1 }
        if minMegapixels != nil { count += 1 }
        if viewed != nil { count += 1 }
        if !reviewStates.isEmpty { count += 1 }
        if onlyPinned { count += 1 }
        if onlyRated || minRating != nil { count += 1 }
        if onlyTagged || tagName != nil { count += 1 }
        if neverFinished { count += 1 }
        return count
    }

    func matches(_ asset: HiddenAsset, meta: AssetMeta) -> Bool {
        if !kinds.isEmpty && !kinds.contains(asset.kind) { return false }
        if onlyFavorites && !asset.isFavorite { return false }
        if onlyAppFavorites && !meta.isAppFavorite { return false }
        if onlyLivePhotos && !asset.subtypes.contains(.livePhoto) { return false }
        if onlyScreenshots && !asset.subtypes.contains(.screenshot) { return false }
        if onlyPanoramas && !asset.subtypes.contains(.panorama) { return false }
        if onlySlowMotion && !asset.subtypes.contains(.slowMotion) { return false }
        if onlyTimeLapse && !asset.subtypes.contains(.timeLapse) { return false }
        if onlyCinematic && !asset.subtypes.contains(.cinematic) { return false }
        if onlyDepthEffect && !asset.subtypes.contains(.depthEffect) { return false }
        if let hasLocation, asset.hasLocation != hasLocation { return false }
        if !orientations.isEmpty && !orientations.contains(asset.orientation) { return false }
        if let capturedRange, !capturedRange.contains(asset.creationDate) { return false }
        if let observedHiddenRange {
            guard let observed = meta.firstObservedHiddenAt,
                  observedHiddenRange.contains(observed) else { return false }
        }
        if let minDuration, asset.duration < minDuration { return false }
        if let maxDuration, asset.duration > maxDuration { return false }
        if let minMegapixels, asset.megapixels < minMegapixels { return false }
        if let viewed, (meta.viewCount > 0) != viewed { return false }
        if !reviewStates.isEmpty && !reviewStates.contains(meta.reviewState) { return false }
        if onlyPinned && !meta.isPinned { return false }
        if onlyRated && meta.rating == 0 { return false }
        if let minRating, meta.rating < minRating { return false }
        if onlyTagged && meta.tagNames.isEmpty { return false }
        if let tagName, !meta.tagNames.contains(tagName) { return false }
        if neverFinished {
            guard asset.isVideo, meta.playbackPosition > 0, !meta.playbackCompleted else { return false }
        }
        return true
    }
}

/// Applies a filter and a sort to a list of assets, given a metadata lookup.
///
/// Pure and synchronous on purpose: the caller decides which thread pays for it, and the
/// tests exercise it with a 20,000-item mock without a database in sight.
enum LibraryQuery {
    static func run(_ assets: [HiddenAsset],
                    filter: LibraryFilter,
                    sort: LibrarySort,
                    meta: [String: AssetMeta],
                    randomSeed: UInt64 = 0) -> [HiddenAsset] {
        let filtered = filter.isActive
            ? assets.filter { filter.matches($0, meta: meta[$0.localIdentifier] ?? .empty) }
            : assets
        return sorted(filtered, by: sort, meta: meta, randomSeed: randomSeed)
    }

    static func sorted(_ assets: [HiddenAsset],
                       by sort: LibrarySort,
                       meta: [String: AssetMeta],
                       randomSeed: UInt64 = 0) -> [HiddenAsset] {
        func observed(_ asset: HiddenAsset) -> Date {
            meta[asset.localIdentifier]?.firstObservedHiddenAt
                ?? meta[asset.localIdentifier]?.firstSeenAt
                ?? asset.creationDate
        }

        switch sort {
        case .recentlyObserved:
            return assets.sorted { observed($0) > observed($1) }
        case .newestCaptured:
            return assets.sorted { $0.creationDate > $1.creationDate }
        case .oldestCaptured:
            return assets.sorted { $0.creationDate < $1.creationDate }
        case .newestModified:
            return assets.sorted { ($0.modificationDate ?? $0.creationDate) > ($1.modificationDate ?? $1.creationDate) }
        case .oldestModified:
            return assets.sorted { ($0.modificationDate ?? $0.creationDate) < ($1.modificationDate ?? $1.creationDate) }
        case .observedFavorite:
            return assets.sorted {
                let a = meta[$0.localIdentifier]?.firstObservedFavoriteAt ?? .distantPast
                let b = meta[$1.localIdentifier]?.firstObservedFavoriteAt ?? .distantPast
                if a != b { return a > b }
                return $0.creationDate > $1.creationDate
            }
        case .shortestVideo:
            return assets.sorted {
                if $0.duration != $1.duration { return $0.duration < $1.duration }
                return $0.creationDate > $1.creationDate
            }
        case .longestVideo:
            return assets.sorted {
                if $0.duration != $1.duration { return $0.duration > $1.duration }
                return $0.creationDate > $1.creationDate
            }
        case .photosFirst:
            return assets.sorted {
                if $0.kind != $1.kind { return $0.kind == .photo }
                return $0.creationDate > $1.creationDate
            }
        case .videosFirst:
            return assets.sorted {
                if $0.kind != $1.kind { return $0.kind == .video }
                return $0.creationDate > $1.creationDate
            }
        case .random:
            // Seeded so the order is stable while the user scrolls, and reshuffles only when
            // the seed changes — not on every recompute.
            var generator = SeededGenerator(seed: randomSeed == 0 ? 0x5EED : randomSeed)
            return assets.shuffled(using: &generator)
        }
    }
}

/// SplitMix64 — small, fast, deterministic. Shared by random sort and the shuffle engine so
/// "the same seed recreates the same sequence" is literally true across the app.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
