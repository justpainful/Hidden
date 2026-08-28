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
    @State private var showsTags = false
    @State private var showsNote = false
    @State private var showsRating = false
    @State private var confirmUnhide = false
    @State private var confirmDelete = false
    @State private var actionError: String?
    @State private var presentedAsset: HiddenAsset?
    @State private var shareImage: UIImage?
    @State private var isPreparingShare = false

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
        .sheet(isPresented: $showsTags) {
            if let current {
                TagEditorView(assetID: current.localIdentifier)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showsNote) {
            if let current {
                NoteEditorView(assetID: current.localIdentifier)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showsRating) {
            if let current {
                VStack(spacing: Space.l) {
                    Text("Rating")
                        .font(Typo.sectionTitle)
                    RatingPicker(assetID: current.localIdentifier)
                }
                .padding(Space.gutter)
                .presentationDetents([.height(160)])
            }
        }
        .confirmationDialog(String(localized: "Make this item visible again in your Photos library?"),
                            isPresented: $confirmUnhide, titleVisibility: .visible) {
            Button(String(localized: "Unhide")) {
                guard let current else { return }
                Task {
                    do { try await app.model.unhide(current.localIdentifier) }
                    catch { actionError = error.localizedDescription }
                }
            }
        }
        .confirmationDialog(String(localized: "Delete this item from your Photos library? This affects Apple Photos and iCloud Photos, and moves it to Recently Deleted."),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "Delete"), role: .destructive) {
                guard let current else { return }
                Task {
                    do { try await app.model.delete([current.localIdentifier]) }
                    catch { actionError = error.localizedDescription }
                }
            }
        }
        .fullScreenCover(item: $presentedAsset) { asset in
            PresentationView(asset: asset) { presentedAsset = nil }
        }
        .sheet(isPresented: Binding(get: { shareImage != nil },
                                    set: { if !$0 { shareImage = nil } })) {
            if let shareImage {
                ActivityView(items: [shareImage])
                    .presentationDetents([.medium, .large])
            }
        }
        .alert(String(localized: "That didn't work"),
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
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

                        moreMenu(for: current)
                    }
                }
                .padding(.bottom, Space.gutter)
            }
        }
    }

    private func moreMenu(for current: HiddenAsset) -> some View {
        Menu {
            Button {
                showsRating = true
            } label: {
                Label(String(localized: "Rate"), systemImage: "star.leadinghalf.filled")
            }
            Button {
                showsTags = true
            } label: {
                Label(String(localized: "Tags"), systemImage: "tag")
            }
            Button {
                showsNote = true
            } label: {
                Label(String(localized: "Note"), systemImage: "note.text")
            }
            Button {
                presentedAsset = current
            } label: {
                Label(String(localized: "Present This Item"), systemImage: "person.2.crop.square.stack")
            }
            if !current.isVideo {
                Button {
                    guard !isPreparingShare else { return }
                    isPreparingShare = true
                    Task {
                        shareImage = await app.media.image(
                            for: current.localIdentifier,
                            side: CGFloat(max(current.pixelWidth, current.pixelHeight)),
                            purpose: .display)
                        isPreparingShare = false
                    }
                } label: {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                }
            }

            if !app.settings.readOnlyMode {
                Divider()
                Button {
                    confirmUnhide = true
                } label: {
                    Label(String(localized: "Unhide"), systemImage: "eye")
                }
                if !app.settings.noDeleteMode {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Typo.glyph(17))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .frame(width: 46, height: 46)
                .contentShape(.circle)
        }
        .glassControl(.circle, tone: .clear)
        .accessibilityLabel(String(localized: "More"))
    }

    private var positionText: String {
        "\((index + 1).formatted()) / \(assets.count.formatted())"
    }
}

/// One page of the viewer: a zoomable photo, or the app's own video player.
private struct ViewerPage: View {
    let asset: HiddenAsset
    let isCurrent: Bool

    var body: some View {
        if asset.isVideo {
            HiddenVideoPlayer(asset: asset, isCurrent: isCurrent)
        } else if asset.isLivePhoto {
            LivePhotoPage(asset: asset, isCurrent: isCurrent)
        } else {
            ZoomableAssetView(assetID: asset.localIdentifier)
        }
    }
}

/// The system share sheet. Sharing hands the pixels to whatever the user picks — a
/// deliberate act, from the deliberate viewer, never from a grid.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Pinch and double-tap zoom for one photo.
struct ZoomableAssetView: View {
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

    @Environment(\.app) private var app

    private var related: [HiddenAsset] {
        RelatedFinder.related(to: asset, in: app.model.assets,
                              meta: app.model.metaByID, limit: 20)
    }

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
                if !related.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.s) {
                                ForEach(related) { relatedAsset in
                                    AssetImageView(assetID: relatedAsset.localIdentifier,
                                                   targetSide: 120)
                                        .frame(width: 72, height: 72)
                                        .clipShape(.rect(cornerRadius: Radius.thumb))
                                        .blurredIfNeeded()
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        NavigationLink(String(localized: "See All Related")) {
                            CollectionResultsView(title: String(localized: "Related"),
                                                  assets: related)
                        }
                    } header: {
                        Text("Related")
                    } footer: {
                        Text("Captured around the same time, the same day, the same session, or sharing a tag.")
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
