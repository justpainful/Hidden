#if DEBUG
import SwiftData
import SwiftUI

/// Developer-only plumbing view, compiled out of release builds entirely. Counts and states
/// — never media, never note text, never tag names.
struct DiagnosticsView: View {
    @Environment(\.app) private var app

    var body: some View {
        List {
            Section("Photo library") {
                row("Access state", String(describing: app.model.accessState))
                row("Accessible hidden", app.model.assets.count.formatted())
                row("Images", app.model.assets.filter { !$0.isVideo }.count.formatted())
                row("Videos", app.model.assets.filter(\.isVideo).count.formatted())
                row("Change generation", app.libraryService.changeGeneration.formatted())
                row("Cloud-only recorded", app.media.cloudOnlyIdentifiers.count.formatted())
                row("Mock mode", LaunchOptions.useMockLibrary ? "yes" : "no")
            }

            Section("Store") {
                row("Asset records", count(AssetRecord.self))
                row("Tags", count(TagRecord.self))
                row("Notes", count(AssetNote.self))
                row("Bookmarks", count(VideoBookmark.self))
                row("Smart collections", count(SmartCollectionRecord.self))
                row("Queues", count(QueueRecord.self))
                row("Snapshots", count(LibrarySnapshotRecord.self))
                row("Journal events", count(ChangeEventRecord.self))
            }

            Section("Refresh") {
                row("Last refresh", app.model.lastRefreshAt?.formatted(
                    date: .abbreviated, time: .standard) ?? "never")
                row("Last snapshot", app.store.latestSnapshot()?.timestamp.formatted(
                    date: .abbreviated, time: .standard) ?? "none")
                row("Digest baseline", app.model.digest.isBaseline ? "yes" : "no")
                row("Newly observed", app.model.digest.newlyObserved.count.formatted())
                row("No longer present", app.model.digest.noLongerPresent.count.formatted())
            }

            Section("Build") {
                row("Version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                row("Build", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func count<T: PersistentModel>(_ type: T.Type) -> String {
        ((try? app.store.context.fetchCount(FetchDescriptor<T>())) ?? 0).formatted()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Palette.textSecondary)
        }
        .font(Typo.meta.monospacedDigit())
    }
}
#endif
