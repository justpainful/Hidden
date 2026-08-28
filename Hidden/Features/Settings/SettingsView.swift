import SwiftUI

struct SettingsView: View {
    @Environment(\.app) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var confirmClearHistory = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                privacySection
                playbackSection
                librarySection
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
