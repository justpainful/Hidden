import SwiftUI

/// The edge-to-edge media grid every surface shares: Library, Discover collections, search
/// results, batch views. Content only — sorting, filtering and selection state belong to
/// the screen that owns them.
struct MediaGridView: View {
    let assets: [HiddenAsset]
    var columns: Int = 3
    /// Non-nil while the parent is in selection mode.
    var selection: Binding<Set<String>>?
    var onOpen: (Int) -> Void

    @Environment(\.app) private var app
    @Environment(\.displayScale) private var displayScale
    /// The centre of the last warmed window, so scrolling only re-warms every `warmStep`
    /// tiles instead of on every appearance.
    @State private var warmedCentre = Int.min

    private let warmStep = 12
    private let warmAhead = 48

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: max(columns, 1))
    }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: 2) {
            ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                tile(asset, index: index)
                    .onAppear { warmAround(index) }
            }
        }
        .onDisappear {
            warmedCentre = .min
        }
    }

    /// Tell the media provider which frames are about to come over the edge, at the same
    /// bucketed size the tiles will actually request — a warm at any other size is wasted.
    private func warmAround(_ index: Int) {
        guard abs(index - warmedCentre) >= warmStep else { return }
        warmedCentre = index
        let side = PhotoMediaProvider.requestSide(forSide: 300, scale: displayScale)
        let lower = max(0, index - warmStep)
        let upper = min(assets.count, index + warmAhead)
        guard lower < upper else { return }
        app.media.startCaching(assets[lower..<upper].map(\.localIdentifier), side: side)
    }

    @ViewBuilder
    private func tile(_ asset: HiddenAsset, index: Int) -> some View {
        let id = asset.localIdentifier
        let isSelected = selection?.wrappedValue.contains(id) ?? false

        Button {
            if let selection {
                if isSelected {
                    selection.wrappedValue.remove(id)
                } else {
                    selection.wrappedValue.insert(id)
                }
            } else {
                onOpen(index)
            }
        } label: {
            AssetTile(asset: asset, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("asset.tile")
        .accessibilityLabel(accessibilityLabel(for: asset))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func accessibilityLabel(for asset: HiddenAsset) -> String {
        var parts: [String] = []
        parts.append(asset.isVideo
            ? String(localized: "Video, \(asset.duration.spokenDuration)")
            : String(localized: "Photo"))
        parts.append(asset.creationDate.formatted(date: .abbreviated, time: .omitted))
        if asset.isFavorite { parts.append(String(localized: "Favorite")) }
        return parts.joined(separator: ", ")
    }
}
