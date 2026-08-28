import Foundation
import Testing
@testable import Hidden

@MainActor
struct MetadataStoreTests {

    private func makeStore() -> MetadataStore {
        MetadataStore(context: HiddenStore.makeContainer(inMemory: true).mainContext)
    }

    @Test("Recording a view sets first/last viewed and increments the count")
    func recordView() {
        let store = makeStore()
        store.recordView(of: "x")
        store.recordView(of: "x")
        let meta = store.record(for: "x")?.meta
        #expect(meta?.viewCount == 2)
        #expect(meta?.firstViewedAt != nil)
        #expect(meta?.lastViewedAt != nil)
    }

    @Test("Incognito records nothing")
    func incognitoBlocksHistory() {
        let store = makeStore()
        store.recordsHistory = false
        store.recordView(of: "x")
        store.recordShuffleExposure(of: "x")
        #expect(store.record(for: "x") == nil)
    }

    @Test("Snapshots round-trip and the latest wins")
    func snapshots() {
        let store = makeStore()
        #expect(store.latestSnapshot() == nil)
        store.saveSnapshot(assetIDs: ["a", "b"], favoriteIDs: ["a"])
        store.saveSnapshot(assetIDs: ["a", "b", "c"], favoriteIDs: [])
        let latest = store.latestSnapshot()
        #expect(latest?.assetIDs == ["a", "b", "c"])
        #expect(latest?.favoriteIDs == [])
    }

    @Test("Clearing viewing history keeps organization")
    func clearHistoryKeepsOrganization() {
        let store = makeStore()
        store.recordView(of: "x")
        store.setAppFavorite("x", true)
        store.addTag("trip", to: "x")
        store.clearViewingHistory()
        let meta = store.record(for: "x")?.meta
        #expect(meta?.viewCount == 0)
        #expect(meta?.firstViewedAt == nil)
        #expect(meta?.isAppFavorite == true)
        #expect(meta?.tagNames.contains("trip") == true)
    }

    @Test("Tags register once and detach cleanly")
    func tags() {
        let store = makeStore()
        store.addTag("sunset", to: "a")
        store.addTag("sunset", to: "b")
        store.addTag("sunset", to: "b")   // duplicate on the same asset is a no-op
        #expect(store.allTags().count == 1)
        #expect(store.record(for: "b")?.tagNames == ["sunset"])
        store.removeTag("sunset", from: "b")
        #expect(store.record(for: "b")?.tagNames.isEmpty == true)
    }

    @Test("Playback progress persists and completion resets the position")
    func playback() {
        let store = makeStore()
        store.recordPlayback(of: "v", position: 42, duration: 100, completed: false)
        var meta = store.record(for: "v")?.meta
        #expect(meta?.playbackPosition == 42)
        #expect(meta?.playbackCompleted == false)

        store.recordPlayback(of: "v", position: 100, duration: 100, completed: true)
        meta = store.record(for: "v")?.meta
        #expect(meta?.playbackPosition == 0)
        #expect(meta?.playbackCompleted == true)
    }
}
