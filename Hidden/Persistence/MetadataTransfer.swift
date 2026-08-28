import Foundation
import SwiftData

/// The documented, versioned export of the app's metadata layer. Small on purpose: it
/// carries identifiers and the user's own annotations, never media. An identifier that no
/// longer resolves after a library change simply imports as a dormant record.
struct MetadataExport: Codable {
    var version: Int = 1
    var exportedAt: Date
    var records: [RecordDTO]
    var tags: [String]
    var notes: [NoteDTO]
    var bookmarks: [BookmarkDTO]
    var smartCollections: [SmartCollectionDTO]
    var queues: [QueueDTO]

    struct RecordDTO: Codable {
        var assetID: String
        var firstSeenAt: Date
        var firstObservedHiddenAt: Date?
        var lastObservedHiddenAt: Date?
        var firstObservedFavoriteAt: Date?
        var firstViewedAt: Date?
        var lastViewedAt: Date?
        var viewCount: Int
        var shuffleExposureCount: Int
        var reviewState: String
        var isAppFavorite: Bool
        var isPinned: Bool
        var rating: Int
        var tagNames: [String]
        var playbackPosition: TimeInterval
        var playbackCompleted: Bool
    }

    struct NoteDTO: Codable {
        var assetID: String
        var text: String
        var createdAt: Date
        var updatedAt: Date
    }

    struct BookmarkDTO: Codable {
        var assetID: String
        var timestamp: TimeInterval
        var note: String
    }

    struct SmartCollectionDTO: Codable {
        var name: String
        var filter: LibraryFilter
        var sort: String
    }

    struct QueueDTO: Codable {
        var name: String
        var itemIDs: [String]
    }
}

enum MetadataTransferError: LocalizedError {
    case unsupportedVersion(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return String(localized: "This backup was made by a newer version of Hidden (format \(version)).")
        case .unreadable:
            return String(localized: "This file isn't a Hidden metadata backup.")
        }
    }
}

@MainActor
enum MetadataTransfer {
    /// Whether history is included is the user's call — an export shared onward should not
    /// have to carry viewing behaviour.
    static func export(store: MetadataStore, includeHistory: Bool) throws -> Data {
        let records = store.allRecords().map { record in
            MetadataExport.RecordDTO(
                assetID: record.assetID,
                firstSeenAt: record.firstSeenAt,
                firstObservedHiddenAt: record.firstObservedHiddenAt,
                lastObservedHiddenAt: record.lastObservedHiddenAt,
                firstObservedFavoriteAt: record.firstObservedFavoriteAt,
                firstViewedAt: includeHistory ? record.firstViewedAt : nil,
                lastViewedAt: includeHistory ? record.lastViewedAt : nil,
                viewCount: includeHistory ? record.viewCount : 0,
                shuffleExposureCount: includeHistory ? record.shuffleExposureCount : 0,
                reviewState: record.reviewStateRaw,
                isAppFavorite: record.isAppFavorite,
                isPinned: record.isPinned,
                rating: record.rating,
                tagNames: record.tagNames,
                playbackPosition: includeHistory ? record.playbackPosition : 0,
                playbackCompleted: includeHistory ? record.playbackCompleted : false)
        }

        let notes = fetchAll(AssetNote.self, store: store).map {
            MetadataExport.NoteDTO(assetID: $0.assetID, text: $0.text,
                                   createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
        let bookmarks = fetchAll(VideoBookmark.self, store: store).map {
            MetadataExport.BookmarkDTO(assetID: $0.assetID, timestamp: $0.timestamp, note: $0.note)
        }

        let export = MetadataExport(
            exportedAt: .now,
            records: records,
            tags: store.allTags().map(\.name),
            notes: notes,
            bookmarks: bookmarks,
            smartCollections: store.allSmartCollections().map {
                MetadataExport.SmartCollectionDTO(name: $0.name, filter: $0.filter,
                                                  sort: $0.sortRaw)
            },
            queues: store.allQueues().map {
                MetadataExport.QueueDTO(name: $0.name, itemIDs: $0.itemIDs)
            })

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    /// Merge an export into the store. Existing rows win on conflicts of identity but take
    /// the backup's annotations where the local row has none — a restore after reinstall is
    /// the whole point, and then every row is new anyway.
    static func importData(_ data: Data, into store: MetadataStore) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export: MetadataExport
        do {
            export = try decoder.decode(MetadataExport.self, from: data)
        } catch {
            throw MetadataTransferError.unreadable
        }
        guard export.version <= 1 else {
            throw MetadataTransferError.unsupportedVersion(export.version)
        }

        for name in export.tags {
            store.registerTag(name)
        }

        var imported = 0
        for dto in export.records {
            let record = store.ensureRecord(for: dto.assetID)
            record.firstSeenAt = min(record.firstSeenAt, dto.firstSeenAt)
            record.firstObservedHiddenAt = earliest(record.firstObservedHiddenAt, dto.firstObservedHiddenAt)
            record.lastObservedHiddenAt = latest(record.lastObservedHiddenAt, dto.lastObservedHiddenAt)
            record.firstObservedFavoriteAt = earliest(record.firstObservedFavoriteAt, dto.firstObservedFavoriteAt)
            record.firstViewedAt = earliest(record.firstViewedAt, dto.firstViewedAt)
            record.lastViewedAt = latest(record.lastViewedAt, dto.lastViewedAt)
            record.viewCount = max(record.viewCount, dto.viewCount)
            record.shuffleExposureCount = max(record.shuffleExposureCount, dto.shuffleExposureCount)
            if record.reviewState == .unreviewed {
                record.reviewStateRaw = dto.reviewState
            }
            record.isAppFavorite = record.isAppFavorite || dto.isAppFavorite
            record.isPinned = record.isPinned || dto.isPinned
            record.rating = max(record.rating, dto.rating)
            record.tagNames = Array(Set(record.tagNames).union(dto.tagNames)).sorted()
            if record.playbackPosition == 0 { record.playbackPosition = dto.playbackPosition }
            record.playbackCompleted = record.playbackCompleted || dto.playbackCompleted
            imported += 1
        }

        for dto in export.notes where store.note(for: dto.assetID) == nil {
            store.context.insert(AssetNote(assetID: dto.assetID, text: dto.text,
                                           createdAt: dto.createdAt))
        }
        for dto in export.bookmarks {
            store.context.insert(VideoBookmark(assetID: dto.assetID,
                                               timestamp: dto.timestamp, note: dto.note))
        }

        let existingCollections = Set(store.allSmartCollections().map(\.name))
        for dto in export.smartCollections where !existingCollections.contains(dto.name) {
            store.addSmartCollection(name: dto.name, filter: dto.filter,
                                     sort: LibrarySort(rawValue: dto.sort) ?? .recentlyObserved)
        }
        let existingQueues = Set(store.allQueues().map(\.name))
        for dto in export.queues where !existingQueues.contains(dto.name) {
            store.addQueue(name: dto.name, itemIDs: dto.itemIDs)
        }

        store.save()
        return imported
    }

    private static func fetchAll<T: PersistentModel>(_ type: T.Type,
                                                     store: MetadataStore) -> [T] {
        (try? store.context.fetch(FetchDescriptor<T>())) ?? []
    }

    private static func earliest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): return min(a, b)
        default: return a ?? b
        }
    }

    private static func latest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): return max(a, b)
        default: return a ?? b
        }
    }
}
