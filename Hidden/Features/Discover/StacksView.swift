import SwiftUI

/// Bursts of stills captured together, shown one cover each. Nothing is modified or
/// deleted here — a stack is a way of looking, not a change.
struct StacksListView: View {
    let assets: [HiddenAsset]

    private var stacks: [AssetStack] {
        StackGrouping.stacks(in: assets)
    }

    var body: some View {
        List {
            ForEach(stacks) { stack in
                NavigationLink {
                    StackDetailView(stack: stack)
                } label: {
                    row(stack)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Stacks"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if stacks.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Stacks"),
                    systemImage: "square.stack",
                    description: Text("Stacks appear when several photos were captured within seconds of each other."))
            }
        }
    }

    private func row(_ stack: AssetStack) -> some View {
        HStack(spacing: Space.l) {
            if let cover = stack.cover {
                AssetImageView(assetID: cover.localIdentifier, targetSide: 120)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: Radius.thumb))
                    .blurredIfNeeded()
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stack.cover?.creationDate.formatted(date: .abbreviated, time: .shortened) ?? "")
                    .font(Typo.control)
                Text(String(localized: "\(stack.count.formatted()) photos in a burst"))
                    .font(Typo.meta)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Text(stack.count.formatted())
                .font(Typo.meta)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, Space.xs)
    }
}

/// One stack: the grid, plus compare for picking the best of the burst.
struct StackDetailView: View {
    let stack: AssetStack

    @State private var viewerTarget: ViewerTarget?
    @State private var showsCompare = false

    var body: some View {
        ScrollView {
            MediaGridView(assets: stack.assets, columns: 3, selection: nil) { index in
                viewerTarget = ViewerTarget(index: index)
            }
        }
        .navigationTitle(Text("Stack"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsCompare = true
                } label: {
                    Label(String(localized: "Compare"), systemImage: "rectangle.split.2x1")
                }
                .disabled(stack.assets.count < 2)
            }
        }
        .fullScreenCover(item: $viewerTarget) { target in
            ViewerView(assets: stack.assets, index: target.index) { viewerTarget = nil }
        }
        .fullScreenCover(isPresented: $showsCompare) {
            CompareView(assets: stack.assets) { showsCompare = false }
        }
    }
}

/// Two candidates side by side, each swappable from a filmstrip, each markable. For burst
/// picking: which of these is the keeper?
struct CompareView: View {
    let assets: [HiddenAsset]
    var onDismiss: () -> Void

    @Environment(\.app) private var app
    @State private var leftIndex = 0
    @State private var rightIndex = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: Space.s) {
                HStack {
                    GlassIconButton(systemImage: "xmark",
                                    label: String(localized: "Close"),
                                    tone: .clear) { onDismiss() }
                    Spacer()
                    Text("Compare")
                        .font(Typo.control)
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 46, height: 46)
                }
                .padding(.horizontal, Space.l)

                HStack(spacing: 2) {
                    pane(index: $leftIndex)
                    pane(index: $rightIndex)
                }

                filmstrip
            }
        }
        .statusBarHidden(true)
    }

    private func pane(index: Binding<Int>) -> some View {
        let asset = assets[min(index.wrappedValue, assets.count - 1)]
        return VStack(spacing: Space.s) {
            AssetImageView(assetID: asset.localIdentifier,
                           targetSide: 800,
                           purpose: .display,
                           contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: Space.m) {
                GlassIconButton(
                    systemImage: app.model.meta(for: asset.localIdentifier).isAppFavorite
                        ? "star.fill" : "star",
                    label: String(localized: "App Favorite"),
                    tone: .clear
                ) {
                    app.model.toggleAppFavorite(asset.localIdentifier)
                }
                GlassIconButton(
                    systemImage: app.model.meta(for: asset.localIdentifier).isPinned
                        ? "pin.fill" : "pin",
                    label: String(localized: "Pin"),
                    tone: .clear
                ) {
                    app.model.togglePinned(asset.localIdentifier)
                }
            }
        }
    }

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    Button {
                        // Fill whichever pane is not already showing this one; prefer left.
                        if rightIndex == index {
                            rightIndex = leftIndex
                            leftIndex = index
                        } else if leftIndex == index {
                            // Already on the left; move it right instead.
                            leftIndex = rightIndex
                            rightIndex = index
                        } else {
                            rightIndex = index
                        }
                    } label: {
                        AssetImageView(assetID: asset.localIdentifier, targetSide: 100)
                            .frame(width: 52, height: 52)
                            .clipShape(.rect(cornerRadius: Radius.gridTile))
                            .overlay {
                                if index == leftIndex || index == rightIndex {
                                    RoundedRectangle(cornerRadius: Radius.gridTile)
                                        .strokeBorder(Palette.accent, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Candidate \((index + 1).formatted())"))
                }
            }
            .padding(.horizontal, Space.l)
        }
        .padding(.bottom, Space.l)
    }
}

/// Groups that might be duplicates — same capture second, same dimensions. Language stays
/// at "possible": nothing here has compared a single pixel, and nothing here deletes.
struct DuplicatesListView: View {
    let assets: [HiddenAsset]

    @State private var viewerAssets: [HiddenAsset] = []
    @State private var viewerTarget: ViewerTarget?

    private var groups: [[HiddenAsset]] {
        DuplicateFinder.possibleDuplicateGroups(in: assets)
    }

    var body: some View {
        List {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s) {
                            ForEach(Array(group.enumerated()), id: \.element.id) { index, asset in
                                Button {
                                    viewerAssets = group
                                    viewerTarget = ViewerTarget(index: index)
                                } label: {
                                    AssetImageView(assetID: asset.localIdentifier, targetSide: 150)
                                        .frame(width: 96, height: 96)
                                        .clipShape(.rect(cornerRadius: Radius.thumb))
                                        .blurredIfNeeded()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("\(group.count.formatted()) possible duplicates · \(group.first?.creationDate.formatted(date: .abbreviated, time: .shortened) ?? "")")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Possible Duplicates"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Possible Duplicates"),
                    systemImage: "square.on.square",
                    description: Text("Items captured in the same second with the same dimensions would appear here."))
            }
        }
        .fullScreenCover(item: $viewerTarget) { target in
            ViewerView(assets: viewerAssets, index: target.index) { viewerTarget = nil }
        }
    }
}
