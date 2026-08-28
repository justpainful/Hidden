import SwiftUI

/// A dynamic collection Discover can compute from the current assets and app metadata.
/// Pure functions, so the whole surface is testable against the mock.
enum DiscoverCollection: String, CaseIterable, Identifiable {
    case continueWatching
    case recentlyViewed
    case unseen
    case forgotten
    case buried
    case seenOnce
    case mostViewed
    case oldFavorites
    case forgottenVideos
    case recentlyFinished
    case deepArchive
    case sameDayOtherYears
    case oneFromEveryMonth
    case appFavorites
    case pinned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueWatching:  return String(localized: "Continue Watching")
        case .recentlyViewed:    return String(localized: "Recently Viewed")
        case .recentlyFinished:  return String(localized: "Recently Finished")
        case .unseen:            return String(localized: "Unseen")
        case .forgotten:         return String(localized: "Forgotten")
        case .buried:            return String(localized: "Buried")
        case .seenOnce:          return String(localized: "Seen Once")
        case .mostViewed:        return String(localized: "Most Viewed")
        case .oldFavorites:      return String(localized: "Old Favorites")
        case .forgottenVideos:   return String(localized: "Forgotten Videos")
        case .deepArchive:       return String(localized: "Deep Archive")
        case .sameDayOtherYears: return String(localized: "On This Day")
        case .oneFromEveryMonth: return String(localized: "One From Every Month")
        case .appFavorites:      return String(localized: "App Favorites")
        case .pinned:            return String(localized: "Pinned")
        }
    }

    var subtitle: String {
        switch self {
        case .continueWatching:  return String(localized: "Videos you started but didn't finish")
        case .recentlyViewed:    return String(localized: "What you opened lately")
        case .recentlyFinished:  return String(localized: "Videos played to the end recently")
        case .unseen:            return String(localized: "Never opened in this app")
        case .forgotten:         return String(localized: "Not viewed in over 90 days")
        case .buried:            return String(localized: "Old, never viewed, not a favorite")
        case .seenOnce:          return String(localized: "Viewed exactly once")
        case .mostViewed:        return String(localized: "Your highest view counts")
        case .oldFavorites:      return String(localized: "Favorites you haven't seen lately")
        case .forgottenVideos:   return String(localized: "Videos not played in a while")
        case .deepArchive:       return String(localized: "The oldest hidden media")
        case .sameDayOtherYears: return String(localized: "Captured on this date in past years")
        case .oneFromEveryMonth: return String(localized: "A sample across time")
        case .appFavorites:      return String(localized: "Your private favorites")
        case .pinned:            return String(localized: "Pinned in this app")
        }
    }

    var symbol: String {
        switch self {
        case .continueWatching:  return "play.circle"
        case .recentlyViewed:    return "clock"
        case .recentlyFinished:  return "checkmark.circle"
        case .unseen:            return "eye.slash"
        case .forgotten:         return "moon.zzz"
        case .buried:            return "archivebox"
        case .seenOnce:          return "1.circle"
        case .mostViewed:        return "flame"
        case .oldFavorites:      return "heart.text.square"
        case .forgottenVideos:   return "video.slash"
        case .deepArchive:       return "clock.arrow.circlepath"
        case .sameDayOtherYears: return "calendar"
        case .oneFromEveryMonth: return "square.grid.3x1.below.line.grid.1x2"
        case .appFavorites:      return "star"
        case .pinned:            return "pin"
        }
    }

    /// The members of this collection, given the full set and the metadata lookup.
    func members(of assets: [HiddenAsset],
                 meta: [String: AssetMeta],
                 now: Date = .now) -> [HiddenAsset] {
        func metaOf(_ asset: HiddenAsset) -> AssetMeta { meta[asset.localIdentifier] ?? .empty }

        switch self {
        case .continueWatching:
            return assets.filter {
                $0.isVideo && metaOf($0).playbackPosition > 2 && !metaOf($0).playbackCompleted
            }
            .sorted { (metaOf($0).lastViewedAt ?? .distantPast) > (metaOf($1).lastViewedAt ?? .distantPast) }
        case .recentlyViewed:
            return assets.filter { metaOf($0).lastViewedAt != nil }
                .sorted { (metaOf($0).lastViewedAt ?? .distantPast) > (metaOf($1).lastViewedAt ?? .distantPast) }
        case .recentlyFinished:
            return assets.filter { $0.isVideo && metaOf($0).playbackCompleted }
                .sorted { (metaOf($0).lastViewedAt ?? .distantPast) > (metaOf($1).lastViewedAt ?? .distantPast) }
        case .unseen:
            return assets.filter { metaOf($0).viewCount == 0 }
        case .forgotten:
            return assets.filter {
                guard let last = metaOf($0).lastViewedAt else { return false }
                return now.timeIntervalSince(last) > 90 * 86_400
            }
        case .buried:
            return assets.filter {
                metaOf($0).viewCount == 0
                    && !$0.isFavorite
                    && !metaOf($0).isAppFavorite
                    && now.timeIntervalSince($0.creationDate) > 365 * 86_400
            }
        case .seenOnce:
            return assets.filter { metaOf($0).viewCount == 1 }
        case .mostViewed:
            return assets.filter { metaOf($0).viewCount > 0 }
                .sorted { metaOf($0).viewCount > metaOf($1).viewCount }
        case .oldFavorites:
            return assets.filter {
                ($0.isFavorite || metaOf($0).isAppFavorite)
                    && (metaOf($0).lastViewedAt.map { now.timeIntervalSince($0) > 30 * 86_400 } ?? true)
            }
        case .forgottenVideos:
            return assets.filter {
                $0.isVideo
                    && (metaOf($0).lastViewedAt.map { now.timeIntervalSince($0) > 60 * 86_400 } ?? true)
            }
        case .deepArchive:
            return assets.filter { now.timeIntervalSince($0.creationDate) > 3 * 365 * 86_400 }
                .sorted { $0.creationDate < $1.creationDate }
        case .sameDayOtherYears:
            let calendar = Calendar.current
            let today = calendar.dateComponents([.month, .day], from: now)
            return assets.filter {
                let components = calendar.dateComponents([.month, .day, .year], from: $0.creationDate)
                return components.month == today.month
                    && components.day == today.day
                    && !calendar.isDate($0.creationDate, equalTo: now, toGranularity: .year)
            }
        case .oneFromEveryMonth:
            let calendar = Calendar.current
            var byMonth: [String: HiddenAsset] = [:]
            for asset in assets {
                let components = calendar.dateComponents([.year, .month], from: asset.creationDate)
                let key = "\(components.year ?? 0)-\(components.month ?? 0)"
                if byMonth[key] == nil { byMonth[key] = asset }
            }
            return byMonth.values.sorted { $0.creationDate > $1.creationDate }
        case .appFavorites:
            return assets.filter { metaOf($0).isAppFavorite }
        case .pinned:
            return assets.filter { metaOf($0).isPinned }
        }
    }
}

