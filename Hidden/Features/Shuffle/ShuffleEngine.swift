import Foundation

/// How strongly the engine favours long-unseen media, or not at all.
enum ShuffleWeighting: String, CaseIterable, Identifiable, Sendable {
    /// Every asset equally likely. A separate, honest mode — not "weighting off-ish".
    case trueRandom
    /// Favour unseen, long-unseen, old and under-exposed media so a big library keeps
    /// surfacing things the user has forgotten instead of last week's items again.
    case rediscovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trueRandom:  return String(localized: "True Random")
        case .rediscovery: return String(localized: "Rediscovery")
        }
    }
}

/// An optional ceiling on a shuffle session.
enum ShuffleLimit: Equatable, Sendable {
    /// At most this many items.
    case count(Int)
    /// A queue that approximately fits this many seconds, counting each photo at the
    /// configured photo duration and each video at its own length.
    case duration(TimeInterval)
}

struct ShuffleConfiguration: Sendable {
    /// The seed decides everything: the same seed over the same pool recreates the same
    /// sequence, which is what makes "resume" and "replay" literal.
    var seed: UInt64
    var weighting: ShuffleWeighting = .rediscovery
    /// Seconds a photo stays on screen during playback.
    var photoDuration: TimeInterval = 3
    /// When true, the queue is rearranged so no two videos play back to back (where the mix
    /// makes that possible).
    var noConsecutiveVideos = false
    var limit: ShuffleLimit?
}

/// Builds shuffle queues. Pure functions only — the queue is a permutation of the pool, so
/// no-repeat is a property of the structure, not a bookkeeping promise: nothing repeats until
/// the pool is exhausted, and "previous" is simply the previous index.
enum ShuffleEngine {
    /// The full ordered queue for a pool under a configuration.
    static func buildQueue(from pool: [HiddenAsset],
                           meta: [String: AssetMeta],
                           configuration: ShuffleConfiguration) -> [HiddenAsset] {
        guard !pool.isEmpty else { return [] }
        var rng = SeededGenerator(seed: configuration.seed)

        var ordered: [HiddenAsset]
        switch configuration.weighting {
        case .trueRandom:
            ordered = pool.shuffled(using: &rng)
        case .rediscovery:
            ordered = weightedOrder(pool, meta: meta, rng: &rng)
        }

        if configuration.noConsecutiveVideos {
            ordered = spacingVideos(ordered)
        }

        if let limit = configuration.limit {
            ordered = applying(limit, to: ordered, photoDuration: configuration.photoDuration)
        }
        return ordered
    }

    /// The estimated playback length of a queue, for "give me 30 minutes" summaries.
    static func estimatedDuration(of queue: [HiddenAsset], photoDuration: TimeInterval) -> TimeInterval {
        queue.reduce(0) { $0 + ($1.isVideo ? max($1.duration, 1) : photoDuration) }
    }

    // MARK: Weighting

    /// A full weighted order via the exponential-sort trick: draw one key per asset,
    /// `-ln(U)/w`, and sort ascending. Equivalent to repeated weighted sampling without
    /// replacement, in one pass, deterministic under the seed.
    private static func weightedOrder(_ pool: [HiddenAsset],
                                      meta: [String: AssetMeta],
                                      rng: inout SeededGenerator) -> [HiddenAsset] {
        let now = pool.map(\.creationDate).max() ?? Date.now
        let keyed = pool.map { asset -> (Double, HiddenAsset) in
            let weight = rediscoveryWeight(for: asset, meta: meta[asset.localIdentifier] ?? .empty, now: now)
            let uniform = Double(rng.next() >> 11) / Double(1 << 53)   // (0, 1)
            let key = -log(max(uniform, .leastNormalMagnitude)) / weight
            return (key, asset)
        }
        return keyed.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Not a ranking of worth — only a bias away from what was just seen.
    static func rediscoveryWeight(for asset: HiddenAsset, meta: AssetMeta, now: Date) -> Double {
        var weight = 1.0

        if let lastViewed = meta.lastViewedAt {
            // Seen five minutes ago is heavily suppressed; seen a year ago is fully back.
            let days = max(now.timeIntervalSince(lastViewed) / 86_400, 0)
            weight *= min(0.15 + days / 60, 1.0)
        } else {
            weight *= 2.0   // never viewed in this app
        }

        weight *= 1.0 / (1.0 + Double(meta.viewCount) * 0.15)
        weight *= 1.0 / (1.0 + Double(meta.shuffleExposureCount) * 0.25)

        // Old media gets a mild lift, capped so ancient does not dominate.
        let ageYears = max(now.timeIntervalSince(asset.creationDate) / 31_557_600, 0)
        weight *= 1.0 + min(ageYears * 0.1, 0.5)

        if asset.isFavorite || meta.isAppFavorite { weight *= 1.2 }

        return max(weight, 0.001)
    }

    // MARK: Mix rules

    /// Rearranges so no two videos are adjacent, keeping relative order within each kind.
    /// When there are too many videos for the photos available, the leftovers run at the end
    /// back to back — the rule bends rather than dropping media silently.
    static func spacingVideos(_ queue: [HiddenAsset]) -> [HiddenAsset] {
        let videos = queue.filter(\.isVideo)
        let photos = queue.filter { !$0.isVideo }
        guard videos.count > 1, !photos.isEmpty else { return queue }

        var result: [HiddenAsset] = []
        result.reserveCapacity(queue.count)
        var videoIterator = videos.makeIterator()
        var photoIterator = photos.makeIterator()
        var lastWasVideo = false

        for original in queue {
            if original.isVideo && lastWasVideo, let photo = photoIterator.next() {
                result.append(photo)
                lastWasVideo = false
            }
            // Draw from the same kind the original slot held, preserving the shuffle's
            // large-scale shape.
            if original.isVideo {
                if let video = videoIterator.next() {
                    result.append(video)
                    lastWasVideo = true
                }
            } else if let photo = photoIterator.next() {
                result.append(photo)
                lastWasVideo = false
            }
        }
        // Whatever remains of either kind.
        while let video = videoIterator.next() { result.append(video) }
        while let photo = photoIterator.next() { result.append(photo) }
        return result
    }

    // MARK: Limits

    private static func applying(_ limit: ShuffleLimit,
                                 to queue: [HiddenAsset],
                                 photoDuration: TimeInterval) -> [HiddenAsset] {
        switch limit {
        case .count(let count):
            return Array(queue.prefix(max(count, 0)))
        case .duration(let target):
            var total: TimeInterval = 0
            var result: [HiddenAsset] = []
            for asset in queue {
                let cost = asset.isVideo ? max(asset.duration, 1) : photoDuration
                if !result.isEmpty && total + cost > target { continue }
                // Skip-but-continue rather than break: a long video early on should not end
                // a thirty-minute session at minute two when short items still fit.
                if total + cost <= target || result.isEmpty {
                    result.append(asset)
                    total += cost
                }
                if total >= target { break }
            }
            return result
        }
    }
}
