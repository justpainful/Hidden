import SwiftUI

/// Show one item to someone else without exposing the rest of the library: no swiping into
/// neighbours, no metadata, no thumbnails — and when the app lock is on, leaving
/// presentation relocks the app so the library only returns after Face ID.
///
/// This is an app-level UX boundary, not a system sandbox, and the About page says so.
struct PresentationView: View {
    let asset: HiddenAsset
    var onDismiss: () -> Void

    @Environment(\.app) private var app
    @State private var showsClose = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if asset.isVideo {
                HiddenVideoPlayer(asset: asset, isCurrent: true)
            } else {
                AssetImageView(assetID: asset.localIdentifier,
                               targetSide: 1400,
                               purpose: .display,
                               contentMode: .fit)
                    .ignoresSafeArea()
            }

            if showsClose {
                VStack {
                    HStack {
                        GlassIconButton(systemImage: "xmark",
                                        label: String(localized: "End Presentation"),
                                        tone: .clear) {
                            // Relock first, so what appears behind the cover is the lock
                            // screen and never the grid.
                            if app.lock.isEnabled {
                                app.lock.lock()
                            }
                            onDismiss()
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Space.l)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) { showsClose.toggle() }
        }
    }
}
