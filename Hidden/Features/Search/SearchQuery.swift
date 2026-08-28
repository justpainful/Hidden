import Foundation

/// Local search over the accessible set: years, month names, media-type words, tags,
/// favourite/pinned keywords, and free text against tag names. Pure, so it is testable and
/// cheap enough to run per keystroke over thousands of assets.
enum SearchQuery {
    /// Split a query into terms; every term must match something (AND).
    static func run(_ query: String,
                    in assets: [HiddenAsset],
                    meta: [String: AssetMeta],
                    calendar: Calendar = .current) -> [HiddenAsset] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
        guard !terms.isEmpty else { return assets }

        return assets.filter { asset in
            let assetMeta = meta[asset.localIdentifier] ?? .empty
            return terms.allSatisfy { term in
                matches(term: term, asset: asset, meta: assetMeta, calendar: calendar)
            }
        }
    }

    private static func matches(term: String,
                                asset: HiddenAsset,
                                meta: AssetMeta,
                                calendar: Calendar) -> Bool {
        // A four-digit year.
        if term.count == 4, let year = Int(term) {
            if calendar.component(.year, from: asset.creationDate) == year { return true }
        }

        // A month name, in the current locale or English.
        if let month = monthNumber(for: term, calendar: calendar) {
            if calendar.component(.month, from: asset.creationDate) == month { return true }
        }

        // Media-type and state keywords.
        switch term {
        case "video", "videos", String(localized: "video").lowercased():
            if asset.isVideo { return true }
        case "photo", "photos", String(localized: "photo").lowercased():
            if !asset.isVideo { return true }
        case "live":
            if asset.isLivePhoto { return true }
        case "screenshot", "screenshots":
            if asset.isScreenshot { return true }
        case "favorite", "favorites", "favourite":
            if asset.isFavorite || meta.isAppFavorite { return true }
        case "pinned":
            if meta.isPinned { return true }
        case "unseen":
            if meta.viewCount == 0 { return true }
        default:
            break
        }

        // Tag names, by prefix or substring.
        if meta.tagNames.contains(where: { $0.lowercased().contains(term) }) { return true }

        return false
    }

    private static func monthNumber(for term: String, calendar: Calendar) -> Int? {
        let symbolSets = [
            calendar.monthSymbols,
            calendar.shortMonthSymbols,
            Calendar(identifier: .gregorian).monthSymbols,        // English fallback
            Calendar(identifier: .gregorian).shortMonthSymbols,
        ]
        for symbols in symbolSets {
            if let index = symbols.firstIndex(where: { $0.lowercased() == term }) {
                return index + 1
            }
        }
        return nil
    }
}
