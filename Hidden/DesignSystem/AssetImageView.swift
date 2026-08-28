import SwiftUI

/// Draws one asset. Every thumbnail and hero image in the app goes through here.
///
/// Loading is asynchronous and the placeholder is a calm tone rather than a spinner: at grid
/// scale a screen full of spinners looks broken even when nothing is wrong. Assets that live
/// only in iCloud say so instead of hanging — browsing never downloads originals.
struct AssetImageView: View {
    let assetID: String
    var targetSide: CGFloat = 400
    var purpose: MediaPurpose = .browsing
    var contentMode: ContentMode = .fill

    @Environment(\.app) private var app
    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?
    @State private var isUnavailable = false
    @State private var lastLoadedIdentifier: String?

    /// Which photograph, and how big — the two things that decide whether what is on screen
    /// is still the right bitmap. Size is bucketed so a point of layout drift does not throw
    /// away a good frame.
    private struct ImageRequest: Hashable {
        var identifier: String
        var pixels: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Palette.surfaceSunk

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .transition(.opacity)
                } else if isUnavailable {
                    Image(systemName: "icloud.slash")
                        .font(Typo.glyph(placeholderGlyphSide(in: proxy.size), .regular))
                        .foregroundStyle(Palette.textTertiary)
                        .accessibilityLabel(String(localized: "Not downloaded from iCloud"))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeOut(duration: 0.22), value: image != nil)
            .task(id: request(for: proxy.size)) { await load(request(for: proxy.size)) }
        }
    }

    private func placeholderGlyphSide(in size: CGSize) -> CGFloat {
        let proportional = min(size.width, size.height) * 0.22
        return min(max(proportional, 13), 44)
    }

    private func request(for size: CGSize) -> ImageRequest {
        ImageRequest(
            identifier: assetID,
            pixels: PhotoMediaProvider.requestSide(
                forSide: max(size.width, size.height, targetSide),
                scale: displayScale
            )
        )
    }

    private func load(_ request: ImageRequest) async {
        // Ask the cache before clearing anything, so a tile scrolling back into view keeps
        // its frame instead of flickering grey.
        if let cached = app.media.cachedImage(for: request.identifier, side: request.pixels) {
            image = cached
            isUnavailable = false
            return
        }

        // A resize of the same photograph keeps the old frame until the better one lands;
        // a different photograph must not show under the new tile.
        if request.identifier != lastLoadedIdentifier { image = nil }
        isUnavailable = false
        lastLoadedIdentifier = request.identifier

        let loaded = await app.media.image(for: request.identifier,
                                           side: request.pixels,
                                           purpose: purpose)
        if let loaded {
            image = loaded
        } else {
            isUnavailable = true
        }
    }
}

/// Marks videos and Live Photos without covering the image. Furniture, not content: it does
/// not grow past the tile it belongs to, and its meaning is carried by the spoken label.
///
/// It draws nothing at all for a plain photo — the padding and scrim are modifiers, and a
/// badge whose content is empty still renders them as a small blank pill on every tile.
struct MediaBadge: View {
    let asset: HiddenAsset

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if asset.isVideo || asset.isLivePhoto {
            badge
        }
    }

    private var badge: some View {
        Group {
            if asset.isVideo {
                Label(asset.duration.shortDuration, systemImage: "play.fill")
            } else {
                Label(String(localized: "Live"), systemImage: "livephoto")
            }
        }
        .font(Typo.scaled(11, .semibold))
        .chromeTypeSize(.xxLarge)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(scrim, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var scrim: Color {
        contrast == .increased || reduceTransparency
            ? Color.black.opacity(0.82)
            : Palette.labelScrim
    }

    private var spokenLabel: String {
        if asset.isVideo {
            return String(localized: "Video, \(asset.duration.spokenDuration)")
        }
        if asset.isLivePhoto { return String(localized: "Live Photo") }
        return ""
    }
}

/// One tile in a media grid: the image, its badges, and the favourite mark.
struct AssetTile: View {
    let asset: HiddenAsset
    var isSelected = false

    @Environment(\.app) private var app

    var body: some View {
        AssetImageView(assetID: asset.localIdentifier, targetSide: 300)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Radius.gridTile))
            .overlay(alignment: .bottomLeading) {
                MediaBadge(asset: asset).padding(Space.xs)
            }
            .overlay(alignment: .topTrailing) {
                if asset.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(Typo.glyph(11))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(Space.xs)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.gridTile)
                        .strokeBorder(Palette.accent, lineWidth: 3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typo.glyph(18))
                        .foregroundStyle(.white, Palette.accent)
                        .padding(Space.xs)
                        .accessibilityHidden(true)
                }
            }
            .blurredIfNeeded()
    }
}

extension View {
    /// The discreet-viewing preference: thumbnails stay blurred until the viewer opens them.
    @ViewBuilder
    func blurredIfNeeded() -> some View {
        modifier(BlurThumbnailModifier())
    }
}

private struct BlurThumbnailModifier: ViewModifier {
    @Environment(\.app) private var app

    func body(content: Content) -> some View {
        if app.settings.blurThumbnails {
            content.blur(radius: 18, opaque: true)
                .clipShape(.rect(cornerRadius: Radius.gridTile))
        } else {
            content
        }
    }
}

extension TimeInterval {
    /// `2:07`, or `1:04:22` for anything over an hour, in the locale's own digits.
    var shortDuration: String {
        let total = wholeSeconds
        let duration = Duration.seconds(total)
        return total >= 3600
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }

    /// The same length in words, for VoiceOver.
    var spokenDuration: String {
        Duration.seconds(wholeSeconds)
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// A whole number of seconds that is safe to convert — a malformed clip shows `0:00`
    /// rather than trapping.
    private var wholeSeconds: Int {
        guard isFinite, self > 0 else { return 0 }
        return Int(min(rounded(), 359_999))
    }
}
