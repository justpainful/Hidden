import Foundation
import Observation
import UIKit
import Vision

/// Optional on-device text recognition over photo thumbnails, so search can find the
/// words inside screenshots and documents. Everything happens on this device: images come
/// from the local thumbnail pipeline (network never allowed), text lands in the local
/// database, and clearing the index erases all of it.
@MainActor
@Observable
final class TextIndexService {
    private(set) var isRunning = false
    private(set) var indexedCount = 0
    private(set) var pendingCount = 0
    private(set) var lastError: String?

    private var task: Task<Void, Never>?

    private let model: LibraryModel
    private let store: MetadataStore

    init(model: LibraryModel, store: MetadataStore) {
        self.model = model
        self.store = store
    }

    func refreshCounts() {
        let photos = model.assets.filter { !$0.isVideo }
        var indexed = 0
        for asset in photos where store.record(for: asset.localIdentifier)?.ocrText != nil {
            indexed += 1
        }
        indexedCount = indexed
        pendingCount = photos.count - indexed
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        task = Task { await run() }
    }

    func pause() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clearIndex() {
        pause()
        for record in store.allRecords() {
            record.ocrText = nil
        }
        store.save()
        refreshCounts()
    }

    /// Every indexed word, for the search layer.
    func textByAssetID() -> [String: String] {
        var result: [String: String] = [:]
        for record in store.allRecords() {
            if let text = record.ocrText, !text.isEmpty {
                result[record.assetID] = text
            }
        }
        return result
    }

    // MARK: The pass

    private func run() async {
        defer {
            isRunning = false
            refreshCounts()
        }
        refreshCounts()

        let photos = model.assets.filter { !$0.isVideo }
        for asset in photos {
            if Task.isCancelled { return }
            // Battery-aware: a pass that started on power should not keep grinding once the
            // battery is draining and low.
            if UIDevice.current.isBatteryMonitoringEnabled == false {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
            if UIDevice.current.batteryState == .unplugged,
               UIDevice.current.batteryLevel >= 0, UIDevice.current.batteryLevel < 0.2 {
                lastError = String(localized: "Paused — battery is low.")
                return
            }

            let id = asset.localIdentifier
            if store.record(for: id)?.ocrText != nil { continue }

            // Browsing purpose: the index never pulls originals from iCloud. An asset that
            // is not local is skipped this pass and picked up whenever it is.
            guard let image = await model.media.image(for: id, side: 1024, purpose: .browsing),
                  let cgImage = image.cgImage else {
                continue
            }

            let text = await Self.recognizeText(in: cgImage)
            if Task.isCancelled { return }
            store.ensureRecord(for: id).ocrText = text
            store.save()
            indexedCount += 1
            pendingCount = max(0, pendingCount - 1)

            // Breathe between items so scrolling stays smooth while the pass runs.
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private nonisolated static func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            var resumed = false
            let request = VNRecognizeTextRequest { request, _ in
                guard !resumed else { return }
                resumed = true
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: "")
            }
        }
    }
}
