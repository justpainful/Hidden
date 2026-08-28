import AVKit
import SwiftUI

/// Plays a shuffle queue: photos advance on a timer, videos play to completion where a
/// playable item exists, previous returns to the actual previous item, and the position is
/// saved continuously so leaving and relaunching resumes exactly here.
struct ShuffleSessionView: View {
    let queue: [HiddenAsset]
    let startIndex: Int
    let photoDuration: TimeInterval
    var onDismiss: () -> Void

    @Environment(\.app) private var app
    @State private var index: Int = 0
    @State private var isPaused = false
    @State private var showsChrome = true
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    /// Which position was last written to history, so pause/resume restarts of the step task
    /// do not double-count views.
    @State private var lastRecordedIndex = -1

    private var current: HiddenAsset? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let current {
                content(for: current)
            } else {
                sessionComplete
            }

            if showsChrome {
                chrome
            }
        }
        .statusBarHidden(!showsChrome)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) { showsChrome.toggle() }
        }
        .onAppear { index = startIndex }
        // Keyed on the pause state as well: unpausing restarts the photo timer.
        .task(id: "\(index)|\(isPaused)") { await stepChanged() }
        .onDisappear {
            player?.pause()
            removeEndObserver()
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(for asset: HiddenAsset) -> some View {
        if asset.isVideo, let player {
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .id(asset.id)
        } else {
            AssetImageView(assetID: asset.localIdentifier,
                           targetSide: 1400,
                           purpose: .display,
                           contentMode: .fit)
                .ignoresSafeArea()
                .id(asset.id)
                .transition(.opacity)
        }
    }

    private var sessionComplete: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "checkmark.circle")
                .font(Typo.glyph(52, .regular))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text("Queue finished")
                .font(Typo.sectionTitle)
                .foregroundStyle(.white)
            Text("Every item played once — nothing repeated.")
                .font(Typo.label)
                .foregroundStyle(.white.opacity(0.7))
            Button {
                ShuffleSessionStore.clear()
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

    private var chrome: some View {
        VStack {
            HStack {
                GlassIconButton(systemImage: "xmark",
                                label: String(localized: "Close"),
                                tone: .clear) {
                    ShuffleSessionStore.saveIndex(index)
                    onDismiss()
                }
                Spacer()
                Text("\(min(index + 1, queue.count).formatted()) / \(queue.count.formatted())")
                    .font(Typo.meta)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                Spacer()
                // Symmetry spacer so the count stays centred.
                Color.clear.frame(width: 46, height: 46)
            }
            .padding(.horizontal, Space.l)

            Spacer()

            GlassEffectContainer {
                HStack(spacing: Space.m) {
                    GlassIconButton(systemImage: "backward.fill",
                                    label: String(localized: "Previous"),
                                    tone: .clear) { previous() }

                    GlassIconButton(systemImage: isPaused ? "play.fill" : "pause.fill",
                                    label: isPaused
                                        ? String(localized: "Play")
                                        : String(localized: "Pause"),
                                    prominent: true,
                                    tone: .clear) { togglePause() }

                    GlassIconButton(systemImage: "forward.fill",
                                    label: String(localized: "Next"),
                                    tone: .clear) { next() }
                }
            }
            .padding(.bottom, Space.gutter)
        }
    }

    // MARK: Stepping

    private func stepChanged() async {
        guard let current else { return }
        ShuffleSessionStore.saveIndex(index)
        if lastRecordedIndex != index {
            lastRecordedIndex = index
            app.model.recordView(of: current.localIdentifier)
            app.model.store.recordShuffleExposure(of: current.localIdentifier)
        }

        player?.pause()
        removeEndObserver()
        player = nil

        if current.isVideo,
           let real = app.media as? PhotoMediaProvider,
           let item = await real.playerItem(for: current.localIdentifier) {
            guard !Task.isCancelled else { return }
            let player = AVPlayer(playerItem: item)
            player.isMuted = app.settings.muteByDefault
            self.player = player
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { _ in
                Task { @MainActor in next() }
            }
            if !isPaused { player.play() }
        } else {
            // A photo — or a clip with no playable item (iCloud offline, or the mock).
            // Either way it holds for the configured duration.
            let holdFor = current.isVideo ? max(photoDuration, 3) : photoDuration
            try? await Task.sleep(for: .seconds(holdFor))
            guard !Task.isCancelled, !isPaused else { return }
            withAnimation(.easeInOut(duration: 0.3)) { index += 1 }
        }
    }

    private func next() {
        withAnimation(.easeInOut(duration: 0.25)) { index += 1 }
    }

    private func previous() {
        withAnimation(.easeInOut(duration: 0.25)) { index = max(0, index - 1) }
    }

    private func togglePause() {
        isPaused.toggle()
        if let player {
            isPaused ? player.pause() : player.play()
        }
        // For photos the task key includes the pause state, so flipping it restarts the timer.
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
