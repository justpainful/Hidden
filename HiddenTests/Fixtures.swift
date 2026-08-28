import Foundation
@testable import Hidden

/// Hand-built assets and metadata for tests that need exact control, next to the seeded
/// mock generator for tests that need scale.
enum Fixture {
    static func asset(_ id: String,
                      video: Bool = false,
                      duration: TimeInterval = 0,
                      favorite: Bool = false,
                      daysAgo: Double = 10,
                      subtypes: MediaSubtypes = [],
                      width: Int = 3024,
                      height: Int = 4032,
                      hasLocation: Bool = false) -> HiddenAsset {
        HiddenAsset(localIdentifier: id,
                    kind: video ? .video : .photo,
                    creationDate: Date(timeIntervalSince1970: 1_756_000_000 - daysAgo * 86_400),
                    modificationDate: nil,
                    pixelWidth: width,
                    pixelHeight: height,
                    duration: video ? max(duration, 10) : 0,
                    isFavorite: favorite,
                    subtypes: subtypes,
                    latitude: hasLocation ? 24.7 : nil,
                    longitude: hasLocation ? 46.6 : nil)
    }

    static func meta(viewCount: Int = 0,
                     lastViewedDaysAgo: Double? = nil,
                     appFavorite: Bool = false,
                     pinned: Bool = false,
                     rating: Int = 0,
                     review: ReviewState = .unreviewed,
                     tags: Set<String> = [],
                     playbackPosition: TimeInterval = 0,
                     playbackCompleted: Bool = false) -> AssetMeta {
        var meta = AssetMeta()
        meta.viewCount = viewCount
        meta.lastViewedAt = lastViewedDaysAgo.map {
            Date(timeIntervalSince1970: 1_756_000_000 - $0 * 86_400)
        }
        meta.isAppFavorite = appFavorite
        meta.isPinned = pinned
        meta.rating = rating
        meta.reviewState = review
        meta.tagNames = tags
        meta.playbackPosition = playbackPosition
        meta.playbackCompleted = playbackCompleted
        return meta
    }
}
