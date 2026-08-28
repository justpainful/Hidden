import Foundation

/// What changed between the last time the app looked at the Hidden set and now.
///
/// Pure value arithmetic over identifier sets — no PhotoKit, no database — which is what
/// makes the inbox testable with twenty thousand synthetic assets.
struct InboxDigest: Sendable, Equatable {
    /// Assets present now that the previous snapshot did not contain.
    var newlyObserved: [String] = []
    /// Assets the previous snapshot contained that are gone from the accessible set now.
    /// Gone can mean unhidden, deleted, or made inaccessible — the app cannot tell which,
    /// and the UI says "no longer here" rather than guessing.
    var noLongerPresent: [String] = []
    /// Assets that became favourites since the previous snapshot.
    var newlyFavorited: [String] = []
    /// Assets whose favourite state was cleared since the previous snapshot.
    var unfavorited: [String] = []
    /// True when there was no previous snapshot at all — first launch, or after a reset.
    /// Everything is technically "new" then, and the inbox should present it as a baseline
    /// rather than as an avalanche of changes.
    var isBaseline = false

    var isEmpty: Bool {
        newlyObserved.isEmpty && noLongerPresent.isEmpty
            && newlyFavorited.isEmpty && unfavorited.isEmpty
    }
}

enum SnapshotDiff {
    /// Compare the previous snapshot against the current accessible set.
    ///
    /// Order in the outputs follows the order of `current`, so "newest first" in the caller
    /// stays newest first here without a second sort.
    static func compare(previousIDs: [String]?,
                        previousFavoriteIDs: [String],
                        current: [HiddenAsset]) -> InboxDigest {
        var digest = InboxDigest()

        guard let previousIDs else {
            digest.isBaseline = true
            digest.newlyObserved = current.map(\.localIdentifier)
            return digest
        }

        let previousSet = Set(previousIDs)
        let previousFavorites = Set(previousFavoriteIDs)
        let currentIDs = Set(current.map(\.localIdentifier))

        for asset in current {
            let id = asset.localIdentifier
            if !previousSet.contains(id) {
                digest.newlyObserved.append(id)
            }
            if asset.isFavorite && !previousFavorites.contains(id) && previousSet.contains(id) {
                digest.newlyFavorited.append(id)
            }
            if !asset.isFavorite && previousFavorites.contains(id) {
                digest.unfavorited.append(id)
            }
        }

        digest.noLongerPresent = previousIDs.filter { !currentIDs.contains($0) }
        return digest
    }
}
