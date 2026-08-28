import SwiftUI

/// Composable filters over the current result set. Everything here ANDs together, which the
/// header states so the mental model is never a guess.
struct FilterSheet: View {
    @Binding var filter: LibraryFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Kind")) {
                    kindToggle(String(localized: "Photos"), .photo)
                    kindToggle(String(localized: "Videos"), .video)
                    Toggle(String(localized: "Live Photos"), isOn: $filter.onlyLivePhotos)
                    Toggle(String(localized: "Screenshots"), isOn: $filter.onlyScreenshots)
                    Toggle(String(localized: "Panoramas"), isOn: $filter.onlyPanoramas)
                    Toggle(String(localized: "Slow Motion"), isOn: $filter.onlySlowMotion)
                    Toggle(String(localized: "Time Lapse"), isOn: $filter.onlyTimeLapse)
                }

                Section(String(localized: "State")) {
                    Toggle(String(localized: "Favorites"), isOn: $filter.onlyFavorites)
                    Toggle(String(localized: "App Favorites"), isOn: $filter.onlyAppFavorites)
                    Toggle(String(localized: "Pinned"), isOn: $filter.onlyPinned)
                    Toggle(String(localized: "Rated"), isOn: $filter.onlyRated)
                    Toggle(String(localized: "Tagged"), isOn: $filter.onlyTagged)
                    Picker(String(localized: "Viewed"), selection: viewedBinding) {
                        Text(String(localized: "Any")).tag(0)
                        Text(String(localized: "Viewed")).tag(1)
                        Text(String(localized: "Never Viewed")).tag(2)
                    }
                    Picker(String(localized: "Review"), selection: reviewBinding) {
                        Text(String(localized: "Any")).tag(0)
                        Text(String(localized: "Reviewed")).tag(1)
                        Text(String(localized: "Unreviewed")).tag(2)
                        Text(String(localized: "Review Later")).tag(3)
                    }
                }

                Section(String(localized: "Shape")) {
                    orientationToggle(String(localized: "Portrait"), .portrait)
                    orientationToggle(String(localized: "Landscape"), .landscape)
                    orientationToggle(String(localized: "Square"), .square)
                    Picker(String(localized: "Location"), selection: locationBinding) {
                        Text(String(localized: "Any")).tag(0)
                        Text(String(localized: "With Location")).tag(1)
                        Text(String(localized: "Without Location")).tag(2)
                    }
                }

                Section(String(localized: "Video Duration")) {
                    Picker(String(localized: "Longer Than"), selection: minDurationBinding) {
                        Text(String(localized: "Any")).tag(0)
                        Text(String(localized: "30 Seconds")).tag(30)
                        Text(String(localized: "2 Minutes")).tag(120)
                        Text(String(localized: "5 Minutes")).tag(300)
                        Text(String(localized: "15 Minutes")).tag(900)
                    }
                    Toggle(String(localized: "Never Finished"), isOn: $filter.neverFinished)
                }

                Section {
                    Button(String(localized: "Clear All Filters"), role: .destructive) {
                        filter = .none
                    }
                    .disabled(!filter.isActive)
                }
            }
            .navigationTitle(String(localized: "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }

    // MARK: Bindings

    private func kindToggle(_ title: String, _ kind: MediaKind) -> some View {
        Toggle(title, isOn: Binding(
            get: { filter.kinds.contains(kind) },
            set: { on in
                if on { filter.kinds.insert(kind) } else { filter.kinds.remove(kind) }
            }))
    }

    private func orientationToggle(_ title: String, _ orientation: AssetOrientation) -> some View {
        Toggle(title, isOn: Binding(
            get: { filter.orientations.contains(orientation) },
            set: { on in
                if on { filter.orientations.insert(orientation) }
                else { filter.orientations.remove(orientation) }
            }))
    }

    private var viewedBinding: Binding<Int> {
        Binding(
            get: {
                switch filter.viewed {
                case nil:   return 0
                case true?: return 1
                case false?: return 2
                }
            },
            set: { filter.viewed = [nil, true, false][$0] })
    }

    private var reviewBinding: Binding<Int> {
        Binding(
            get: {
                if filter.reviewStates == [.reviewed] { return 1 }
                if filter.reviewStates == [.unreviewed] { return 2 }
                if filter.reviewStates == [.reviewLater] { return 3 }
                return 0
            },
            set: {
                switch $0 {
                case 1: filter.reviewStates = [.reviewed]
                case 2: filter.reviewStates = [.unreviewed]
                case 3: filter.reviewStates = [.reviewLater]
                default: filter.reviewStates = []
                }
            })
    }

    private var locationBinding: Binding<Int> {
        Binding(
            get: {
                switch filter.hasLocation {
                case nil:    return 0
                case true?:  return 1
                case false?: return 2
                }
            },
            set: { filter.hasLocation = [nil, true, false][$0] })
    }

    private var minDurationBinding: Binding<Int> {
        Binding(
            get: { Int(filter.minDuration ?? 0) },
            set: { filter.minDuration = $0 == 0 ? nil : TimeInterval($0) })
    }
}
