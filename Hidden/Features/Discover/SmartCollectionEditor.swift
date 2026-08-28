import SwiftUI

/// Define a dynamic collection: a name, a rule set (the same composable filter the Library
/// uses), and a sort. The rules are stored as JSON, and the collection updates itself —
/// membership is computed live, never frozen.
struct SmartCollectionEditor: View {
    @Environment(\.app) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var filter: LibraryFilter = .none
    @State private var sort: LibrarySort = .recentlyObserved
    @State private var showsRules = false

    private var matchCount: Int {
        LibraryQuery.run(app.model.assets, filter: filter, sort: sort,
                         meta: app.model.metaByID).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name"), text: $name)
                }

                Section {
                    Button {
                        showsRules = true
                    } label: {
                        HStack {
                            Text("Rules")
                                .foregroundStyle(Palette.textPrimary)
                            Spacer()
                            Text(filter.isActive
                                 ? String(localized: "\(filter.activeCount.formatted()) active")
                                 : String(localized: "Everything"))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Picker(String(localized: "Sort"), selection: $sort) {
                        ForEach(LibrarySort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } footer: {
                    Text("Currently matches \(matchCount.formatted()) items. Membership updates automatically as your library changes.")
                }
            }
            .navigationTitle(String(localized: "New Smart Collection"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        app.store.addSmartCollection(name: name, filter: filter, sort: sort)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showsRules) {
                FilterSheet(filter: $filter)
            }
        }
    }
}
