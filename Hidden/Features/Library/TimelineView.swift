import SwiftUI

/// Which date the timeline is organized by. The label travels with the choice everywhere —
/// a capture timeline and an observation timeline are different histories.
enum TimelineDateMode: String, CaseIterable, Identifiable {
    case captured
    case observed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captured: return String(localized: "Captured")
        case .observed: return String(localized: "First Observed")
        }
    }
}

/// Years and months over the accessible set, each month opening into the shared grid.
struct TimelineView: View {
    @Environment(\.app) private var app
    @State private var mode: TimelineDateMode = .captured

    private var calendar: Calendar { Calendar.current }

    private struct MonthGroup: Identifiable {
        var id: String { "\(year)-\(month)" }
        let year: Int
        let month: Int
        let assets: [HiddenAsset]
    }

    private struct YearGroup: Identifiable {
        var id: Int { year }
        let year: Int
        let months: [MonthGroup]
        var count: Int { months.reduce(0) { $0 + $1.assets.count } }
    }

    private func date(of asset: HiddenAsset) -> Date? {
        switch mode {
        case .captured: return asset.creationDate
        case .observed: return app.model.meta(for: asset.localIdentifier).firstObservedHiddenAt
        }
    }

    private var years: [YearGroup] {
        var byMonth: [Int: [Int: [HiddenAsset]]] = [:]
        for asset in app.model.assets {
            guard let date = date(of: asset) else { continue }
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            byMonth[year, default: [:]][month, default: []].append(asset)
        }
        return byMonth.map { year, months in
            YearGroup(year: year,
                      months: months.map { MonthGroup(year: year, month: $0.key, assets: $0.value) }
                          .sorted { $0.month > $1.month })
        }
        .sorted { $0.year > $1.year }
    }

    var body: some View {
        List {
            ForEach(years) { year in
                Section {
                    ForEach(year.months) { group in
                        NavigationLink {
                            CollectionResultsView(title: monthTitle(group),
                                                  assets: group.assets)
                        } label: {
                            HStack(spacing: Space.l) {
                                if let cover = group.assets.first {
                                    AssetImageView(assetID: cover.localIdentifier, targetSide: 100)
                                        .frame(width: 44, height: 44)
                                        .clipShape(.rect(cornerRadius: Radius.thumb))
                                        .blurredIfNeeded()
                                        .accessibilityHidden(true)
                                }
                                Text(monthTitle(group))
                                    .font(Typo.control)
                                Spacer()
                                Text(group.assets.count.formatted())
                                    .font(Typo.meta)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                } header: {
                    Text(String(year.year))
                        .font(Typo.sectionTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Timeline"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker(String(localized: "Timeline Date"), selection: $mode) {
                    ForEach(TimelineDateMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .overlay {
            if years.isEmpty {
                ContentUnavailableView(
                    String(localized: "Nothing to Show"),
                    systemImage: "calendar",
                    description: Text(mode == .observed
                        ? String(localized: "Observation dates appear after the app has seen your library at least once.")
                        : String(localized: "No media available.")))
            }
        }
    }

    private func monthTitle(_ group: MonthGroup) -> String {
        let components = DateComponents(year: group.year, month: group.month)
        let date = calendar.date(from: components) ?? .now
        return date.formatted(.dateTime.month(.wide).year())
    }
}
