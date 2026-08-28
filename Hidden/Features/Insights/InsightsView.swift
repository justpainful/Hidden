import Charts
import SwiftUI

/// Statistics over the accessible Hidden set and the app's own history. Informative, not
/// gamified: numbers and trends, no streaks, no pressure.
struct InsightsView: View {
    @Environment(\.app) private var app

    private var assets: [HiddenAsset] { app.model.assets }
    private var meta: [String: AssetMeta] { app.model.metaByID }

    var body: some View {
        NavigationStack {
            Group {
                if assets.isEmpty {
                    HiddenEmptyStateView()
                } else {
                    content
                }
            }
            .navigationTitle(Text("Insights"))
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                statGrid
                captureTrend
                mediaSplit
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.l)
        }
        .background(Palette.canvas)
    }

    // MARK: Stats

    private var videos: [HiddenAsset] { assets.filter(\.isVideo) }
    private var viewedCount: Int {
        assets.filter { (meta[$0.localIdentifier]?.viewCount ?? 0) > 0 }.count
    }
    private var reviewedCount: Int {
        assets.filter { meta[$0.localIdentifier]?.reviewState == .reviewed }.count
    }
    private var totalVideoSeconds: TimeInterval {
        videos.reduce(0) { $0 + $1.duration }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m),
                            GridItem(.flexible(), spacing: Space.m)],
                  spacing: Space.m) {
            stat(String(localized: "Total Hidden"), assets.count.formatted())
            stat(String(localized: "Videos"), videos.count.formatted())
            stat(String(localized: "Favorites"),
                 assets.filter(\.isFavorite).count.formatted())
            stat(String(localized: "App Favorites"),
                 assets.filter { meta[$0.localIdentifier]?.isAppFavorite == true }.count.formatted())
            stat(String(localized: "Unseen"),
                 (assets.count - viewedCount).formatted())
            stat(String(localized: "Reviewed"),
                 "\(reviewedCount.formatted()) / \(assets.count.formatted())")
            stat(String(localized: "Video Time"), totalVideoSeconds.shortDuration)
            stat(String(localized: "Oldest"),
                 assets.map(\.creationDate).min()?
                    .formatted(.dateTime.year()) ?? "—")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(value)
                .font(Typo.sectionTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(Typo.meta)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.tile))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: Charts

    private struct YearCount: Identifiable {
        var id: Int { year }
        let year: Int
        let count: Int
    }

    private var byYear: [YearCount] {
        let calendar = Calendar.current
        var counts: [Int: Int] = [:]
        for asset in assets {
            counts[calendar.component(.year, from: asset.creationDate), default: 0] += 1
        }
        return counts.map { YearCount(year: $0.key, count: $0.value) }
            .sorted { $0.year < $1.year }
    }

    private var captureTrend: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Captured by Year")
                .font(Typo.sectionTitle)

            Chart(byYear) { entry in
                BarMark(
                    x: .value("Year", String(entry.year)),
                    y: .value("Items", entry.count)
                )
                .foregroundStyle(Palette.accent)
                .cornerRadius(3)
            }
            .frame(height: 180)
            .accessibilityLabel(String(localized: "Bar chart of items captured per year"))
        }
        .padding(Space.l)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
    }

    private var mediaSplit: some View {
        let photoCount = assets.count - videos.count
        return VStack(alignment: .leading, spacing: Space.m) {
            Text("Media Types")
                .font(Typo.sectionTitle)

            Chart {
                SectorMark(angle: .value(String(localized: "Photos"), photoCount),
                           innerRadius: .ratio(0.6), angularInset: 2)
                    .foregroundStyle(Palette.accent)
                SectorMark(angle: .value(String(localized: "Videos"), videos.count),
                           innerRadius: .ratio(0.6), angularInset: 2)
                    .foregroundStyle(Palette.accent.opacity(0.45))
            }
            .frame(height: 160)
            .accessibilityLabel(String(localized: "\(photoCount.formatted()) photos and \(videos.count.formatted()) videos"))

            HStack(spacing: Space.l) {
                legendDot(Palette.accent, String(localized: "Photos"), photoCount)
                legendDot(Palette.accent.opacity(0.45), String(localized: "Videos"), videos.count)
            }
        }
        .padding(Space.l)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
    }

    private func legendDot(_ color: Color, _ label: String, _ count: Int) -> some View {
        HStack(spacing: Space.s) {
            Circle().fill(color).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text("\(label) · \(count.formatted())")
                .font(Typo.meta)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
