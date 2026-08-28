import SwiftUI

/// Which timestamp the heatmap visualizes. Stated on screen, always — a capture heatmap and
/// an observation heatmap answer different questions and must never be mistaken for each
/// other.
enum HeatmapMode: String, CaseIterable, Identifiable {
    case captured
    case observed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captured: return String(localized: "Capture Activity")
        case .observed: return String(localized: "First Observed Activity")
        }
    }

    var caption: String {
        switch self {
        case .captured:
            return String(localized: "When the media was captured")
        case .observed:
            return String(localized: "When this app first observed it hidden")
        }
    }
}

/// A GitHub-style calendar heat map over roughly the last six months.
struct HeatmapView: View {
    let assets: [HiddenAsset]
    let meta: [String: AssetMeta]

    @State private var mode: HeatmapMode = .captured

    private let weeks = 26
    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Picker(String(localized: "Heatmap Mode"), selection: $mode) {
                ForEach(HeatmapMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(mode.caption)
                .font(Typo.meta)
                .foregroundStyle(Palette.textSecondary)

            grid

            legend
        }
        .padding(Space.l)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
    }

    // MARK: Data

    private var dates: [Date] {
        switch mode {
        case .captured:
            return assets.map(\.creationDate)
        case .observed:
            return assets.compactMap { meta[$0.localIdentifier]?.firstObservedHiddenAt }
        }
    }

    /// Count per start-of-day.
    private var countsByDay: [Date: Int] {
        var counts: [Date: Int] = [:]
        for date in dates {
            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
        return counts
    }

    // MARK: Drawing

    private var grid: some View {
        let counts = countsByDay
        let maximum = max(counts.values.max() ?? 1, 1)
        let today = calendar.startOfDay(for: .now)
        // Align the last column to the current week.
        let weekday = calendar.component(.weekday, from: today) - calendar.firstWeekday
        let daysIntoWeek = (weekday + 7) % 7

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { day in
                            // Row 0 is the first weekday of the week; the rightmost column
                            // ends on today, so later rows in it are the future.
                            let offset = (weeks - 1 - week) * 7 + (daysIntoWeek - day)
                            let date = calendar.date(byAdding: .day,
                                                     value: -offset,
                                                     to: today) ?? today
                            let count = date > today ? 0 : (counts[calendar.startOfDay(for: date)] ?? 0)
                            cell(count: count, maximum: maximum, future: date > today)
                        }
                    }
                }
            }
        }
        // The grid is decoration at this density; the accessible summary carries the meaning.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleSummary)
    }

    private func cell(count: Int, maximum: Int, future: Bool) -> some View {
        let intensity = count == 0 ? 0 : 0.25 + 0.75 * Double(count) / Double(maximum)
        return RoundedRectangle(cornerRadius: 2)
            .fill(future ? Color.clear
                  : (count == 0 ? Palette.surfaceSunk : Palette.accent.opacity(intensity)))
            .frame(width: 12, height: 12)
    }

    private var legend: some View {
        HStack(spacing: Space.xs) {
            Text("Less")
                .font(Typo.meta)
                .foregroundStyle(Palette.textTertiary)
            ForEach([0.0, 0.35, 0.6, 1.0], id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step == 0 ? Palette.surfaceSunk : Palette.accent.opacity(step))
                    .frame(width: 12, height: 12)
            }
            Text("More")
                .font(Typo.meta)
                .foregroundStyle(Palette.textTertiary)
        }
        .accessibilityHidden(true)
    }

    private var accessibleSummary: String {
        let total = dates.filter {
            $0 > calendar.date(byAdding: .day, value: -weeks * 7, to: .now)!
        }.count
        return String(localized: "\(mode.title): \(total.formatted()) items in the last \(weeks.formatted()) weeks")
    }
}
