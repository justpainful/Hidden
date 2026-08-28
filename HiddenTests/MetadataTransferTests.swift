import Foundation
import Testing
@testable import Hidden

/// Export → wipe → import over the shared container: the exact reinstall-and-restore story
/// the backup exists for.
@MainActor
struct MetadataTransferTests {

    @Test("Export and import round-trip the organization layer")
    func roundTrip() throws {
        let store = SharedTestStore.freshStore()
        store.setAppFavorite("a", true)
        store.setRating("a", 4)
        store.addTag("trip", to: "a")
        store.setNote("the good one", for: "a")
        store.recordView(of: "a")
        var filter = LibraryFilter()
        filter.kinds = [.video]
        filter.minDuration = 300
        store.addSmartCollection(name: "Long Videos", filter: filter, sort: .longestVideo)
        store.addQueue(name: "Evening", itemIDs: ["a", "b"])

        let data = try MetadataTransfer.export(store: store, includeHistory: true)

        store.resetEverything()   // the "deleted and reinstalled" moment
        let imported = try MetadataTransfer.importData(data, into: store)
        #expect(imported == 1)

        let meta = store.record(for: "a")?.meta
        #expect(meta?.isAppFavorite == true)
        #expect(meta?.rating == 4)
        #expect(meta?.tagNames.contains("trip") == true)
        #expect(meta?.viewCount == 1)
        #expect(store.note(for: "a")?.text == "the good one")

        let collections = store.allSmartCollections()
        #expect(collections.count == 1)
        #expect(collections.first?.filter.minDuration == 300)
        #expect(collections.first?.sort == .longestVideo)
        #expect(store.allQueues().first?.itemIDs == ["a", "b"])
    }

    @Test("History can be excluded from an export")
    func historyExcluded() throws {
        let store = SharedTestStore.freshStore()
        store.recordView(of: "a")
        store.setRating("a", 5)

        let data = try MetadataTransfer.export(store: store, includeHistory: false)
        store.resetEverything()
        _ = try MetadataTransfer.importData(data, into: store)

        let meta = store.record(for: "a")?.meta
        #expect(meta?.viewCount == 0)
        #expect(meta?.firstViewedAt == nil)
        #expect(meta?.rating == 5)   // organization still travels
    }

    @Test("Import merges instead of clobbering local state")
    func mergeKeepsLocal() throws {
        let store = SharedTestStore.freshStore()
        store.setRating("a", 2)
        let data = try MetadataTransfer.export(store: store, includeHistory: true)

        store.resetEverything()
        store.setRating("a", 5)
        store.setAppFavorite("a", true)
        _ = try MetadataTransfer.importData(data, into: store)

        let meta = store.record(for: "a")?.meta
        #expect(meta?.rating == 5)          // max wins
        #expect(meta?.isAppFavorite == true)
    }

    @Test("Garbage input is rejected with a readable error")
    func garbageRejected() {
        let store = SharedTestStore.freshStore()
        #expect(throws: MetadataTransferError.self) {
            _ = try MetadataTransfer.importData(Data("not json".utf8), into: store)
        }
    }
}
