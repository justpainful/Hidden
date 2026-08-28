import Foundation
import Testing
@testable import Hidden

struct SnapshotDiffTests {

    @Test("No previous snapshot is a baseline, not an avalanche of changes")
    func baseline() {
        let current = [Fixture.asset("a"), Fixture.asset("b")]
        let digest = SnapshotDiff.compare(previousIDs: nil,
                                          previousFavoriteIDs: [],
                                          current: current)
        #expect(digest.isBaseline)
        #expect(digest.newlyObserved == ["a", "b"])
        #expect(digest.noLongerPresent.isEmpty)
    }

    @Test("New, gone and unchanged are classified correctly")
    func basicDiff() {
        let current = [Fixture.asset("a"), Fixture.asset("c")]
        let digest = SnapshotDiff.compare(previousIDs: ["a", "b"],
                                          previousFavoriteIDs: [],
                                          current: current)
        #expect(!digest.isBaseline)
        #expect(digest.newlyObserved == ["c"])
        #expect(digest.noLongerPresent == ["b"])
    }

    @Test("A favorite transition is noticed; a stable favorite is not")
    func favoriteTransitions() {
        let current = [
            Fixture.asset("a", favorite: true),    // was favorite — stable
            Fixture.asset("b", favorite: true),    // newly favorited
            Fixture.asset("c", favorite: false),   // unfavorited
        ]
        let digest = SnapshotDiff.compare(previousIDs: ["a", "b", "c"],
                                          previousFavoriteIDs: ["a", "c"],
                                          current: current)
        #expect(digest.newlyFavorited == ["b"])
        #expect(digest.unfavorited == ["c"])
    }

    @Test("A brand-new asset that arrives already favorited is new, not 'newly favorited'")
    func newAssetAlreadyFavorite() {
        let current = [Fixture.asset("new", favorite: true)]
        let digest = SnapshotDiff.compare(previousIDs: [],
                                          previousFavoriteIDs: [],
                                          current: current)
        #expect(digest.newlyObserved == ["new"])
        #expect(digest.newlyFavorited.isEmpty)
    }

    @Test("Identical sets produce an empty digest")
    func noChange() {
        let current = [Fixture.asset("a"), Fixture.asset("b", favorite: true)]
        let digest = SnapshotDiff.compare(previousIDs: ["a", "b"],
                                          previousFavoriteIDs: ["b"],
                                          current: current)
        #expect(digest.isEmpty)
    }

    @Test("Scale: diffing 20,000 against 20,000 with drift stays correct")
    func largeDiff() {
        let previous = MockPhotoLibrary.generate(count: 20_000, seed: 1)
        var current = previous
        current.removeFirst(50)                       // 50 gone
        let added = (0..<75).map { Fixture.asset("added\($0)") }
        current.append(contentsOf: added)             // 75 new

        let digest = SnapshotDiff.compare(previousIDs: previous.map(\.localIdentifier),
                                          previousFavoriteIDs: [],
                                          current: current)
        #expect(digest.newlyObserved.count == 75)
        #expect(digest.noLongerPresent.count == 50)
    }
}
