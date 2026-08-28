import AVFoundation
import AVKit
import SwiftUI

/// The app's own video transport: scrubber, times, speed, mute, restart — and playback
/// position remembered per asset, locally, without ever touching the original file.
struct HiddenVideoPlayer: View {
    let asset: HiddenAsset
    /// Whether this page is the one on screen; playback pauses the moment it is not.
    let isCurrent: Bool
    var onFinished: (() -> Void)?

    @Environment(\.app) private var app

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isMuted = true
    @State private var rate: Float = 1
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var isLoadFailed = false
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()
            } else {
                // The poster while the item resolves — or an honest failure state.
                AssetImageView(assetID: asset.localIdentifier,
                               targetSide: 1200,
                               purpose: .display,
                               contentMode: .fit)
                if isLoadFailed {
                    VStack(spacing: Space.s) {
                        Image(systemName: "icloud.slash")
                            .font(Typo.glyph(34, .regular))
                        Text("This video isn't available right now")
                            .font(Typo.label)
                    }
                    .foregroundStyle(.white)
                    .padding(Space.l)
                    .background(Palette.labelScrim, in: .rect(cornerRadius: Radius.panel))
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if player != nil {
                transport
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, 84)   // above the viewer's own action row
            }
        }
        .task(id: isCurrent) {
            if isCurrent {
                await loadIfNeeded()
                if app.settings.autoplayNext { play() }
            } else {
                pause()
                persistPosition(completed: false)
            }
        }
        .onDisappear {
            pause()
            persistPosition(completed: false)
            teardown()
        }
    }

    // MARK: Transport

    private var transport: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.m) {
                Text(currentTime.shortDuration)
                    .font(Typo.meta.monospacedDigit())
                    .foregroundStyle(.white)

                Slider(value: Binding(
                    get: { duration > 0 ? currentTime / duration : 0 },
                    set: { fraction in
                        isScrubbing = true
                        currentTime = fraction * duration
                    }
                ), onEditingChanged: { editing in
                    if !editing {
                        seek(to: currentTime)
                        isScrubbing = false
                    }
                })
                .tint(.white)
                .accessibilityLabel(String(localized: "Playback position"))

                Text("-\(max(duration - currentTime, 0).shortDuration)")
                    .font(Typo.meta.monospacedDigit())
                    .foregroundStyle(.white)
            }

            HStack(spacing: Space.m) {
                GlassIconButton(systemImage: "gobackward.10",
                                label: String(localized: "Back 10 Seconds"),
                                tone: .clear) {
                    seek(to: max(currentTime - 10, 0))
                }

                GlassIconButton(systemImage: isPlaying ? "pause.fill" : "play.fill",
                                label: isPlaying
                                    ? String(localized: "Pause")
                                    : String(localized: "Play"),
                                prominent: true,
                                tone: .clear) {
                    isPlaying ? pause() : play()
                }

                GlassIconButton(systemImage: "goforward.10",
                                label: String(localized: "Forward 10 Seconds"),
                                tone: .clear) {
                    seek(to: min(currentTime + 10, duration))
                }

                GlassIconButton(systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                label: isMuted
                                    ? String(localized: "Unmute")
                                    : String(localized: "Mute"),
                                tone: .clear) {
                    isMuted.toggle()
                    player?.isMuted = isMuted
                }

                Menu {
                    Picker(String(localized: "Speed"), selection: $rate) {
                        Text("0.5×").tag(Float(0.5))
                        Text("1×").tag(Float(1))
                        Text("1.5×").tag(Float(1.5))
                        Text("2×").tag(Float(2))
                    }
                    .onChange(of: rate) { _, newRate in
                        if isPlaying { player?.rate = newRate }
                    }
                    Button {
                        seek(to: 0)
                        play()
                    } label: {
                        Label(String(localized: "Restart"), systemImage: "arrow.counterclockwise")
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
                .accessibilityLabel(String(localized: "More Playback Options"))
            }
        }
    }

    // MARK: Player lifecycle

    private func loadIfNeeded() async {
        guard player == nil else { return }
        guard let real = app.media as? PhotoMediaProvider else {
            isLoadFailed = true
            return
        }
        guard let item = await real.playerItem(for: asset.localIdentifier) else {
            isLoadFailed = true
            return
        }

        let player = AVPlayer(playerItem: item)
        isMuted = app.settings.muteByDefault
        player.isMuted = isMuted
        self.player = player

        duration = item.duration.seconds.isFinite ? item.duration.seconds : asset.duration

        // Resume where the user left off, unless they had effectively finished.
        let saved = app.model.meta(for: asset.localIdentifier).playbackPosition
        if saved > 2, saved < duration - 2 {
            await player.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
            currentTime = saved
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            Task { @MainActor in
                guard !isScrubbing else { return }
                currentTime = time.seconds
                if duration <= 0, let item = player.currentItem,
                   item.duration.seconds.isFinite {
                    duration = item.duration.seconds
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                isPlaying = false
                persistPosition(completed: true)
                onFinished?()
            }
        }
    }

    private func play() {
        guard let player else { return }
        player.play()
        player.rate = rate
        isPlaying = true
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    private func seek(to seconds: TimeInterval) {
        currentTime = seconds
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func persistPosition(completed: Bool) {
        guard player != nil, duration > 0 else { return }
        app.model.store.recordPlayback(of: asset.localIdentifier,
                                       position: currentTime,
                                       duration: duration,
                                       completed: completed)
    }

    private func teardown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player = nil
    }
}

/// A bare `AVPlayerLayer` host: the transport above replaces `VideoPlayer`'s system chrome,
/// and drawing both would double every control.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
