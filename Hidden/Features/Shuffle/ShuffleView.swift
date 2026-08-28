import SwiftUI

/// Which slice of the library a shuffle draws from.
enum ShufflePool: String, CaseIterable, Identifiable {
    case all, photos, videos, favorites, appFavorites, unseen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:          return String(localized: "All Hidden")
        case .photos:       return String(localized: "Photos Only")
        case .videos:       return String(localized: "Videos Only")
        case .favorites:    return String(localized: "Favorites")
        case .appFavorites: return String(localized: "App Favorites")
        case .unseen:       return String(localized: "Unseen")
        }
    }

    func members(of assets: [HiddenAsset], meta: [String: AssetMeta]) -> [HiddenAsset] {
        switch self {
        case .all:       return assets
        case .photos:    return assets.filter { !$0.isVideo }
        case .videos:    return assets.filter(\.isVideo)
        case .favorites: return assets.filter(\.isFavorite)
        case .appFavorites:
            return assets.filter { meta[$0.localIdentifier]?.isAppFavorite == true }
        case .unseen:
            return assets.filter { (meta[$0.localIdentifier]?.viewCount ?? 0) == 0 }
        }
    }
}

enum ShuffleSessionLimit: String, CaseIterable, Identifiable {
    case none, tenMinutes, thirtyMinutes, oneHour, items25, items50

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:          return String(localized: "No Limit")
        case .tenMinutes:    return String(localized: "10 Minutes")
        case .thirtyMinutes: return String(localized: "30 Minutes")
        case .oneHour:       return String(localized: "1 Hour")
        case .items25:       return String(localized: "25 Items")
        case .items50:       return String(localized: "50 Items")
        }
    }

    var limit: ShuffleLimit? {
        switch self {
        case .none:          return nil
        case .tenMinutes:    return .duration(600)
        case .thirtyMinutes: return .duration(1_800)
        case .oneHour:       return .duration(3_600)
        case .items25:       return .count(25)
        case .items50:       return .count(50)
        }
    }
}

/// The flagship surface: build a non-repeating, optionally weighted, optionally limited
/// queue and play it. Leaving and returning resumes exactly where the session stopped.
struct ShuffleView: View {
    @Environment(\.app) private var app

    @State private var pool: ShufflePool = .all
    @State private var weighting: ShuffleWeighting = .rediscovery
    @State private var sessionLimit: ShuffleSessionLimit = .none
    @State private var photoDuration: TimeInterval = 3
    @State private var noConsecutiveVideos = false
    @State private var session: ShuffleSessionTarget?
    @State private var didLoadDefaults = false

