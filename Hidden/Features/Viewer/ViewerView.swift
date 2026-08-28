import AVKit
import SwiftUI

/// The full-screen viewer: swipe between assets, zoom photos, play videos, act on what is
/// on screen. Presented as a full-screen cover over whichever surface opened it.
struct ViewerView: View {
    let assets: [HiddenAsset]
    @State var index: Int
    var onDismiss: () -> Void

    @Environment(\.app) private var app
    @State private var showsChrome = true
    @State private var showsInfo = false

    private var current: HiddenAsset? {
        assets.indices.contains(index) ? assets[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { itemIndex, asset in
                    ViewerPage(asset: asset, isCurrent: itemIndex == index)
                        .tag(itemIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if showsChrome {
                chrome
            }
        }
        .statusBarHidden(!showsChrome)
        .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { showsChrome.toggle() } }
        .task(id: index) {
            if let current { app.model.recordView(of: current.localIdentifier) }
        }
        .sheet(isPresented: $showsInfo) {
            if let current {
                AssetInfoView(asset: current, meta: app.model.meta(for: current.localIdentifier))
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack {
            HStack {
                GlassIconButton(systemImage: "xmark",
                                label: String(localized: "Close"),
                                tone: .clear) { onDismiss() }
                Spacer()
                Text(positionText)
                    .font(Typo.meta)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .accessibilityLabel(String(localized: "Item \(index + 1) of \(assets.count)"))
                Spacer()
                GlassIconButton(systemImage: "info.circle",
                                label: String(localized: "Info"),
                                tone: .clear) { showsInfo = true }
            }
            .padding(.horizontal, Space.l)

            Spacer()

            if let current {
                GlassEffectContainer {
                    HStack(spacing: Space.m) {
                        GlassIconButton(
                            systemImage: current.isFavorite ? "heart.fill" : "heart",
                            label: current.isFavorite
                                ? String(localized: "Remove Favorite")
                                : String(localized: "Favorite"),
                            tone: .clear
                        ) {
                            guard !app.settings.readOnlyMode else { return }
                            Task { await app.model.toggleSystemFavorite(current.localIdentifier) }
                        }

                        GlassIconButton(
                            systemImage: app.model.meta(for: current.localIdentifier).isAppFavorite
                                ? "star.fill" : "star",
                            label: String(localized: "App Favorite"),
                            tone: .clear
                        ) {
                            app.model.toggleAppFavorite(current.localIdentifier)
                        }

                        GlassIconButton(
                            systemImage: app.model.meta(for: current.localIdentifier).isPinned
                                ? "pin.fill" : "pin",
                            label: String(localized: "Pin"),
                            tone: .clear
                        ) {
                            app.model.togglePinned(current.localIdentifier)
                        }

                        GlassIconButton(
                            systemImage: "bookmark",
                            label: String(localized: "Review Later"),
                            tone: .clear
                        ) {
                            app.model.setReviewState(current.localIdentifier, .reviewLater)
                        }
                    }
                }
                .padding(.bottom, Space.gutter)
            }
        }
    }

    private var positionText: String {
        "\((index + 1).formatted()) / \(assets.count.formatted())"
    }
}

/// One page of the viewer: a zoomable photo, or a video player once the item resolves.
private struct ViewerPage: View {
    let asset: HiddenAsset
    let isCurrent: Bool

    @Environment(\.app) private var app
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if asset.isVideo {
                videoContent
            } else {
                ZoomableAssetView(assetID: asset.localIdentifier)
            }
        }
        .task(id: isCurrent) {
            guard asset.isVideo else { return }
            if isCurrent, player == nil {
                if let real = app.media as? PhotoMediaProvider,
                   let item = await real.playerItem(for: asset.localIdentifier) {
                    let player = AVPlayer(playerItem: item)
                    player.isMuted = app.settings.muteByDefault
                    self.player = player
                }
            } else if !isCurrent {
                player?.pause()
            }
        }
    }

    @ViewBuilder
    private var videoContent: some View {
        if let player {
            VideoPlayer(player: player)
                .ignoresSafeArea()
        } else {
            // The poster frame while the item resolves — or forever, in the mock, which has
            // no real clips to play.
            ZStack {
                AssetImageView(assetID: asset.localIdentifier,
                               targetSide: 1200,
                               purpose: .display,
                               contentMode: .fit)
                Image(systemName: "play.circle.fill")
                    .font(Typo.glyph(56, .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 6)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Pinch and double-tap zoom for one photo.
private struct ZoomableAssetView: View {
    let assetID: String

    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            AssetImageView(assetID: assetID,
                           targetSide: max(proxy.size.width, proxy.size.height),
                           purpose: .display,
                           contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(magnification.simultaneously(with: scale > 1.01 ? drag : nil))
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.3)) {
                        if scale > 1.01 {
                            scale = 1; steadyScale = 1
                            offset = .zero; steadyOffset = .zero
                        } else {
                            scale = 2.5; steadyScale = 2.5
                        }
                    }
                }
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(steadyScale * value, 1), 6)
            }
            .onEnded { _ in
                steadyScale = scale
                if scale <= 1.01 {
                    withAnimation(.spring(duration: 0.25)) {
                        offset = .zero; steadyOffset = .zero
                    }
                }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: steadyOffset.width + value.translation.width,
                                height: steadyOffset.height + value.translation.height)
            }
            .onEnded { _ in steadyOffset = offset }
    }
}

/// Public metadata for one asset, plus the app's own observation dates — each labelled as
/// exactly what it is. `addedDate` is never called "hidden date"; observation dates are
/// never passed off as system history.
struct AssetInfoView: View {
    let asset: HiddenAsset
    let meta: AssetMeta

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Media")) {
                    row(String(localized: "Type"), typeText)
                    row(String(localized: "Dimensions"), "\(asset.pixelWidth) × \(asset.pixelHeight)")
                    if asset.isVideo {
                        row(String(localized: "Duration"), asset.duration.shortDuration)
                    }
                }
                Section(String(localized: "Dates")) {
                    row(String(localized: "Captured"),
                        asset.creationDate.formatted(date: .abbreviated, time: .shortened))
                    if let modified = asset.modificationDate {
                        row(String(localized: "Modified"),
                            modified.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let observed = meta.firstObservedHiddenAt {
                        row(String(localized: "First Observed by Hidden"),
                            observed.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let favorite = meta.firstObservedFavoriteAt {
                        row(String(localized: "First Observed Favorite"),
                            favorite.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if meta.viewCount > 0 {
                    Section(String(localized: "In This App")) {
                        row(String(localized: "Views"), meta.viewCount.formatted())
                        if let last = meta.lastViewedAt {
                            row(String(localized: "Last Viewed"),
                                last.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
                if asset.hasLocation {
                    Section(String(localized: "Location")) {
                        row(String(localized: "Has Location"), String(localized: "Yes"))
                    }
                }
            }
            .navigationTitle(String(localized: "Info"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var typeText: String {
        if asset.isVideo { return String(localized: "Video") }
        if asset.isLivePhoto { return String(localized: "Live Photo") }
        if asset.isScreenshot { return String(localized: "Screenshot") }
        return String(localized: "Photo")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Palette.textSecondary)
        }
        .font(Typo.label)
    }
}
