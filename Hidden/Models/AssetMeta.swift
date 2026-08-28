import Foundation

/// The app's own metadata for one asset, as a plain value.
///
/// This is a snapshot of `AssetRecord` (the SwiftData row) that filters, sorting and the
/// shuffle engine can consume without touching the database or the main actor. Missing
/// metadata — an asset the app has never touched — is represented by `.none` at call sites,
/// and every predicate treats that as "all counters zero".
struct AssetMeta: Sendable, Hashable {
    var firstSeenAt: Date?
    var firstObservedHiddenAt: Date?
    var firstObservedFavoriteAt: Date?
    var firstViewedAt: Date?
    var lastViewedAt: Date?
    var viewCount: Int = 0
    var shuffleExposureCount: Int = 0
    var reviewState: ReviewState = .unreviewed
    var isAppFavorite: Bool = false
    var isPinned: Bool = false
    /// 0 means unrated; 1...5 are stars.
    var rating: Int = 0
    var tagNames: Set<String> = []
    /// Seconds into the video the user last stopped at.
    var playbackPosition: TimeInterval = 0
    var playbackCompleted: Bool = false
    /// On-device recognized text, when the optional index has run over this asset.
    var ocrText: String?

    static let empty = AssetMeta()
}

enum ReviewState: String, Sendable, Hashable, Codable, CaseIterable {
    case unreviewed
    case reviewed
    case reviewLater
}
