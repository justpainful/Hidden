import Foundation

/// Relations the app can honestly compute from public metadata: capture-time proximity,
/// same calendar day, shared tags, the same observed session. No claims beyond that.
enum RelatedFinder {
    static func related(to asset: HiddenAsset,
                        in assets: [HiddenAsset],
                        meta: [String: AssetMeta],
                        limit: Int = 40) -> [HiddenAsset] {
        let calendar = Calendar.current
        let anchorTags = meta[asset.localIdentifier]?.tagNames ?? []
        let anchorObserved = meta[asset.localIdentifier]?.firstObservedHiddenAt

        var scored: [(Double, HiddenAsset)] = []
        for candidate in assets where candidate.localIdentifier != asset.localIdentifier {
            var score = 0.0

            let gap = abs(candidate.creationDate.timeIntervalSince(asset.creationDate))
            if gap < 10 * 60 { score += 3 }               // same shooting moment
            else if calendar.isDate(candidate.creationDate,
                                    inSameDayAs: asset.creationDate) { score += 1.5 }

            if let anchorObserved,
               let observed = meta[candidate.localIdentifier]?.firstObservedHiddenAt,
               abs(observed.timeIntervalSince(anchorObserved)) < 30 * 60 {
                score += 1                                 // hidden in the same session
            }

            if !anchorTags.isEmpty,
               !(meta[candidate.localIdentifier]?.tagNames.isDisjoint(with: anchorTags) ?? true) {
                score += 2                                 // shares a tag
            }

            if score > 0 { scored.append((score, candidate)) }
        }

        return scored
            .sorted {
                if $0.0 != $1.0 { return $0.0 > $1.0 }
                return $0.1.creationDate > $1.1.creationDate
            }
            .prefix(limit)
            .map(\.1)
    }
}

/// A stack: a run of stills captured in one short burst of activity. Detection is
/// deliberately conservative — capture-time adjacency only, since that is the one signal
/// public metadata actually provides.
struct AssetStack: Identifiable, Equatable, Sendable {
    var id: String { assets.first?.localIdentifier ?? "empty" }
    var assets: [HiddenAsset]
    var count: Int { assets.count }
    var cover: HiddenAsset? { assets.first }
}

enum StackGrouping {
    /// Photos captured within `gap` seconds of the previous one chain into a stack; stacks
    /// under `minimumCount` are noise and are dropped. Videos never stack.
    static func stacks(in assets: [HiddenAsset],
                       gap: TimeInterval = 12,
                       minimumCount: Int = 3) -> [AssetStack] {
        let photos = assets.filter { !$0.isVideo }
            .sorted { $0.creationDate < $1.creationDate }
        guard photos.count >= minimumCount else { return [] }

        var stacks: [AssetStack] = []
        var current: [HiddenAsset] = []

        func close() {
            if current.count >= minimumCount {
                // Newest first, matching every other surface.
                stacks.append(AssetStack(assets: current.reversed()))
            }
            current = []
        }

        for photo in photos {
            if let last = current.last,
               photo.creationDate.timeIntervalSince(last.creationDate) > gap {
                close()
            }
            current.append(photo)
        }
        close()

        return stacks.sorted {
            ($0.cover?.creationDate ?? .distantPast) > ($1.cover?.creationDate ?? .distantPast)
        }
    }
}

/// Possible duplicates, conservatively: identical capture second, identical pixel
/// dimensions, same kind. The label is "possible" because that is all the evidence says —
/// nothing here reads pixels, and nothing here ever deletes.
enum DuplicateFinder {
    static func possibleDuplicateGroups(in assets: [HiddenAsset]) -> [[HiddenAsset]] {
        var groups: [String: [HiddenAsset]] = [:]
        for asset in assets {
            let second = Int(asset.creationDate.timeIntervalSince1970)
            let key = "\(second)|\(asset.pixelWidth)x\(asset.pixelHeight)|\(asset.kind.rawValue)"
            groups[key, default: []].append(asset)
        }
        return groups.values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.creationDate ?? .distantPast) > ($1.first?.creationDate ?? .distantPast) }
    }
}