    private var poolAssets: [HiddenAsset] {
        pool.members(of: app.model.assets, meta: app.model.metaByID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if app.model.assets.isEmpty {
                    HiddenEmptyStateView()
                } else {
                    form
                }
            }
            .navigationTitle(Text("Shuffle"))
        }
        .onAppear {
            guard !didLoadDefaults else { return }
            didLoadDefaults = true
            photoDuration = app.settings.photoDuration
        }
        .fullScreenCover(item: $session) { target in
            ShuffleSessionView(queue: target.queue,
                               startIndex: target.startIndex,
                               photoDuration: photoDuration) { session = nil }
        }
    }

    private var form: some View {
        Form {
            Section(String(localized: "Source")) {
                Picker(String(localized: "Play From"), selection: $pool) {
                    ForEach(ShufflePool.allCases) { pool in
                        Text(pool.title).tag(pool)
                    }
                }
                LabeledContent(String(localized: "In Pool"),
                               value: poolAssets.count.formatted())
            }

            Section(String(localized: "Order")) {
                Picker(String(localized: "Weighting"), selection: $weighting) {
                    ForEach(ShuffleWeighting.allCases) { weighting in
                        Text(weighting.title).tag(weighting)
                    }
                }
                Toggle(String(localized: "No Two Videos in a Row"), isOn: $noConsecutiveVideos)
            }

            Section(String(localized: "Session")) {
                Picker(String(localized: "Length"), selection: $sessionLimit) {
                    ForEach(ShuffleSessionLimit.allCases) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
                Picker(String(localized: "Photo Duration"), selection: $photoDuration) {
                    Text(String(localized: "2 Seconds")).tag(TimeInterval(2))
                    Text(String(localized: "3 Seconds")).tag(TimeInterval(3))
                    Text(String(localized: "5 Seconds")).tag(TimeInterval(5))
                    Text(String(localized: "10 Seconds")).tag(TimeInterval(10))
                }
            }

            Section {
                Button {
                    start()
                } label: {
                    Label(String(localized: "Start Shuffle"), systemImage: "shuffle")
                        .font(Typo.control)
                        .frame(maxWidth: .infinity, minHeight: Hit.min)
                }
                .disabled(poolAssets.isEmpty)

                if let saved = savedSession {
                    Button {
                        resume(saved)
                    } label: {
                        Label(String(localized: "Resume Last Session"), systemImage: "play.circle")
                            .font(Typo.control)
                            .frame(maxWidth: .infinity, minHeight: Hit.min)
                    }
                }
            }

            savedQueuesSection
        }
    }

    @ViewBuilder
    private var savedQueuesSection: some View {
        let queues = app.store.allQueues()
        if !queues.isEmpty {
            Section(String(localized: "Saved Queues")) {
                ForEach(queues, id: \.id) { queue in
                    let members = queue.itemIDs.compactMap { app.model.asset(for: $0) }
                    Button {
                        guard !members.isEmpty else { return }
                        session = ShuffleSessionTarget(queue: members, startIndex: 0)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(queue.name)
                                    .font(Typo.control)
                                    .foregroundStyle(Palette.textPrimary)
                                Text(String(localized: "\(members.count.formatted()) items"))
                                    .font(Typo.meta)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .foregroundStyle(Palette.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            app.store.deleteQueue(queue)
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: Sessions

    private func start() {
        app.settings.photoDuration = photoDuration
        let seed = UInt64.random(in: 1..<UInt64.max)
        let configuration = ShuffleConfiguration(seed: seed,
                                                 weighting: weighting,
                                                 photoDuration: photoDuration,
                                                 noConsecutiveVideos: noConsecutiveVideos,
                                                 limit: sessionLimit.limit)
        let queue = ShuffleEngine.buildQueue(from: poolAssets,
                                             meta: app.model.metaByID,
                                             configuration: configuration)
        guard !queue.isEmpty else { return }
        ShuffleSessionStore.save(ids: queue.map(\.localIdentifier), index: 0, seed: seed)
        session = ShuffleSessionTarget(queue: queue, startIndex: 0)
    }

    private var savedSession: ShuffleSessionStore.Saved? {
        ShuffleSessionStore.load()
    }

    private func resume(_ saved: ShuffleSessionStore.Saved) {
        let queue = saved.ids.compactMap { app.model.asset(for: $0) }
        guard !queue.isEmpty else {
            ShuffleSessionStore.clear()
            return
        }
        let index = min(max(saved.index, 0), queue.count - 1)
        session = ShuffleSessionTarget(queue: queue, startIndex: index)
    }
}

struct ShuffleSessionTarget: Identifiable {
    let id = UUID()
    var queue: [HiddenAsset]
    var startIndex: Int
}

/// Queue persistence, deliberately small: identifiers, position, seed. Assets that no
/// longer resolve on resume are skipped.
enum ShuffleSessionStore {
    struct Saved {
        var ids: [String]
        var index: Int
        var seed: UInt64
    }

    static func save(ids: [String], index: Int, seed: UInt64) {
        let defaults = UserDefaults.standard
        defaults.set(ids, forKey: "shuffleQueueIDs")
        defaults.set(index, forKey: "shuffleQueueIndex")
        defaults.set(String(seed), forKey: "shuffleQueueSeed")
    }

    static func saveIndex(_ index: Int) {
        UserDefaults.standard.set(index, forKey: "shuffleQueueIndex")
    }

    static func load() -> Saved? {
        let defaults = UserDefaults.standard
        guard let ids = defaults.stringArray(forKey: "shuffleQueueIDs"), !ids.isEmpty else {
            return nil
        }
        return Saved(ids: ids,
                     index: defaults.integer(forKey: "shuffleQueueIndex"),
                     seed: UInt64(defaults.string(forKey: "shuffleQueueSeed") ?? "") ?? 0)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "shuffleQueueIDs")
        defaults.removeObject(forKey: "shuffleQueueIndex")
        defaults.removeObject(forKey: "shuffleQueueSeed")
    }
}
