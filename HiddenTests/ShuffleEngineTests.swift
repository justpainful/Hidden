import Foundation
import Testing
@testable import Hidden

struct ShuffleEngineTests {

    private func pool(_ count: Int, videosEvery: Int = 5) -> [HiddenAsset] {
        (0..<count).map { index in
            Fixture.asset("a\(index)",
                          video: videosEvery > 0 && index % videosEvery == 0,
                          duration: 60,
                          daysAgo: Double(index))
        }
    }

    @Test("A queue is a permutation: every asset exactly once, so nothing repeats")
    func noRepeatUntilExhausted() {
        let assets = pool(500)
        let queue = ShuffleEngine.buildQueue(
            from: assets, meta: [:],
            configuration: ShuffleConfiguration(seed: 42))
        #expect(queue.count == assets.count)
        #expect(Set(queue.map(\.localIdentifier)).count == assets.count)
    }

    @Test("The same seed recreates the same sequence")
    func seededShuffleIsDeterministic() {
        let assets = pool(200)
        let first = ShuffleEngine.buildQueue(
            from: assets, meta: [:],
            configuration: ShuffleConfiguration(seed: 7, weighting: .trueRandom))
        let second = ShuffleEngine.buildQueue(
            from: assets, meta: [:],
            configuration: ShuffleConfiguration(seed: 7, weighting: .trueRandom))
        #expect(first.map(\.localIdentifier) == second.map(\.localIdentifier))
    }

    @Test("Different seeds produce different orders")
    func differentSeedsDiffer() {
        let assets = pool(200)
        let first = ShuffleEngine.buildQueue(
            from: assets, meta: [:],
            configuration: ShuffleConfiguration(seed: 1, weighting: .trueRandom))
        let second = ShuffleEngine.buildQueue(
            from: assets, meta: [:],
            configuration: ShuffleConfiguration(seed: 2, weighting: .trueRandom))
        #expect(first.map(\.localIdentifier) != second.map(\.localIdentifier))
    }

    @Test("Weighted shuffle is also a full permutation")
    func weightedIsPermutation() {
        let assets = pool(300)
        var meta: [String: AssetMeta] = [:]
        for asset in assets.prefix(100) {
            meta[asset.localIdentifier] = Fixture.meta(viewCount: 5, lastViewedDaysAgo: 1)
        }
        let queue = ShuffleEngine.buildQueue(
            from: assets, meta: meta,
            configuration: ShuffleConfiguration(seed: 9, weighting: .rediscovery))
        #expect(Set(queue.map(\.localIdentifier)).count == assets.count)
    }

    @Test("Rediscovery pushes the just-seen towards the back on average")
    func rediscoveryBiasHolds() {
        let assets = pool(400, videosEvery: 0)
        var meta: [String: AssetMeta] = [:]
        // First half: heavily viewed five minutes ago. Second half: never viewed.
        for asset in assets.prefix(200) {
            meta[asset.localIdentifier] = Fixture.meta(viewCount: 10, lastViewedDaysAgo: 0)
        }
        let queue = ShuffleEngine.buildQueue(
            from: assets, meta: meta,
            configuration: ShuffleConfiguration(seed: 5, weighting: .rediscovery))

        // Average position of unseen assets should be clearly earlier than the seen ones.
        var seenPositions: [Int] = [], unseenPositions: [Int] = []
        for (position, asset) in queue.enumerated() {
            if meta[asset.localIdentifier] != nil {
                seenPositions.append(position)
            } else {
                unseenPositions.append(position)
            }
        }
        let seenAverage = Double(seenPositions.reduce(0, +)) / Double(seenPositions.count)
        let unseenAverage = Double(unseenPositions.reduce(0, +)) / Double(unseenPositions.count)
        #expect(unseenAverage < seenAverage)
    }

    @Test("A count limit caps the queue")
    func countLimit() {
        let queue = ShuffleEngine.buildQueue(
            from: pool(100), meta: [:],
            configuration: ShuffleConfiguration(seed: 3, limit: .count(25)))
        #expect(queue.count == 25)
    }

    @Test("A duration limit approximately fits the target")
    func durationLimit() {
        // 60-second videos and 3-second photos; a 10-minute session.
        let queue = ShuffleEngine.buildQueue(
            from: pool(500, videosEvery: 3), meta: [:],
            configuration: ShuffleConfiguration(seed: 11, photoDuration: 3,
                                                limit: .duration(600)))
        let total = ShuffleEngine.estimatedDuration(of: queue, photoDuration: 3)
        #expect(total <= 600)
        #expect(total > 300)   // not pathologically under-filled
    }

    @Test("No two videos consecutively when photos allow the spacing")
    func videoSpacing() {
        let assets = pool(300, videosEvery: 4)   // 25% videos — spacing is possible
        let queue = ShuffleEngine.buildQueue(
            from: assets, meta: [:],
            configuration: ShuffleConfiguration(seed: 21, noConsecutiveVideos: true))
        #expect(queue.count == assets.count)
        for pair in zip(queue, queue.dropFirst()) {
            #expect(!(pair.0.isVideo && pair.1.isVideo))
        }
    }

    @Test("Spacing holds even at the tight bound of videos = photos + 1")
    func videoSpacingTightBound() {
        let assets = (0..<11).map { index in
            Fixture.asset("t\(index)", video: index < 6, duration: 30)   // 6 videos, 5 photos
        }
        let spaced = ShuffleEngine.spacingVideos(assets)
        #expect(spaced.count == assets.count)
        for pair in zip(spaced, spaced.dropFirst()) {
            #expect(!(pair.0.isVideo && pair.1.isVideo))
        }
    }

    @Test("With more videos than the bound, nothing is dropped and the rule bends at the end")
    func videoSpacingOverflow() {
        let assets = (0..<10).map { index in
            Fixture.asset("o\(index)", video: index < 8, duration: 30)   // 8 videos, 2 photos
        }
        let spaced = ShuffleEngine.spacingVideos(assets)
        #expect(spaced.count == assets.count)
        #expect(Set(spaced.map(\.localIdentifier)).count == assets.count)
    }

    @Test("An empty pool produces an empty queue, not a crash")
    func emptyPool() {
        let queue = ShuffleEngine.buildQueue(
            from: [], meta: [:],
            configuration: ShuffleConfiguration(seed: 1))
        #expect(queue.isEmpty)
    }

    @Test("Scale: a 20,000-item weighted queue builds and stays a permutation")
    func largeScale() {
        let assets = MockPhotoLibrary.generate(count: 20_000, seed: 3)
        let queue = ShuffleEngine.buildQueue(
            from: assets, meta: [:],
            configuration: ShuffleConfiguration(seed: 8, weighting: .rediscovery))
        #expect(queue.count == 20_000)
        #expect(Set(queue.map(\.localIdentifier)).count == 20_000)
    }
}
