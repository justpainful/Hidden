import SwiftUI

/// One item at a time, one decision each: keep, favorite, later. Fast enough that inbox
/// zero is realistic. Reviewed state belongs to this app; nothing here alters the original
/// asset except the explicit Favorite action.
struct ReviewView: View {
    let queue: [HiddenAsset]
    var onDismiss: () -> Void

    @Environment(\.app) private var app
    @State private var index = 0
    @State private var decided = 0
    /// The last few decisions, so Undo can walk back.
    @State private var history: [(index: Int, id: String, previous: ReviewState)] = []

    private var current: HiddenAsset? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let current {
                VStack(spacing: 0) {
                    header

                    AssetImageView(assetID: current.localIdentifier,
                                   targetSide: 1000,
                                   purpose: .display,
                                   contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottomLeading) {
                            MediaBadge(asset: current).padding(Space.m)
                        }

                    actions(for: current)
                }
            } else {
                finished
            }
        }
        .task(id: index) {
            if let current { app.model.recordView(of: current.localIdentifier) }
        }
    }

    private var header: some View {
        HStack {
            GlassIconButton(systemImage: "xmark",
                            label: String(localized: "Close"),
                            tone: .clear) { onDismiss() }
            Spacer()
            Text("\(decided.formatted()) / \(queue.count.formatted()) reviewed")
                .font(Typo.meta)
                .foregroundStyle(.white)
            Spacer()
            GlassIconButton(systemImage: "arrow.uturn.backward",
                            label: String(localized: "Undo"),
                            tone: .clear) { undo() }
                .opacity(history.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
    }

    private func actions(for asset: HiddenAsset) -> some View {
        GlassEffectContainer {
            HStack(spacing: Space.m) {
                GlassIconButton(systemImage: "checkmark",
                                label: String(localized: "Keep Hidden"),
                                prominent: true,
                                tone: .clear) {
                    decide(asset, .reviewed)
                }

                GlassIconButton(
                    systemImage: app.model.meta(for: asset.localIdentifier).isAppFavorite
                        ? "star.fill" : "star",
                    label: String(localized: "App Favorite"),
                    tone: .clear
                ) {
                    app.model.toggleAppFavorite(asset.localIdentifier)
                }

                GlassIconButton(systemImage: "heart",
                                label: String(localized: "Favorite"),
                                tone: .clear) {
                    guard !app.settings.readOnlyMode else { return }
                    Task { await app.model.toggleSystemFavorite(asset.localIdentifier) }
                }

                GlassIconButton(systemImage: "clock",
                                label: String(localized: "Review Later"),
                                tone: .clear) {
                    decide(asset, .reviewLater)
                }
            }
        }
        .padding(.bottom, Space.gutter)
    }

    private var finished: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "checkmark.seal")
                .font(Typo.glyph(52, .regular))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text("All reviewed")
                .font(Typo.sectionTitle)
                .foregroundStyle(.white)
            Text("\(decided.formatted()) decisions.")
                .font(Typo.label)
                .foregroundStyle(.white.opacity(0.7))
            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(Typo.control)
                    .padding(.horizontal, Space.xl)
                    .frame(minHeight: Hit.min)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func decide(_ asset: HiddenAsset, _ state: ReviewState) {
        let id = asset.localIdentifier
        history.append((index, id, app.model.meta(for: id).reviewState))
        if history.count > 50 { history.removeFirst() }
        app.model.setReviewState(id, state)
        decided += 1
        withAnimation(.snappy) { index += 1 }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        app.model.setReviewState(last.id, last.previous)
        decided = max(0, decided - 1)
        withAnimation(.snappy) { index = last.index }
    }
}
