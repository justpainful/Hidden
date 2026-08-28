import Foundation
import Observation

/// The one place the accessible Hidden set, the metadata layer and the inbox digest meet.
///
/// Views read from here; refreshes happen here; every observation date the app records
/// (first observed hidden, first observed favourite) is written here so the rules about
/// honesty — observation time, never a pretended system timestamp — live in one file.
@MainActor
@Observable
final class LibraryModel {
    let library: PhotoLibraryProviding
    let media: MediaProviding
    let store: MetadataStore

    private(set) var assets: [HiddenAsset] = []
    private(set) var assetsByID: [String: HiddenAsset] = [:]
    private(set) var metaByID: [String: AssetMeta] = [:]
    private(set) var digest = InboxDigest()
    private(set) var isRefreshing = false
    private(set) var lastRefreshAt: Date?

    var accessState: AccessState { library.accessState }

    init(library: PhotoLibraryProviding, media: MediaProviding, store: MetadataStore) {
        self.library = library
        self.media = media
        self.store = store
    }

    func asset(for id: String) -> HiddenAsset? { assetsByID[id] }
    func meta(for id: String) -> AssetMeta { metaByID[id] ?? .empty }

    // MARK: Refresh

    /// Fetch the current accessible Hidden set, diff it against the last snapshot, update
    /// observation dates, and store a new snapshot when anything moved.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let current = await library.fetchHiddenAssets()
        let previous = store.latestSnapshot()
        let newDigest = SnapshotDiff.compare(previousIDs: previous?.assetIDs,
                                             previousFavoriteIDs: previous?.favoriteIDs ?? [],
                                             current: current)

        applyObservations(for: current, digest: newDigest)

        // Snapshot only when the set actually changed, so quiet launches stay quiet.
        let currentIDs = current.map(\.localIdentifier)
        let favoriteIDs = current.filter(\.isFavorite).map(\.localIdentifier)
        if previous == nil
            || previous?.assetIDs != currentIDs
            || previous?.favoriteIDs != favoriteIDs {
            store.saveSnapshot(assetIDs: currentIDs, favoriteIDs: favoriteIDs)
        }

        assets = current
        assetsByID = Dictionary(uniqueKeysWithValues: current.map { ($0.localIdentifier, $0) })
        digest = newDigest
        metaByID = store.metaByID()
        lastRefreshAt = .now
    }

    /// Write observation dates for what the diff found. On a baseline pass (first ever
    /// launch) the records are created but no change events are journalled — a first look
    /// at a library is not an avalanche of changes.
    private func applyObservations(for current: [HiddenAsset], digest: InboxDigest) {
        let now = Date.now
        var records: [String: AssetRecord] = [:]
        for record in store.allRecords() { records[record.assetID] = record }

        func record(for id: String) -> AssetRecord {
            if let existing = records[id] { return existing }
            let created = AssetRecord(assetID: id, firstSeenAt: now)
            store.context.insert(created)
            records[id] = created
            return created
        }

        let newlyObserved = Set(digest.newlyObserved)
        for asset in current {
            let row = record(for: asset.localIdentifier)
            if row.firstObservedHiddenAt == nil {
                row.firstObservedHiddenAt = now
                if newlyObserved.contains(asset.localIdentifier) && !digest.isBaseline {
                    store.log(.firstObservedHidden, assetID: asset.localIdentifier)
                }
            }
            row.lastObservedHiddenAt = now
            if asset.isFavorite && row.firstObservedFavoriteAt == nil {
                row.firstObservedFavoriteAt = now
                if !digest.isBaseline {
                    store.log(.becameFavorite, assetID: asset.localIdentifier)
                }
            }
        }

        if !digest.isBaseline {
            for id in digest.noLongerPresent {
                store.log(.noLongerObservedHidden, assetID: id)
            }
            for id in digest.unfavorited {
                store.log(.favoriteRemoved, assetID: id)
            }
        }
        store.save()
    }

    // MARK: User actions

    func recordView(of assetID: String) {
        store.recordView(of: assetID)
        metaByID[assetID] = store.record(for: assetID)?.meta ?? .empty
    }

    func toggleAppFavorite(_ assetID: String) {
        let current = meta(for: assetID).isAppFavorite
        store.setAppFavorite(assetID, !current)
        metaByID[assetID] = store.record(for: assetID)?.meta ?? .empty
    }

    func togglePinned(_ assetID: String) {
        let current = meta(for: assetID).isPinned
        store.setPinned(assetID, !current)
        metaByID[assetID] = store.record(for: assetID)?.meta ?? .empty
    }

    func setRating(_ assetID: String, _ rating: Int) {
        store.setRating(assetID, rating)
        metaByID[assetID] = store.record(for: assetID)?.meta ?? .empty
    }

    func setReviewState(_ assetID: String, _ state: ReviewState) {
        store.setReviewState(assetID, state)
        metaByID[assetID] = store.record(for: assetID)?.meta ?? .empty
    }

    func toggleSystemFavorite(_ assetID: String) async {
        guard let asset = assetsByID[assetID] else { return }
        do {
            try await library.setFavorite(assetID, !asset.isFavorite)
            await refresh()
        } catch {
            // The change sheet was declined or PhotoKit refused; state simply stays.
        }
    }

    func unhide(_ assetID: String) async throws {
        try await library.unhide(assetID)
        await refresh()
    }

    func delete(_ assetIDs: [String]) async throws {
        try await library.delete(assetIDs)
        await refresh()
    }
}
