import Foundation
import Observation
import Photos

/// The real thing: PhotoKit, the system Hidden smart album, and honest state when the system
/// withholds it.
///
/// There is no supported way for a third-party app to authenticate and unlock the system
/// Hidden album. When the user has "Use Face ID" enabled for Hidden in Photos settings,
/// PhotoKit simply returns no hidden assets; this class reports that as `hiddenEmpty` and
/// nothing here tries to work around it.
@MainActor
@Observable
final class HiddenPhotoLibrary: PhotoLibraryProviding {
    private(set) var accessState: AccessState = .notDetermined
    private(set) var changeGeneration: Int = 0

    private var observer: ChangeObserver?

    init() {
        refreshAccess()
    }

    // MARK: Access

    func requestAccess() async -> AccessState {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
        }
        apply(status)
        return accessState
    }

    func refreshAccess() {
        apply(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private func apply(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized:
            // Whether this lands on `available` or `hiddenEmpty` is only known after a fetch;
            // start from `hiddenEmpty` and let the first fetch upgrade it.
            if accessState != .available { accessState = .hiddenEmpty }
            startObserving()
        case .limited:
            accessState = .limited
            startObserving()
        case .denied:     accessState = .denied
        case .restricted: accessState = .restricted
        default:          accessState = .notDetermined
        }
    }

    // MARK: Fetching

    func fetchHiddenAssets() async -> [HiddenAsset] {
        guard accessState.canRead else { return [] }

        // Off the main actor: faulting thousands of PHAssets is thousands of small reads
        // against the Photos database.
        let snapshots = await Task.detached(priority: .userInitiated) {
            Self.fetchHiddenSnapshots()
        }.value

        if accessState != .limited {
            accessState = snapshots.isEmpty ? .hiddenEmpty : .available
        }
        return snapshots
    }

    private nonisolated static func fetchHiddenSnapshots() -> [HiddenAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = true

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumAllHidden, options: nil)
        guard let hidden = collections.firstObject else { return [] }

        let result = PHAsset.fetchAssets(in: hidden, options: options)
        var assets: [HiddenAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(HiddenAsset(asset))
        }
        return assets
    }

    nonisolated static func asset(for identifier: String) -> PHAsset? {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: options).firstObject
    }

    nonisolated static func assets(for identifiers: [String]) -> [String: PHAsset] {
        guard !identifiers.isEmpty else { return [:] }
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: options)
        var map: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in map[asset.localIdentifier] = asset }
        return map
    }

    // MARK: Writing back

    func setFavorite(_ assetID: String, _ value: Bool) async throws {
        guard let asset = Self.asset(for: assetID) else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = value
        }
    }

    func unhide(_ assetID: String) async throws {
        guard let asset = Self.asset(for: assetID) else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isHidden = false
        }
    }

    func delete(_ assetIDs: [String]) async throws {
        let found = Self.assets(for: assetIDs)
        let assets = assetIDs.compactMap { found[$0] }
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    // MARK: Change observing

    private func startObserving() {
        guard observer == nil else { return }
        let observer = ChangeObserver { [weak self] in
            Task { @MainActor in self?.changeGeneration &+= 1 }
        }
        PHPhotoLibrary.shared().register(observer)
        self.observer = observer
    }
}

/// `PHPhotoLibraryChangeObserver` requires an `NSObject`; keeping it in its own tiny class
/// lets the service stay a clean `@Observable`.
///
/// It reports only *that* something changed. A hidden-album fetch cannot be diffed reliably
/// through `PHChange` in every case (protection toggles do not itemise), so the library model
/// refetches and diffs against its own snapshot instead.
private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}

extension HiddenAsset {
    /// Snapshot a live `PHAsset` into the plain value everything downstream consumes.
    init(_ asset: PHAsset) {
        var subtypes: MediaSubtypes = []
        let raw = asset.mediaSubtypes
        if raw.contains(.photoLive)        { subtypes.insert(.livePhoto) }
        if raw.contains(.photoScreenshot)  { subtypes.insert(.screenshot) }
        if raw.contains(.photoPanorama)    { subtypes.insert(.panorama) }
        if raw.contains(.photoHDR)         { subtypes.insert(.hdr) }
        if raw.contains(.photoDepthEffect) { subtypes.insert(.depthEffect) }
        if raw.contains(.videoHighFrameRate) { subtypes.insert(.slowMotion) }
        if raw.contains(.videoTimelapse)   { subtypes.insert(.timeLapse) }
        if raw.contains(.videoCinematic)   { subtypes.insert(.cinematic) }

        self.init(localIdentifier: asset.localIdentifier,
                  kind: asset.mediaType == .video ? .video : .photo,
                  creationDate: asset.creationDate ?? asset.modificationDate ?? .distantPast,
                  modificationDate: asset.modificationDate,
                  pixelWidth: asset.pixelWidth,
                  pixelHeight: asset.pixelHeight,
                  duration: asset.duration,
                  isFavorite: asset.isFavorite,
                  subtypes: subtypes,
                  latitude: asset.location?.coordinate.latitude,
                  longitude: asset.location?.coordinate.longitude)
    }
}
