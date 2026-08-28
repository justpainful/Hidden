import Foundation

/// A batch of assets first observed hidden around the same time — the app's inferred idea
/// of "one hiding session". Inferred is the operative word: these are observation-time
/// clusters, not Apple's own history, and the UI presents them as such.
struct HiddenSession: Identifiable, Equatable, Sendable {
    var id: Date { observedAt }
    /// When the earliest member of the batch was first observed.
    var observedAt: Date
    var assetIDs: [String]
    var photoCount: Int
    var videoCount: Int
    var videoSeconds: TimeInterval

    var count: Int { assetIDs.count }
}

enum SessionGrouping {
    /// Cluster by `firstObservedHiddenAt` proximity: a quiet gap longer than `gap` starts a
    /// new session. Assets with no observation date (never refreshed into the store yet)
    /// are left out rather than guessed at.
    static func sessions(assets: [HiddenAsset],
                         meta: [String: AssetMeta],
                         gap: TimeInterval = 30 * 60) -> [HiddenSession] {
        let dated: [(Date, HiddenAsset)] = assets.compactMap { asset in
            guard let observed = meta[asset.localIdentifier]?.firstObservedHiddenAt else {
                return nil
            }
            return (observed, asset)
        }
        .sorted { $0.0 < $1.0 }

        guard !dated.isEmpty else { return [] }

        var sessions: [HiddenSession] = []
        var start = dated[0].0
        var previous = dated[0].0
        var members: [(Date, HiddenAsset)] = []

        func close() {
            guard !members.isEmpty else { return }
            let videos = members.filter { $0.1.isVideo }
            sessions.append(HiddenSession(
                observedAt: start,
                assetIDs: members.map(\.1.localIdentifier),
                photoCount: members.count - videos.count,
                videoCount: videos.count,
                videoSeconds: videos.reduce(0) { $0 + $1.1.duration }))
        }

        for entry in dated {
            if entry.0.timeIntervalSince(previous) > gap {
                close()
                members = []
                start = entry.0
            }
            members.append(entry)
            previous = entry.0
        }
        close()

        return sessions.sorted { $0.observedAt > $1.observedAt }
    }
}
