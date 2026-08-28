import SwiftUI

/// Attach and detach private tags. Tags belong to this app's metadata layer only; nothing
/// in Apple Photos changes.
struct TagEditorView: View {
    let assetID: String

    @Environment(\.app) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    private var attached: Set<String> { app.model.meta(for: assetID).tagNames }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "New Tag")) {
                    HStack {
                        TextField(String(localized: "Tag name"), text: $newTag)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addNew)
                        Button(String(localized: "Add"), action: addNew)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                let all = app.store.allTags()
                if !all.isEmpty {
                    Section(String(localized: "Tags")) {
                        ForEach(all, id: \.name) { tag in
                            Button {
                                toggle(tag.name)
                            } label: {
                                HStack {
                                    Text(tag.name)
                                        .foregroundStyle(Palette.textPrimary)
                                    Spacer()
                                    if attached.contains(tag.name) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Palette.accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Tags"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }

    private func addNew() {
        let name = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        app.model.store.addTag(name, to: assetID)
        app.model.refreshMeta(for: assetID)
        newTag = ""
    }

    private func toggle(_ name: String) {
        if attached.contains(name) {
            app.model.store.removeTag(name, from: assetID)
        } else {
            app.model.store.addTag(name, to: assetID)
        }
        app.model.refreshMeta(for: assetID)
    }
}

/// A private note on one asset.
struct NoteEditorView: View {
    let assetID: String

    @Environment(\.app) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(Typo.body)
                .padding(Space.m)
                .navigationTitle(String(localized: "Note"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save")) {
                            app.store.setNote(text, for: assetID)
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    guard !didLoad else { return }
                    didLoad = true
                    text = app.store.note(for: assetID)?.text ?? ""
                }
        }
    }
}

/// The 1–5 rating control, as a row of stars.
struct RatingPicker: View {
    let assetID: String

    @Environment(\.app) private var app

    var body: some View {
        let current = app.model.meta(for: assetID).rating
        HStack(spacing: Space.s) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    // Tapping the current rating clears it.
                    app.model.setRating(assetID, star == current ? 0 : star)
                } label: {
                    Image(systemName: star <= current ? "star.fill" : "star")
                        .font(Typo.glyph(22, .regular))
                        .foregroundStyle(star <= current ? Color.yellow : Palette.textTertiary)
                        .frame(width: Hit.min, height: Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(star) stars"))
                .accessibilityAddTraits(star <= current ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