/// Rediscovery: collections that keep a large hidden library alive instead of static.
struct DiscoverView: View {
    @Environment(\.app) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.model.assets.isEmpty {
                    HiddenEmptyStateView()
                } else {
                    list
                }
            }
            .navigationTitle(Text("Discover"))
        }
    }

    private var list: some View {
        List {
            ForEach(DiscoverCollection.allCases) { collection in
                let members = collection.members(of: app.model.assets, meta: app.model.metaByID)
                if !members.isEmpty {
                    NavigationLink {
                        CollectionResultsView(title: collection.title, assets: members)
                    } label: {
                        row(collection, count: members.count, cover: members.first)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ collection: DiscoverCollection, count: Int, cover: HiddenAsset?) -> some View {
        HStack(spacing: Space.l) {
            if let cover {
                AssetImageView(assetID: cover.localIdentifier, targetSide: 120)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: Radius.thumb))
                    .blurredIfNeeded()
                    .accessibilityHidden(true)
            } else {
                Image(systemName: collection.symbol)
                    .font(Typo.glyph(22, .medium))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 56, height: 56)
                    .background(Palette.surfaceSunk, in: .rect(cornerRadius: Radius.thumb))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title).font(Typo.control)
                Text(collection.subtitle)
                    .font(Typo.meta)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer()

            Text(count.formatted())
                .font(Typo.meta)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, Space.xs)
    }
}

/// A grid of one collection's members, opening into the viewer.
struct CollectionResultsView: View {
    let title: String
    let assets: [HiddenAsset]

    @State private var viewerTarget: ViewerTarget?

    var body: some View {
        ScrollView {
            MediaGridView(assets: assets, columns: 3, selection: nil) { index in
                viewerTarget = ViewerTarget(index: index)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewerTarget) { target in
            ViewerView(assets: assets, index: target.index) { viewerTarget = nil }
        }
    }
}
