import SwiftUI

/// The complete accessible Hidden library: an edge-to-edge grid with sorting, composable
/// filters, adjustable density and selection.
struct LibraryView: View {
    @Environment(\.app) private var app

    @State private var sort: LibrarySort = .recentlyObserved
    @State private var filter: LibraryFilter = .none
    @State private var columns = 3
    @State private var showsFilters = false
    @State private var viewerTarget: ViewerTarget?
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var randomSeed: UInt64 = 1
    @State private var didLoadDefaults = false

    private var results: [HiddenAsset] {
        LibraryQuery.run(app.model.assets,
                         filter: filter,
                         sort: sort,
                         meta: app.model.metaByID,
                         randomSeed: randomSeed)
    }

    var body: some View {
        NavigationStack {
            Group {
                if app.model.assets.isEmpty {
                    HiddenEmptyStateView()
                } else {
                    grid
                }
            }
            .navigationTitle(Text("Library"))
            .toolbar { toolbarContent }
            .sheet(isPresented: $showsFilters) {
                FilterSheet(filter: $filter)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(item: $viewerTarget) { target in
                ViewerView(assets: results, index: target.index) { viewerTarget = nil }
            }
        }
        .onAppear {
            if !didLoadDefaults {
                didLoadDefaults = true
                sort = app.settings.defaultSort
                columns = app.settings.gridColumns
            }
        }
    }

    private var grid: some View {
        ScrollView {
            if filter.isActive {
                HStack {
                    Text("\(results.count.formatted()) items")
                        .font(Typo.meta)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button(String(localized: "Clear Filters")) { filter = .none }
                        .font(Typo.meta)
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)
            }

            MediaGridView(assets: results,
                          columns: columns,
                          selection: isSelecting ? $selection : nil) { index in
                viewerTarget = ViewerTarget(index: index)
            }
        }
        .refreshable { await app.model.refresh() }
        // Pinch anywhere on the grid to step density between 2 and 6 columns.
        .simultaneousGesture(
            MagnificationGesture()
                .onEnded { value in
                    withAnimation(.snappy) {
                        if value > 1.2 { columns = max(2, columns - 1) }
                        if value < 0.8 { columns = min(6, columns + 1) }
                    }
                    app.settings.gridColumns = columns
                }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isSelecting.toggle()
                if !isSelecting { selection = [] }
            } label: {
                Text(isSelecting ? String(localized: "Done") : String(localized: "Select"))
            }
        }

        if isSelecting && !selection.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        for id in selection { app.model.store.setAppFavorite(id, true) }
                        finishSelection()
                    } label: {
                        Label(String(localized: "App Favorite"), systemImage: "star")
                    }
                    Button {
                        for id in selection { app.model.store.setReviewState(id, .reviewed) }
                        finishSelection()
                    } label: {
                        Label(String(localized: "Mark Reviewed"), systemImage: "checkmark.circle")
                    }
                    Button {
                        for id in selection { app.model.store.setPinned(id, true) }
                        finishSelection()
                    } label: {
                        Label(String(localized: "Pin"), systemImage: "pin")
                    }
                } label: {
                    Text("\(selection.count.formatted()) selected")
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsFilters = true
                } label: {
                    Label(String(localized: "Filters"), systemImage: filter.isActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(String(localized: "Sort"), selection: $sort) {
                        ForEach(LibrarySort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    if sort == .random {
                        Button {
                            randomSeed = UInt64.random(in: 1..<UInt64.max)
                        } label: {
                            Label(String(localized: "Reshuffle"), systemImage: "shuffle")
                        }
                    }
                } label: {
                    Label(String(localized: "Sort"), systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func finishSelection() {
        // Refresh the meta the grid reads from, then leave selection mode.
        Task { await app.model.refresh() }
        selection = []
        isSelecting = false
    }
}

/// A viewer presentation target with identity, for `fullScreenCover(item:)`.
struct ViewerTarget: Identifiable {
    let id = UUID()
    var index: Int
}

/// The Hidden album came back empty, and the app cannot know which of the two truths caused
/// it. Say both, plainly.
struct HiddenEmptyStateView: View {
    @Environment(\.app) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                Image(systemName: "eye.slash")
                    .font(Typo.glyph(44, .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                    .padding(.top, Space.section * 2)

                Text("No Hidden Media Available")
                    .font(Typo.sectionTitle)

                Text("Either nothing is currently hidden in your Photos library, or the Hidden album's own protection is on. When \"Use Face ID\" is enabled for the Hidden album in Settings → Apps → Photos, iOS does not let any third-party app see those items — including this one, and this app's own lock cannot change that.")
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.section)

                Button {
                    Task { await app.model.refresh() }
                } label: {
                    Label(String(localized: "Check Again"), systemImage: "arrow.clockwise")
                        .font(Typo.control)
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: Hit.min)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
    }
}
