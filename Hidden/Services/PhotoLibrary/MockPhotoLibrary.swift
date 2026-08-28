import AVFoundation
import Foundation
import Observation
import UIKit

/// A deterministic synthetic library, for tests, previews and CI screenshots.
///
/// Everything about it comes from the seed: the same seed always produces the same assets
/// with the same dates, kinds, favourites and colours. `simctl` cannot mark seeded media as
/// hidden, so CI runs the app against this instead — launched with `-UITestMockLibrary`.
@MainActor
@Observable
final class MockPhotoLibrary: PhotoLibraryProviding {
    private(set) var accessState: AccessState = .available
    private(set) var changeGeneration: Int = 0

    private var assets: [HiddenAsset]

    init(count: Int = 240, seed: UInt64 = 1) {
        assets = Self.generate(count: count, seed: seed)
    }

    func requestAccess() async -> AccessState { accessState }
    func refreshAccess() {}

    func fetchHiddenAssets() async -> [HiddenAsset] { assets }

    func setFavorite(_ assetID: String, _ value: Bool) async throws {
        guard let index = assets.firstIndex(where: { $0.localIdentifier == assetID }) else { return }
        assets[index].isFavorite = value
        changeGeneration &+= 1
    }

    func unhide(_ assetID: String) async throws {
        assets.removeAll { $0.localIdentifier == assetID }
        changeGeneration &+= 1
    }

    func delete(_ assetIDs: [String]) async throws {
        let removing = Set(assetIDs)
        assets.removeAll { removing.contains($0.localIdentifier) }
        changeGeneration &+= 1
    }

    // MARK: Generation

    /// Nonisolated and pure so unit tests can build 20,000-asset libraries off the main actor.
    nonisolated static func generate(count: Int, seed: UInt64) -> [HiddenAsset] {
        var rng = SeededGenerator(seed: seed)
        var assets: [HiddenAsset] = []
        assets.reserveCapacity(count)

        // A fixed anchor rather than `.now`, so the library is byte-for-byte identical
        // between runs — screenshots, tests and failure reproductions all agree.
        let anchor = Date(timeIntervalSince1970: 1_756_000_000)   // 2025-08-24

        for index in 0..<count {
            let isVideo = UInt64.random(in: 0..<100, using: &rng) < 22
            // Capture dates fan out over roughly six years, denser recently.
            let daysBack = Double(UInt64.random(in: 0..<2_200, using: &rng))
            let weighted = pow(daysBack / 2_200, 1.6) * 2_200
            let secondsBack = weighted * 86_400 + Double(UInt64.random(in: 0..<86_400, using: &rng))
            let creation = anchor.addingTimeInterval(-secondsBack)

            var subtypes: MediaSubtypes = []
            var duration: TimeInterval = 0
            var width = 3024, height = 4032

            if isVideo {
                duration = Double(UInt64.random(in: 4..<1_200, using: &rng))
                width = 1920; height = 1080
                if UInt64.random(in: 0..<100, using: &rng) < 8 { subtypes.insert(.slowMotion) }
                else if UInt64.random(in: 0..<100, using: &rng) < 6 { subtypes.insert(.timeLapse) }
            } else {
                let shape = UInt64.random(in: 0..<100, using: &rng)
                if shape < 25 { swap(&width, &height) }          // landscape
                else if shape < 32 { width = 2048; height = 2048 } // square
                if UInt64.random(in: 0..<100, using: &rng) < 10 { subtypes.insert(.livePhoto) }
                if UInt64.random(in: 0..<100, using: &rng) < 12 {
                    subtypes.insert(.screenshot)
                    width = 1179; height = 2556
                }
            }

            let hasLocation = UInt64.random(in: 0..<100, using: &rng) < 40
            assets.append(HiddenAsset(
                localIdentifier: String(format: "mock-%05d", index),
                kind: isVideo ? .video : .photo,
                creationDate: creation,
                modificationDate: creation,
                pixelWidth: width,
                pixelHeight: height,
                duration: duration,
                isFavorite: UInt64.random(in: 0..<100, using: &rng) < 15,
                subtypes: subtypes,
                latitude: hasLocation ? 24.7 + Double(UInt64.random(in: 0..<300, using: &rng)) / 100 : nil,
                longitude: hasLocation ? 46.6 + Double(UInt64.random(in: 0..<300, using: &rng)) / 100 : nil))
        }

        return assets.sorted { $0.creationDate > $1.creationDate }
    }
}

/// Draws deterministic thumbnails for the mock library: a calm two-tone gradient with a
/// simple scene, unique per asset, so screenshots look like a real populated app rather
/// than a wall of grey squares.
@MainActor
final class MockMediaProvider: MediaProviding {
    private let cache = NSCache<NSString, UIImage>()
    let cloudOnlyIdentifiers: Set<String> = []

    init() {
        cache.countLimit = 600
    }

    func cachedImage(for assetID: String, side: CGFloat) -> UIImage? {
        cache.object(forKey: key(assetID, side))
    }

    func image(for assetID: String, side: CGFloat, purpose: MediaPurpose) async -> UIImage? {
        if let cached = cachedImage(for: assetID, side: side) { return cached }
        let rendered = Self.render(assetID: assetID, side: min(side, 640))
        cache.setObject(rendered, forKey: key(assetID, side))
        return rendered
    }

    func startCaching(_ assetIDs: [String], side: CGFloat) {}
    func stopCaching(_ assetIDs: [String], side: CGFloat) {}
    func clearMemoryCache() { cache.removeAllObjects() }

    func playerItem(for assetID: String) async -> AVPlayerItem? { nil }

    private func key(_ id: String, _ side: CGFloat) -> NSString {
        "\(id)|\(Int(side))" as NSString
    }

    private nonisolated static func render(assetID: String, side: CGFloat) -> UIImage {
        // The identifier's stable hash drives every visual decision.
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in assetID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let hue = CGFloat(hash % 360) / 360
        let hillPhase = CGFloat((hash >> 8) % 100) / 100
        let sunX = 0.2 + CGFloat((hash >> 16) % 60) / 100

        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let ctx = context.cgContext
            let top = UIColor(hue: hue, saturation: 0.38, brightness: 0.92, alpha: 1)
            let bottom = UIColor(hue: fmod(hue + 0.07, 1), saturation: 0.52, brightness: 0.55, alpha: 1)
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: .zero,
                                       end: CGPoint(x: 0, y: side), options: [])
            }

            // A sun.
            let sunRadius = side * 0.09
            ctx.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: side * sunX, y: side * 0.18,
                                       width: sunRadius * 2, height: sunRadius * 2))

            // A hill line.
            ctx.setFillColor(UIColor(hue: fmod(hue + 0.5, 1), saturation: 0.3,
                                     brightness: 0.25, alpha: 0.75).cgColor)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: side))
            path.addLine(to: CGPoint(x: 0, y: side * (0.62 + hillPhase * 0.2)))
            path.addQuadCurve(to: CGPoint(x: side, y: side * (0.72 + hillPhase * 0.12)),
                              control: CGPoint(x: side * 0.5, y: side * (0.45 + hillPhase * 0.25)))
            path.addLine(to: CGPoint(x: side, y: side))
            ctx.addPath(path)
            ctx.fillPath()
        }
    }
}
