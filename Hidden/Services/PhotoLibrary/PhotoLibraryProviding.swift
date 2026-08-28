import AVFoundation
import Foundation
import UIKit

/// The app's relationship to the Photos library, stated honestly.
///
/// The distinction that matters most is the one PhotoKit refuses to make for us: an empty
/// Hidden fetch can mean "there is genuinely nothing hidden" or "the system's own Hidden
/// protection is withholding them from third-party apps", and no public API says which.
/// `hiddenEmpty` carries that ambiguity all the way to the UI, which explains it instead of
/// guessing.
enum AccessState: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    /// Limited Photos access: the app sees a user-chosen selection, which may or may not
    /// include anything from the Hidden album.
    case limited
    /// Full access and the Hidden fetch returned assets.
    case available
    /// Full access but the Hidden fetch came back empty — either nothing is hidden, or the
    /// system's authentication protection for Hidden is on.
    case hiddenEmpty

    var canRead: Bool {
        self == .available || self == .hiddenEmpty || self == .limited
    }
}

/// The library service the app talks to. The real implementation wraps PhotoKit; the mock
/// generates a deterministic synthetic library for tests, previews and CI screenshots.
@MainActor
protocol PhotoLibraryProviding: AnyObject {
    var accessState: AccessState { get }
    /// Bumped whenever the underlying library reports a change, so observers can refetch.
    var changeGeneration: Int { get }

    func requestAccess() async -> AccessState
    func refreshAccess()
    /// Every Hidden asset the app can currently see, newest capture first.
    func fetchHiddenAssets() async -> [HiddenAsset]

    // Write-backs. Each one is a supported PhotoKit change the user explicitly asked for.
    func setFavorite(_ assetID: String, _ value: Bool) async throws
    func unhide(_ assetID: String) async throws
    func delete(_ assetIDs: [String]) async throws
}

/// Why an image is being requested, which decides whether iCloud may be touched: indexing
/// and grids never pull originals down; a deliberately opened photo may.
enum MediaPurpose: Sendable {
    case browsing
    case display

    var allowsNetwork: Bool { self == .display }
}

/// Thumbnails and playable media, behind one face so the grid and viewer render identically
/// against PhotoKit and against the mock.
@MainActor
protocol MediaProviding: AnyObject {
    /// The cached frame if there is one, without suspending — lets a tile that scrolls back
    /// into view skip the placeholder flicker.
    func cachedImage(for assetID: String, side: CGFloat) -> UIImage?
    func image(for assetID: String, side: CGFloat, purpose: MediaPurpose) async -> UIImage?
    /// Warm decodes for the tiles about to scroll in.
    func startCaching(_ assetIDs: [String], side: CGFloat)
    func stopCaching(_ assetIDs: [String], side: CGFloat)
    func clearMemoryCache()

    /// The playable item for a clip the user has opened. The mock returns nil; the viewer
    /// falls back to the poster frame.
    func playerItem(for assetID: String) async -> AVPlayerItem?

    /// Identifiers Photos reported as living only in iCloud, so the UI can say so.
    var cloudOnlyIdentifiers: Set<String> { get }
}
