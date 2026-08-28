import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.app) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var confirmClearHistory = false
    @State private var confirmReset = false
    @State private var exportURL: URL?
    @State private var exportIncludesHistory = false
    @State private var showsImporter = false
    @State private var transferMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                privacySection
                playbackSection
                librarySection
                searchSection
                backupSection
                dataSection
                aboutSection
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }

    // MARK: Sections

    private var privacySection: some View {
        Section {
            Toggle(String(localized: "Lock with Face ID"), isOn: Binding(
                get: { app.lock.isEnabled },
                set: { app.lock.isEnabled = $0 }))

            if app.lock.isEnabled {
                Picker(String(localized: "Require Again"), selection: Binding(
                    get: { app.lock.timeout },
                    set: { app.lock.timeout = $0 })) {
                    ForEach(LockTimeout.allCases) { timeout in
                        Text(timeout.title).tag(timeout)
                    }
                }
                Button(String(localized: "Lock Now")) {
                    app.lock.lock()
                }
            }

            Toggle(String(localized: "Incognito"), isOn: Binding(
                get: { app.settings.incognito },
                set: { app.settings.incognito = $0; app.applySettings() }))
            Toggle(String(localized: "Blur Thumbnails"), isOn: Binding(
                get: { app.settings.blurThumbnails },
                set: { app.settings.blurThumbnails = $0 }))
            Toggle(String(localized: "Cover While Screen Recording"), isOn: Binding(
                get: { app.settings.obscureWhileCaptured },
                set: { app.settings.obscureWhileCaptured = $0 }))
            Toggle(String(localized: "Read Only Mode"), isOn: Binding(
                get: { app.settings.readOnlyMode },
                set: { app.settings.readOnlyMode = $0 }))
            Toggle(String(localized: "No Delete Mode"), isOn: Binding(
                get: { app.settings.noDeleteMode },
                set: { app.settings.noDeleteMode = $0 }))
        } header: {
            Text("Privacy")
        } footer: {
            Text("Incognito stops the app recording any viewing history. Read Only stops it changing anything in Apple Photos.")
        }
    }

    private var playbackSection: some View {
        Section(String(localized: "Playback")) {
            Picker(String(localized: "Photo Duration"), selection: Binding(
                get: { app.settings.photoDuration },
                set: { app.settings.photoDuration = $0 })) {
                Text(String(localized: "2 Seconds")).tag(TimeInterval(2))
                Text(String(localized: "3 Seconds")).tag(TimeInterval(3))
                Text(String(localized: "5 Seconds")).tag(TimeInterval(5))
                Text(String(localized: "10 Seconds")).tag(TimeInterval(10))
            }
            Toggle(String(localized: "Mute Videos by Default"), isOn: Binding(
                get: { app.settings.muteByDefault },
                set: { app.settings.muteByDefault = $0 }))
            Toggle(String(localized: "Autoplay Next"), isOn: Binding(
                get: { app.settings.autoplayNext },
                set: { app.settings.autoplayNext = $0 }))
        }
    }

    private var librarySection: some View {
        Section(String(localized: "Library")) {
            Picker(String(localized: "Default Sort"), selection: Binding(
                get: { app.settings.defaultSort },
                set: { app.settings.defaultSort = $0 })) {
                ForEach(LibrarySort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            Picker(String(localized: "Appearance"), selection: Binding(
                get: { app.settings.appearance },
                set: { app.settings.appearance = $0 })) {
                ForEach(AppearanceChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            Picker(String(localized: "Open On"), selection: Binding(
                get: { AppTab(rawValue: app.settings.launchTabRaw) ?? .inbox },
                set: { app.settings.launchTabRaw = $0.rawValue })) {
                ForEach(AppTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
        }
    }

    private var searchSection: some View {
        Section {
            Toggle(String(localized: "Find Text in Photos"), isOn: Binding(
                get: { app.settings.ocrEnabled },
                set: { enabled in
                    app.settings.ocrEnabled = enabled
                    if enabled {
                        app.textIndex.start()
                    } else {
                        app.textIndex.pause()
                    }
                }))

            if app.settings.ocrEnabled {
                LabeledContent(String(localized: "Indexed"),
                               value: "\(app.textIndex.indexedCount.formatted()) / \((app.textIndex.indexedCount + app.textIndex.pendingCount).formatted())")

                if app.textIndex.isRunning {
                    Button(String(localized: "Pause Indexing")) {
                        app.textIndex.pause()
                    }
                } else if app.textIndex.pendingCount > 0 {
                    Button(String(localized: "Resume Indexing")) {
                        app.textIndex.start()
                    }
                }

                if let error = app.textIndex.lastError {
                    Text(error)
                        .font(Typo.meta)
                        .foregroundStyle(Palette.textSecondary)
                }

                Button(String(localized: "Clear Text Index"), role: .destructive) {
                    app.textIndex.clearIndex()
                }
            }
        } header: {
            Text("Search")
        } footer: {
            Text("Recognizes text inside photos on this device so search can find it. Nothing is uploaded; iCloud originals are never downloaded for indexing.")
        }
        .onAppear { app.textIndex.refreshCounts() }
    }

    private var backupSection: some View {
        Section {
            Toggle(String(localized: "Include Viewing History"), isOn: $exportIncludesHistory)
                .onChange(of: exportIncludesHistory) { _, _ in exportURL = nil }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label(String(localized: "Share Backup File"), systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    prepareExport()
                } label: {
                    Label(String(localized: "Prepare Metadata Backup"), systemImage: "archivebox")
                }
            }

            Button {
                showsImporter = true
            } label: {
                Label(String(localized: "Import Backup"), systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("A backup carries tags, ratings, notes, collections and observation dates — never photos or videos. Identifiers that no longer resolve import as dormant records.")
        }
        .fileImporter(isPresented: $showsImporter,
                      allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importBackup(from: url)
            case .failure(let error):
                transferMessage = error.localizedDescription
            }
        }
        .alert(String(localized: "Backup"),
               isPresented: Binding(get: { transferMessage != nil },
                                    set: { if !$0 { transferMessage = nil } })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(transferMessage ?? "")
        }
    }

    private func prepareExport() {
        do {
            let data = try MetadataTransfer.export(store: app.store,
                                                   includeHistory: exportIncludesHistory)
            let stamp = Date.now.formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Hidden-Metadata-\(stamp).json")
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            transferMessage = error.localizedDescription
        }
    }

    private func importBackup(from url: URL) {
        do {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let count = try MetadataTransfer.importData(data, into: app.store)
            transferMessage = String(localized: "Restored metadata for \(count.formatted()) items.")
            Task { await app.model.refresh() }
        } catch {
            transferMessage = error.localizedDescription
        }
    }

    private var dataSection: some View {
        Section {
            Button(String(localized: "Clear Viewing History"), role: .destructive) {
                confirmClearHistory = true
            }
            .confirmationDialog(String(localized: "Clear all viewing history? Tags, notes and favorites stay."),
                                isPresented: $confirmClearHistory,
                                titleVisibility: .visible) {
                Button(String(localized: "Clear History"), role: .destructive) {
                    app.store.clearViewingHistory()
                    Task { await app.model.refresh() }
                }
            }

            Button(String(localized: "Clear Image Cache")) {
                app.media.clearMemoryCache()
            }

            Button(String(localized: "Reset App Data"), role: .destructive) {
                confirmReset = true
            }
            .confirmationDialog(String(localized: "Reset everything Hidden knows — tags, history, collections, queues? Your photos and videos in Apple Photos are not touched."),
                                isPresented: $confirmReset,
                                titleVisibility: .visible) {
                Button(String(localized: "Reset Everything"), role: .destructive) {
                    app.store.resetEverything()
                    ShuffleSessionStore.clear()
                    Task { await app.model.refresh() }
                }
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Everything Hidden stores is a small local metadata layer. Your media lives in Apple Photos and is never duplicated or uploaded.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(String(localized: "Version"), value: appVersion)
            NavigationLink(String(localized: "About the Hidden Album")) {
                AboutLimitationView()
            }
            #if DEBUG
            NavigationLink("Diagnostics") {
                DiagnosticsView()
            }
            #endif
        } header: {
            Text("About")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// The honest page: what this app can and cannot do about Apple's own Hidden protection.
struct AboutLimitationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Apple protects the system Hidden album independently of any app.")
                    .font(Typo.control)

                Text("When \"Use Face ID\" is enabled for the Hidden album (Settings → Apps → Photos), iOS does not provide those hidden photos and videos to third-party apps at all — including this one. There is no supported way for an app to authenticate and unlock them.")
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)

                Text("Hidden's own Face ID lock protects this app. It is independent of Apple's protection and cannot unlock Apple's Hidden album.")
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)

                Text("If your Hidden album appears empty here, either nothing is hidden, or the system protection is on. Turning that protection off in Photos settings makes hidden media visible to this app.")
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)

                Divider()

                Text("What Hidden stores")
                    .font(Typo.control)

                Text("Asset identifiers, tags, notes, ratings, viewing history, playback positions, collection rules and observation dates — a small local database. Never your photos or videos, and never anything sent off this device.")
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(Space.gutter)
        }
        .navigationTitle(Text("About"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
