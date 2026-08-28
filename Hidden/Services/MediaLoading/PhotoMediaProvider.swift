import AVFoundation
import Photos
import UIKit

/// Loads and caches thumbnails from PhotoKit, and reports which assets are not available
/// offline. Grids never touch the network; a deliberately opened photo may — to Apple's
/// iCloud, where the photo already lives. Nothing is ever sent anywhere.
@MainActor
final class PhotoMediaProvider: MediaProviding {
    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()

    private(set) var cloudOnlyIdentifiers: Set<String> = []

    init() {
        cache.countLimit = 900
        cache.totalCostLimit = 96 * 1024 * 1024
        manager.allowsCachingHighQualityImages = false
    }

    // MARK: Images

    func cachedImage(for assetID: String, side: CGFloat) -> UIImage? {
        cache.object(forKey: Self.cacheKey(assetID, side))
    }

    func image(for assetID: String, side: CGFloat, purpose: MediaPurpose) async -> UIImage? {
        if let cached = cachedImage(for: assetID, side: side) { return cached }
        guard let asset = HiddenPhotoLibrary.asset(for: assetID) else { return nil }

        let targetSize = CGSize(width: side, height: side)
        let options = Self.options(for: purpose)
        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(for: asset,
                                 targetSize: targetSize,
                                 contentMode: .aspectFill,
                                 options: options) { image, info in
                // `.opportunistic` calls back twice; only the final result should resume.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, !resumed else { return }
                resumed = true
                if (info?[PHImageResultIsInCloudKey] as? Bool) == true, image == nil {
                    self.recordCloudOnly(assetID)
                }
                continuation.resume(returning: image)
            }
        }

        if let image {
            cache.setObject(image, forKey: Self.cacheKey(assetID, side),
                            cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    // MARK: Prefetching

    func startCaching(_ assetIDs: [String], side: CGFloat) {
        let found = HiddenPhotoLibrary.assets(for: assetIDs)
        let assets = assetIDs.compactMap { found[$0] }
        guard !assets.isEmpty else { return }
        manager.startCachingImages(for: assets,
                                   targetSize: CGSize(width: side, height: side),
                                   contentMode: .aspectFill,
                                   options: Self.options(for: .browsing))
    }

    func stopCaching(_ assetIDs: [String], side: CGFloat) {
        let found = HiddenPhotoLibrary.assets(for: assetIDs)
        let assets = assetIDs.compactMap { found[$0] }
        guard !assets.isEmpty else { return }
        manager.stopCachingImages(for: assets,
                                  targetSize: CGSize(width: side, height: side),
                                  contentMode: .aspectFill,
                                  options: Self.options(for: .browsing))
    }

    func clearMemoryCache() {
        cache.removeAllObjects()
        manager.stopCachingImagesForAllAssets()
    }

    // MARK: Video

    /// The playable item for a clip the user has opened.
    func playerItem(for assetID: String) async -> AVPlayerItem? {
        guard let asset = HiddenPhotoLibrary.asset(for: assetID) else { return nil }
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestPlayerItem(forVideo: asset, options: options) { item, info in
                guard !resumed else { return }
                resumed = true
                if (info?[PHImageResultIsInCloudKey] as? Bool) == true, item == nil {
                    self.recordCloudOnly(assetID)
                }
                continuation.resume(returning: item)
            }
        }
    }

    // MARK: Plumbing

    /// Photos runs result handlers on a queue of its own choosing; hop before mutating.
    nonisolated private func recordCloudOnly(_ identifier: String) {
        Task { @MainActor in self.cloudOnlyIdentifiers.insert(identifier) }
    }

    /// The pixel side to ask Photos for, rounded up onto a shared ladder so the prefetcher
    /// and the tiles agree — Photos matches a cached frame by exact numbers.
    nonisolated static func requestSide(forSide side: CGFloat, scale: CGFloat) -> CGFloat {
        let step: CGFloat = 128
        let pixels = max(side, 1) * max(scale, 1)
        let rounded = (pixels / step).rounded(.up) * step
        return min(max(rounded, step), 4096)
    }

    private static func options(for purpose: MediaPurpose) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = purpose.allowsNetwork
        options.deliveryMode = purpose == .display ? .highQualityFormat : .opportunistic
        options.resizeMode = purpose == .display ? .none : .fast
        options.isSynchronous = false
        return options
    }

    private static func cacheKey(_ identifier: String, _ side: CGFloat) -> NSString {
        "\(identifier)|\(Int(side))" as NSString
    }
}
