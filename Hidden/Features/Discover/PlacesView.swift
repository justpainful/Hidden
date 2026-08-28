import SwiftUI

/// Location areas, from the coordinates PhotoKit already carries. No maps SDK, no remote
/// analytics — clusters, a cached place name each, and the shared grid behind every row.
struct PlacesView: View {
    let assets: [HiddenAsset]

    private var clusters: [PlaceCluster] {
        LocationClustering.clusters(in: assets)
    }

    private var withoutLocation: [HiddenAsset] {
        assets.filter { !$0.hasLocation }
    }

    var body: some View {
        List {
            ForEach(clusters) { cluster in
                NavigationLink {
                    CollectionResultsView(title: PlaceLabelCache.shared.cachedLabel(for: cluster)
                                            ?? PlaceLabelCache.shared.fallbackLabel(for: cluster),
                                          assets: cluster.assets)
                } label: {
                    PlaceRow(cluster: cluster)
                }
            }

            if !withoutLocation.isEmpty {
                NavigationLink {
                    CollectionResultsView(title: String(localized: "Without Location"),
                                          assets: withoutLocation)
                } label: {
                    HStack {
                        Image(systemName: "location.slash")
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 56, height: 56)
                            .accessibilityHidden(true)
                        Text("Without Location")
                            .font(Typo.control)
                        Spacer()
                        Text(withoutLocation.count.formatted())
                            .font(Typo.meta)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Places"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if clusters.isEmpty && withoutLocation.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Location Data"),
                    systemImage: "location",
                    description: Text("Media with location information would be grouped into areas here."))
            }
        }
    }
}

private struct PlaceRow: View {
    let cluster: PlaceCluster

    @State private var label: String?

    var body: some View {
        HStack(spacing: Space.l) {
            if let cover = cluster.assets.first {
                AssetImageView(assetID: cover.localIdentifier, targetSide: 120)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: Radius.thumb))
                    .blurredIfNeeded()
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label ?? PlaceLabelCache.shared.fallbackLabel(for: cluster))
                    .font(Typo.control)
                Text(String(localized: "\(cluster.count.formatted()) items"))
                    .font(Typo.meta)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, Space.xs)
        .task {
            label = await PlaceLabelCache.shared.resolveLabel(for: cluster)
        }
    }
}
