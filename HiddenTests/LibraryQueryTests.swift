import Foundation
import Testing
@testable import Hidden

struct LibraryQueryTests {

    @Test("Composed filters AND together")
    func composedFilters() {
        let assets = [
            Fixture.asset("longFavVideo", video: true, duration: 400, favorite: true),
            Fixture.asset("shortFavVideo", video: true, duration: 30, favorite: true),
            Fixture.asset("longVideo", video: true, duration: 400),
            Fixture.asset("favPhoto", favorite: true),
        ]
        var filter = LibraryFilter()
        filter.kinds = [.video]
        filter.onlyFavorites = true
        filter.minDuration = 300

        let result = LibraryQuery.run(assets, filter: filter,
                                      sort: .newestCaptured, meta: [:])
        #expect(result.map(\.localIdentifier) == ["longFavVideo"])
    }

    @Test("Metadata-backed filters read the lookup")
    func metaFilters() {
        let assets = [Fixture.asset("seen"), Fixture.asset("unseen"), Fixture.asset("later")]
        let meta: [String: AssetMeta] = [
            "seen": Fixture.meta(viewCount: 3),
            "later": Fixture.meta(review: .reviewLater),
        ]

        var neverViewed = LibraryFilter()
        neverViewed.viewed = false
        #expect(Set(LibraryQuery.run(assets, filter: neverViewed, sort: .newestCaptured, meta: meta)
            .map(\.localIdentifier)) == ["unseen", "later"])

        var reviewLater = LibraryFilter()
        reviewLater.reviewStates = [.reviewLater]
        #expect(LibraryQuery.run(assets, filter: reviewLater, sort: .newestCaptured, meta: meta)
            .map(\.localIdentifier) == ["later"])
    }

    @Test("Never-finished means started but not completed, videos only")
    func neverFinished() {
        let assets = [
            Fixture.asset("half", video: true, duration: 100),
            Fixture.asset("done", video: true, duration: 100),
            Fixture.asset("untouched", video: true, duration: 100),
            Fixture.asset("photo"),
        ]
        let meta: [String: AssetMeta] = [
            "half": Fixture.meta(playbackPosition: 50),
            "done": Fixture.meta(playbackPosition: 0, playbackCompleted: true),
            "photo": Fixture.meta(playbackPosition: 5),
        ]
        var filter = LibraryFilter()
        filter.neverFinished = true
        #expect(LibraryQuery.run(assets, filter: filter, sort: .newestCaptured, meta: meta)
            .map(\.localIdentifier) == ["half"])
    }

    @Test("Duration sorts break ties by recency and order correctly")
    func durationSorts() {
        let assets = [
            Fixture.asset("long", video: true, duration: 900, daysAgo: 3),
            Fixture.asset("short", video: true, duration: 20, daysAgo: 1),
            Fixture.asset("middle", video: true, duration: 300, daysAgo: 2),
        ]
        #expect(LibraryQuery.sorted(assets, by: .shortestVideo, meta: [:])
            .map(\.localIdentifier) == ["short", "middle", "long"])
        #expect(LibraryQuery.sorted(assets, by: .longestVideo, meta: [:])
            .map(\.localIdentifier) == ["long", "middle", "short"])
    }

    @Test("Random sort is stable under one seed and different under another")
    func randomSortSeeded() {
        let assets = (0..<100).map { Fixture.asset("a\($0)") }
        let first = LibraryQuery.sorted(assets, by: .random, meta: [:], randomSeed: 4)
        let second = LibraryQuery.sorted(assets, by: .random, meta: [:], randomSeed: 4)
        let third = LibraryQuery.sorted(assets, by: .random, meta: [:], randomSeed: 5)
        #expect(first.map(\.localIdentifier) == second.map(\.localIdentifier))
        #expect(first.map(\.localIdentifier) != third.map(\.localIdentifier))
    }

    @Test("Orientation is derived from pixel dimensions")
    func orientation() {
        #expect(Fixture.asset("p", width: 3024, height: 4032).orientation == .portrait)
        #expect(Fixture.asset("l", width: 4032, height: 3024).orientation == .landscape)
        #expect(Fixture.asset("s", width: 2048, height: 2048).orientation == .square)
    }

    @Test("Scale: filtering and sorting 20,000 items returns quickly and correctly")
    func largeScale() {
        let assets = MockPhotoLibrary.generate(count: 20_000, seed: 2)
        var filter = LibraryFilter()
        filter.kinds = [.video]

        let clock = ContinuousClock()
        var result: [HiddenAsset] = []
        let elapsed = clock.measure {
            result = LibraryQuery.run(assets, filter: filter, sort: .longestVideo, meta: [:])
        }
        #expect(!result.isEmpty)
        // A closure rather than `\.isVideo` as a function: the new typed-throws stdlib
        // signatures make key-path-as-function conversions read as throwing inside the
        // #expect macro's rewrite, which fails to compile.
        #expect(result.allSatisfy { $0.isVideo })
        // Ordered by duration descending.
        for pair in zip(result, result.dropFirst()) {
            #expect(pair.0.duration >= pair.1.duration)
        }
        // Generous ceiling: this is a responsiveness guard, not a benchmark.
        #expect(elapsed < .seconds(2))
    }

    @Test("The mock generator is deterministic")
    func mockDeterminism() {
        let first = MockPhotoLibrary.generate(count: 500, seed: 9)
        let second = MockPhotoLibrary.generate(count: 500, seed: 9)
        #expect(first == second)
        #expect(first.contains { $0.isVideo })
        #expect(first.contains { $0.isFavorite })
        #expect(first.contains { !$0.isVideo })
    }
}
