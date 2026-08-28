import Photos
import PhotosUI
import SwiftUI

/// A Live Photo in the viewer: the still shows immediately, the motion arrives when it
/// resolves, and playback follows the system convention — press to play. In mock mode (or
/// while iCloud withholds the pair) the page is simply the zoomable still.
struct LivePhotoPage: View {
    let asset: HiddenAsset
    let isCurrent: Bool

    @Environment(\.app) private var app
    @State private var livePhoto: PHLivePhoto?

    var body: some View {
        ZStack {
            if let livePhoto {
                LivePhotoLayerView(livePhoto: livePhoto)
                    .ignoresSafeArea()
            } else {
                ZoomableAssetView(assetID: asset.localIdentifier)
            }
        }
        .task(id: isCurrent) {
            guard isCurrent, livePhoto == nil,
                  let real = app.media as? PhotoMediaProvider else { return }
            livePhoto = await real.livePhoto(
                for: asset.localIdentifier,
                targetSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight))
        }
    }
}

private struct LivePhotoLayerView: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.livePhoto = livePhoto
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        view.livePhoto = livePhoto
    }
}
