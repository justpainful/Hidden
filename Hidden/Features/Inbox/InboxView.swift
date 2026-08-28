import SwiftUI

/// What is new or changed in the Hidden workflow since the app last looked.
///
/// Everything here is phrased as observation — "newly observed", "no longer here" — because
/// that is what the app actually knows. PhotoKit exposes no historical hidden date, and the
/// inbox never pretends it does.
struct InboxView: View {
    @Environment(\.app) private var app

    @State private var showsSettings = false
    @State private var reviewQueue: [HiddenAsset]?
    @State private var viewerTarget: ViewerTarget?
    @State private var viewerAssets: [HiddenAsset] = []

    private var digest: InboxDigest { app.model.digest }

    private var unreviewed: [HiddenAsset] {
        app.model.assets.filter {
            app.model.meta(for: $0.localIdentifier).reviewState == .unreviewed
        }
    }

    private var reviewLater: [HiddenAsset] {
        app.model.assets.filter {
            app.model.meta(for: $0.localIdentifier).reviewState == .reviewLater
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if app.model.assets.isEmpty {
                        HiddenEmptyStateView()
                    } else {
                        summaryHeader

                        if !newlyObservedAssets.isEmpty {
                            section(title: String(localized: "Newly Observed"),
                                    assets: newlyObservedAssets)
                        }
                        if !newlyFavoritedAssets.isEmpty {
                            section(title: String(localized: "Newly Favorited"),
                                    assets: newlyFavoritedAssets)
                        }
                        if !digest.noLongerPresent.isEmpty {
                            noLongerPresentCard
                        }
                        if !unreviewed.isEmpty {
                            reviewCard
                        }
                        if !reviewLater.isEmpty {
                            section(title: String(localized: "Review Later"),
                                    assets: reviewLater)
                        }
                        if digest.isEmpty && unreviewed.isEmpty && reviewLater.isEmpty {
                            caughtUp
                        }
                    }
                }
                .padding(.vertical, Space.l)
            }
            .background(Palette.canvas)
            .navigationTitle(Text("Inbox"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label(String(localized: "Settings"), systemImage: "gearshape")
                    }
                }
            }
            .refreshable { await app.model.refresh() }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .fullScreenCover(item: reviewQueueTarget) { target in
                ReviewView(queue: target.assets) { reviewQueue = nil }
            }
            .fullScreenCover(item: $viewerTarget) { target in
                ViewerView(assets: viewerAssets, index: target.index) { viewerTarget = nil }
            }
        }
    }

    // MARK: Data

    private var newlyObservedAssets: [HiddenAsset] {
        digest.newlyObserved.compactMap { app.model.asset(for: $0) }
    }

    private var newlyFavoritedAssets: [HiddenAsset] {
        digest.newlyFavorited.compactMap { app.model.asset(for: $0) }
    }

    /// A bridge so `fullScreenCover(item:)` gets identity for the review queue.
    private var reviewQueueTarget: Binding<ReviewQueueTarget?> {
        Binding(
            get: { reviewQueue.map { ReviewQueueTarget(assets: $0) } },
            set: { reviewQueue = $0?.assets })
    }

    // MARK: Sections

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if digest.isBaseline {
                Text("First look at your Hidden library")
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)
            } else if let refreshed = app.model.lastRefreshAt {
                Text("Updated \(refreshed.formatted(date: .omitted, time: .shortened))")
                    .font(Typo.meta)
                    .foregroundStyle(Palette.textTertiary)
            }

            HStack(spacing: Space.m) {
                countChip(digest.newlyObserved.count, String(localized: "New"))
                countChip(unreviewed.count, String(localized: "Unreviewed"))
                countChip(digest.newlyFavorited.count, String(localized: "Favorited"))
            }
        }
        .padding(.horizontal, Space.gutter)
    }

    private func countChip(_ count: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(count.formatted())
                .font(Typo.sectionTitle)
                .foregroundStyle(count > 0 ? Palette.textPrimary : Palette.textTertiary)
            Text(label)
                .font(Typo.meta)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.tile))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count.formatted()) \(label)")
    }

    private func section(title: String, assets: [HiddenAsset]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(title).font(Typo.sectionTitle)
                Spacer()
                Text(assets.count.formatted())
                    .font(Typo.meta)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, Space.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(Array(assets.prefix(30).enumerated()), id: \.element.id) { index, asset in
                        Button {
                            viewerAssets = assets
                            viewerTarget = ViewerTarget(index: index)
                        } label: {
                            AssetImageView(assetID: asset.localIdentifier, targetSide: 150)
                                .frame(width: 110, height: 110)
                                .clipShape(.rect(cornerRadius: Radius.thumb))
                                .overlay(alignment: .bottomLeading) {
                                    MediaBadge(asset: asset).padding(Space.xs)
                                }
                                .blurredIfNeeded()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.gutter)
            }
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Review")
                .font(Typo.sectionTitle)

            Text("\(unreviewed.count.formatted()) items waiting for a decision.")
                .font(Typo.label)
                .foregroundStyle(Palette.textSecondary)

            HStack(spacing: Space.m) {
                Button {
                    reviewQueue = unreviewed
                } label: {
                    Label(String(localized: "Review All"), systemImage: "checkmark.rectangle.stack")
                        .font(Typo.control)
                        .frame(minHeight: Hit.min)
                        .padding(.horizontal, Space.l)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    reviewQueue = Array(unreviewed.prefix(25))
                } label: {
                    Text("First 25")
                        .font(Typo.control)
                        .frame(minHeight: Hit.min)
                        .padding(.horizontal, Space.l)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
        .padding(.horizontal, Space.gutter)
    }

    private var noLongerPresentCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("No Longer Here")
                .font(Typo.sectionTitle)
            Text("\(digest.noLongerPresent.count.formatted()) items from the last check are no longer in the accessible Hidden set. They may have been unhidden, deleted, or protected by the system — the app cannot tell which.")
                .font(Typo.label)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
        .padding(.horizontal, Space.gutter)
    }

    private var caughtUp: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "checkmark.circle")
                .font(Typo.glyph(40, .regular))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text("You're caught up.")
                .font(Typo.sectionTitle)
            Text("Nothing new since the last check.")
                .font(Typo.label)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.section)
    }
}

private struct ReviewQueueTarget: Identifiable {
    let id = UUID()
    var assets: [HiddenAsset]
}
