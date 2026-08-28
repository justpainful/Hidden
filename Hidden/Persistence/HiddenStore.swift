import Foundation
import SwiftData

/// Builds the model container and gives the rest of the app a small, typed API over it.
enum HiddenStore {
    static let schema = Schema([
        AssetRecord.self,
        TagRecord.self,
        AssetNote.self,
        VideoBookmark.self,
        SmartCollectionRecord.self,
        QueueRecord.self,
        LibrarySnapshotRecord.self,
        ChangeEventRecord.self,
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A corrupt metadata store must not brick the app: the media itself lives in
            // Photos, so the worst case of starting fresh is lost tags and history — bad,
            // but strictly better than an app that cannot launch.
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            } catch {
                fatalError("SwiftData container could not be created at all: \(error)")
            }
        }
    }
}

/// Main-actor facade over the metadata database.
///
/// Every mutation of app metadata goes through here so history toggles, incognito mode and
/// the change journal are enforced in one place rather than at each call site.
@MainActor
final class MetadataStore {
    let context: ModelContext

    /// While true, nothing about viewing is recorded. Flipped by Incognito mode.
    var recordsHistory = true
    /// While true, notable transitions are appended to the change journal.
    var keepsChangeLog = true

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Records

    func record(for assetID: String) -> AssetRecord? {
        var descriptor = FetchDescriptor<AssetRecord>(
            predicate: #Predicate { $0.assetID == assetID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func ensureRecord(for assetID: String) -> AssetRecord {
        if let existing = record(for: assetID) { return existing }
        let record = AssetRecord(assetID: assetID)
        context.insert(record)
        return record
    }

    func allRecords() -> [AssetRecord] {
        (try? context.fetch(FetchDescriptor<AssetRecord>())) ?? []
    }

    /// The snapshot dictionary the query layer works from.
    func metaByID() -> [String: AssetMeta] {
        var result: [String: AssetMeta] = [:]
        for record in allRecords() {
            result[record.assetID] = record.meta
        }
        return result
    }

    // MARK: Viewing history

    func recordView(of assetID: String) {
        guard recordsHistory else { return }
        let record = ensureRecord(for: assetID)
        let now = Date.now
        if record.firstViewedAt == nil {
            record.firstViewedAt = now
            log(.firstViewed, assetID: assetID)
        }
        record.lastViewedAt = now
        record.viewCount += 1
        save()
    }

    func recordShuffleExposure(of assetID: String) {
        guard recordsHistory else { return }
        ensureRecord(for: assetID).shuffleExposureCount += 1
        save()
    }

    func recordPlayback(of assetID: String, position: TimeInterval,
                        duration: TimeInterval, completed: Bool) {
        guard recordsHistory else { return }
        let record = ensureRecord(for: assetID)
        record.playbackPosition = completed ? 0 : position
        record.playbackDuration = duration
        record.lastPlaybackAt = .now
        if completed && !record.playbackCompleted {
            record.playbackCompleted = true
            log(.playbackCompleted, assetID: assetID)
        } else if !completed {
            record.playbackCompleted = false
        }
        save()
    }

    func clearViewingHistory() {
        for record in allRecords() {
            record.firstViewedAt = nil
            record.lastViewedAt = nil
            record.viewCount = 0
            record.shuffleExposureCount = 0
            record.playbackPosition = 0
            record.playbackCompleted = false
            record.lastPlaybackAt = nil
        }
        save()
    }

    // MARK: Organization

    func setAppFavorite(_ assetID: String, _ value: Bool) {
        let record = ensureRecord(for: assetID)
        guard record.isAppFavorite != value else { return }
        record.isAppFavorite = value
        log(value ? .appFavoriteAdded : .appFavoriteRemoved, assetID: assetID)
        save()
    }

    func setPinned(_ assetID: String, _ value: Bool) {
        ensureRecord(for: assetID).isPinned = value
        save()
    }

    func setRating(_ assetID: String, _ rating: Int) {
        ensureRecord(for: assetID).rating = max(0, min(5, rating))
        save()
    }

    func setReviewState(_ assetID: String, _ state: ReviewState) {
        let record = ensureRecord(for: assetID)
        guard record.reviewState != state else { return }
        record.reviewState = state
        if state == .reviewed { log(.reviewed, assetID: assetID) }
        save()
    }

    func addTag(_ name: String, to assetID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        registerTag(trimmed)
        let record = ensureRecord(for: assetID)
        guard !record.tagNames.contains(trimmed) else { return }
        record.tagNames.append(trimmed)
        log(.tagAdded, assetID: assetID)
        save()
    }

    func removeTag(_ name: String, from assetID: String) {
        guard let record = record(for: assetID) else { return }
        record.tagNames.removeAll { $0 == name }
        log(.tagRemoved, assetID: assetID)
        save()
    }

    func registerTag(_ name: String) {
        var descriptor = FetchDescriptor<TagRecord>(predicate: #Predicate { $0.name == name })
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) == nil {
            context.insert(TagRecord(name: name))
        }
    }

    func allTags() -> [TagRecord] {
        let descriptor = FetchDescriptor<TagRecord>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Snapshots

    func latestSnapshot() -> LibrarySnapshotRecord? {
        var descriptor = FetchDescriptor<LibrarySnapshotRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func saveSnapshot(assetIDs: [String], favoriteIDs: [String]) {
        context.insert(LibrarySnapshotRecord(assetIDs: assetIDs, favoriteIDs: favoriteIDs))
        trimSnapshots(keeping: 30)
        save()
    }

    /// Snapshots are cheap but not free; a month of them is plenty for trends.
    private func trimSnapshots(keeping limit: Int) {
        let descriptor = FetchDescriptor<LibrarySnapshotRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        guard let all = try? context.fetch(descriptor), all.count > limit else { return }
        for stale in all.dropFirst(limit) {
            context.delete(stale)
        }
    }

    // MARK: Change journal

    func log(_ kind: ChangeEventKind, assetID: String?) {
        guard keepsChangeLog else { return }
        context.insert(ChangeEventRecord(kind: kind, assetID: assetID))
    }

    func recentEvents(limit: Int = 200) -> [ChangeEventRecord] {
        var descriptor = FetchDescriptor<ChangeEventRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func clearChangeLog() {
        try? context.delete(model: ChangeEventRecord.self)
        save()
    }

    // MARK: Reset

    /// The "start over" switch in Settings. Media is untouched — this is only our layer.
    func resetEverything() {
        try? context.delete(model: AssetRecord.self)
        try? context.delete(model: TagRecord.self)
        try? context.delete(model: AssetNote.self)
        try? context.delete(model: VideoBookmark.self)
        try? context.delete(model: SmartCollectionRecord.self)
        try? context.delete(model: QueueRecord.self)
        try? context.delete(model: LibrarySnapshotRecord.self)
        try? context.delete(model: ChangeEventRecord.self)
        save()
    }

    func save() {
        try? context.save()
    }
}
