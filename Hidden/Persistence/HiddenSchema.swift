import Foundation
import SwiftData

/// The app's metadata layer. Only identifiers and small values live here — never media.
/// Deleting this database loses tags and history, not photographs.
@Model
final class AssetRecord {
    /// PhotoKit's `localIdentifier`. Unique: one row per asset.
    @Attribute(.unique) var assetID: String

    // Observation dates. PhotoKit exposes no historical "hidden date" or "favorite date", so
    // the app records when *it* first observed each state and never pretends otherwise.
    var firstSeenAt: Date
    var firstObservedHiddenAt: Date?
    var lastObservedHiddenAt: Date?
    var firstObservedFavoriteAt: Date?

    // Viewing history (only written when history is enabled and not incognito).
    var firstViewedAt: Date?
    var lastViewedAt: Date?
    var viewCount: Int
    var shuffleExposureCount: Int

    // Private organization.
    var reviewStateRaw: String
    var isAppFavorite: Bool
    var isPinned: Bool
    /// 0 = unrated, 1...5 stars.
    var rating: Int
    var tagNames: [String]

    // Playback.
    var playbackPosition: TimeInterval
    var playbackDuration: TimeInterval
    var playbackCompleted: Bool
    var lastPlaybackAt: Date?

    // Optional on-device intelligence. Nil means "not indexed yet"; empty means "indexed,
    // nothing found". Cleared wholesale when the user clears the index.
    var ocrText: String?

    init(assetID: String, firstSeenAt: Date = .now) {
        self.assetID = assetID
        self.firstSeenAt = firstSeenAt
        self.viewCount = 0
        self.shuffleExposureCount = 0
        self.reviewStateRaw = ReviewState.unreviewed.rawValue
        self.isAppFavorite = false
        self.isPinned = false
        self.rating = 0
        self.tagNames = []
        self.playbackPosition = 0
        self.playbackDuration = 0
        self.playbackCompleted = false
    }

    var reviewState: ReviewState {
        get { ReviewState(rawValue: reviewStateRaw) ?? .unreviewed }
        set { reviewStateRaw = newValue.rawValue }
    }

    /// The plain-value snapshot the query layer consumes.
    var meta: AssetMeta {
        AssetMeta(firstSeenAt: firstSeenAt,
                  firstObservedHiddenAt: firstObservedHiddenAt,
                  firstObservedFavoriteAt: firstObservedFavoriteAt,
                  firstViewedAt: firstViewedAt,
                  lastViewedAt: lastViewedAt,
                  viewCount: viewCount,
                  shuffleExposureCount: shuffleExposureCount,
                  reviewState: reviewState,
                  isAppFavorite: isAppFavorite,
                  isPinned: isPinned,
                  rating: rating,
                  tagNames: Set(tagNames),
                  playbackPosition: playbackPosition,
                  playbackCompleted: playbackCompleted,
                  ocrText: ocrText)
    }
}

/// The registry of tag names the user has created, so the tag picker can list them even when
/// nothing currently carries one.
@Model
final class TagRecord {
    @Attribute(.unique) var name: String
    var createdAt: Date

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

@Model
final class AssetNote {
    var assetID: String
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(assetID: String, text: String, createdAt: Date = .now) {
        self.assetID = assetID
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class VideoBookmark {
    var assetID: String
    var timestamp: TimeInterval
    var note: String
    var createdAt: Date

    init(assetID: String, timestamp: TimeInterval, note: String = "", createdAt: Date = .now) {
        self.assetID = assetID
        self.timestamp = timestamp
        self.note = note
        self.createdAt = createdAt
    }
}

/// A user-defined dynamic collection. The rules are the codable form of `LibraryFilter`,
/// stored as JSON so the schema does not have to change when a criterion is added.
@Model
final class SmartCollectionRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var rulesData: Data
    var sortRaw: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, rulesData: Data, sort: LibrarySort, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.rulesData = rulesData
        self.sortRaw = sort.rawValue
        self.createdAt = createdAt
    }

    var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recentlyObserved }

    /// Rules that fail to decode fall back to "match everything" rather than crashing a
    /// collection created by a newer version of the app.
    var filter: LibraryFilter {
        (try? JSONDecoder().decode(LibraryFilter.self, from: rulesData)) ?? .none
    }
}

/// A queue is references and order — never copies of media.
@Model
final class QueueRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    /// Ordered asset identifiers. An identifier that no longer resolves is skipped gracefully.
    var itemIDs: [String]
    var currentIndex: Int
    /// Shuffle seed, when this queue was produced by the shuffle engine; 0 means unordered.
    /// Stored as the bit pattern of the `UInt64` seed — the underlying store has no unsigned
    /// 64-bit type, and a seed is an opaque number, not a quantity.
    var seedBits: Int64
    var isSaved: Bool

    init(id: UUID = UUID(), name: String, itemIDs: [String] = [], seed: UInt64 = 0,
         isSaved: Bool = true, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.itemIDs = itemIDs
        self.currentIndex = 0
        self.seedBits = Int64(bitPattern: seed)
        self.isSaved = isSaved
        self.createdAt = createdAt
    }

    var seed: UInt64 {
        get { UInt64(bitPattern: seedBits) }
        set { seedBits = Int64(bitPattern: newValue) }
    }
}

/// A lightweight record of what the accessible Hidden set looked like at one moment: the
/// identifiers and which of them were favourites. This is what makes the inbox diff possible
/// across launches, since the app cannot rely on receiving change events while terminated.
@Model
final class LibrarySnapshotRecord {
    var timestamp: Date
    var assetIDs: [String]
    var favoriteIDs: [String]

    init(timestamp: Date = .now, assetIDs: [String], favoriteIDs: [String]) {
        self.timestamp = timestamp
        self.assetIDs = assetIDs
        self.favoriteIDs = favoriteIDs
    }
}

/// The local change journal. Optional, clearable, never required for correctness.
@Model
final class ChangeEventRecord {
    var timestamp: Date
    var kindRaw: String
    var assetID: String?

    init(kind: ChangeEventKind, assetID: String? = nil, timestamp: Date = .now) {
        self.kindRaw = kind.rawValue
        self.assetID = assetID
        self.timestamp = timestamp
    }

    var kind: ChangeEventKind { ChangeEventKind(rawValue: kindRaw) ?? .other }
}

enum ChangeEventKind: String, Codable, Sendable {
    case firstObservedHidden
    case noLongerObservedHidden
    case becameFavorite
    case favoriteRemoved
    case firstViewed
    case reviewed
    case appFavoriteAdded
    case appFavoriteRemoved
    case tagAdded
    case tagRemoved
    case queueCreated
    case playbackCompleted
    case other
}
