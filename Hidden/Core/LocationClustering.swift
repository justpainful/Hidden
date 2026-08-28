import CoreLocation
import Foundation

/// A place-shaped cluster of assets, from coordinates PhotoKit already carries. Grid-based
/// and coarse on purpose: ~5km cells merge into "areas" without any remote analytics.
struct PlaceCluster: Identifiable, Sendable {
    /// Stable across runs: the rounded cell key.
    var id: String
    var latitude: Double
    var longitude: Double
    var assets: [HiddenAsset]
    var count: Int { assets.count }
}

enum LocationClustering {
    /// Cell size in degrees; ~0.05° is a few kilometres — a district, not a doorstep.
    static let cell = 0.05

    static func clusters(in assets: [HiddenAsset]) -> [PlaceCluster] {
        var byCell: [String: [HiddenAsset]] = [:]
        for asset in assets {
            guard let latitude = asset.latitude, let longitude = asset.longitude else { continue }
            let key = "\((latitude / cell).rounded())|\((longitude / cell).rounded())"
            byCell[key, default: []].append(asset)
        }
        return byCell.map { key, members in
            let latitude = members.compactMap(\.latitude).reduce(0, +) / Double(members.count)
            let longitude = members.compactMap(\.longitude).reduce(0, +) / Double(members.count)
            return PlaceCluster(id: key, latitude: latitude, longitude: longitude,
                                assets: members.sorted { $0.creationDate > $1.creationDate })
        }
        .sorted { $0.count > $1.count }
    }
}

/// Reverse geocoding, once per area, cached forever. Geocoding thousands of assets is
/// exactly what this avoids: only a cluster's centre is ever looked up, only when its row
/// is on screen, and the derived label is stored locally.
@MainActor
final class PlaceLabelCache {
    static let shared = PlaceLabelCache()

    private let geocoder = CLGeocoder()
    private var pending: Set<String> = []

    func cachedLabel(for cluster: PlaceCluster) -> String? {
        UserDefaults.standard.string(forKey: "placeLabel|\(cluster.id)")
    }

    /// The coordinate written as text — the honest fallback when geocoding is unavailable.
    func fallbackLabel(for cluster: PlaceCluster) -> String {
        String(format: "%.2f°, %.2f°", cluster.latitude, cluster.longitude)
    }

    func resolveLabel(for cluster: PlaceCluster) async -> String {
        if let cached = cachedLabel(for: cluster) { return cached }
        guard !pending.contains(cluster.id) else { return fallbackLabel(for: cluster) }
        pending.insert(cluster.id)
        defer { pending.remove(cluster.id) }

        let location = CLLocation(latitude: cluster.latitude, longitude: cluster.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return fallbackLabel(for: cluster)
        }
        let label = [placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .first ?? fallbackLabel(for: cluster)
        UserDefaults.standard.set(label, forKey: "placeLabel|\(cluster.id)")
        return label
    }
}
