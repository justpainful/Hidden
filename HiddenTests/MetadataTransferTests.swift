import Foundation
import Testing
@testable import Hidden

@MainActor
struct MetadataTransferTests {

    private func makeStore() -> MetadataStore {
        MetadataStore(context: HiddenStore.makeContainer(inMemory: true).mainContext)
    }

    @Test("Export and import round-trip the organization layer")
    func roundTrip() throws {
        let source = makeStore()
        source.setAppFavorite("a", true)
        source.setRating("a", 4)
        source.addTag("trip", to: "a")
        source.setNote("the good one", for: "a")
        source.recordView(of: "a")
        source.addSmartCollection(name: "Long Videos",
                                  filter: {
                                      var filter = LibraryFilter()
                                      filter.kinds = [.video]
                                      filter.minDuration = 300
                                      return filter
                                  }(),
                                  sort: .longestVideo)
        source.addQueue(name: "Evening", itemIDs: ["a", "b"])

        let data = try MetadataTransfer.export(store: source, includeHistory: true)

        let target = makeStore()
        let imported = try MetadataTransfer.importData(data, into: target)
        #expect(imported == 1)

        let meta = target.record(for: "a")?.meta
        #expect(meta?.isAppFavorite == true)
        #expect(meta?.rating == 4)
        #expect(meta?.tagNames.contains("trip") == true)
        #expect(meta?.viewCount == 1)
        #expect(target.note(for: "a")?.text == "the good one")

        let collections = target.allSmartCollections()
        #expect(collections.count == 1)
        #expect(collections.first?.filter.minDuration == 300)
        #expect(collections.first?.sort == .longestVideo)
        #expect(target.allQueues().first?.itemIDs == ["a", "b"])
    }

    @Test("History can be excluded from an export")
    func historyExcluded() throws {
        let source = makeStore()
        source.recordView(of: "a")
        source.setRating("a", 5)

        let data = try MetadataTransfer.export(store: source, includeHistory: false)
        let target = makeStore()
        _ = try MetadataTransfer.importData(data, into: target)

        let meta = target.record(for: "a")?.meta
        #expect(meta?.viewCount == 0)
        #expect(meta?.firstViewedAt == nil)
        #expect(meta?.rating == 5)   // organization still travels
    }

    @Test("Import merges instead of clobbering local state")
    func mergeKeepsLocal() throws {
        let source = makeStore()
        source.setRating("a", 2)
        let data = try MetadataTransfer.export(store: source, includeHistory: true)

        let target = makeStore()
        target.setRating("a", 5)
        target.setAppFavorite("a", true)
        _ = try MetadataTransfer.importData(data, into: target)

        let meta = target.record(for: "a")?.meta
        #expect(meta?.rating == 5)          // max wins
        #expect(meta?.isAppFavorite == true)
    }

    @Test("Garbage input is rejected with a readable error")
    func garbageRejected() {
        let target = makeStore()
        #expect(throws: MetadataTransferError.self) {
            _ = try MetadataTransfer.importData(Data("not json".utf8), into: target)
        }
    }
}
