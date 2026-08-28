import SwiftUI

/// First launch: what the app is, what it will and will not do, and the one button that
/// asks for Photos access. The system prompt is only shown after the user chooses to see it.
struct WelcomeView: View {
    @Environment(\.app) private var app
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Space.l) {
                Image(systemName: "photo.stack")
                    .font(Typo.glyph(52, .medium))
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)

                Text("Hidden")
                    .font(Typo.hero)

                Text("Browse, rediscover and organize the media in your Hidden album — with your library staying exactly where it is, in Apple Photos.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.section)
            }

            Spacer()

            VStack(alignment: .leading, spacing: Space.l) {
                promiseRow(symbol: "iphone",
                           title: String(localized: "On this device"),
                           detail: String(localized: "Nothing is uploaded, tracked or analyzed anywhere else."))
                promiseRow(symbol: "photo.on.rectangle",
                           title: String(localized: "Photos stays the source of truth"),
                           detail: String(localized: "Hidden never duplicates your originals; it only keeps its own small notes."))
                promiseRow(symbol: "faceid",
                           title: String(localized: "Your own lock"),
                           detail: String(localized: "Lock the app with Face ID, separately from anything Apple protects."))
            }
            .padding(.horizontal, Space.section)

            Spacer()

            Button {
                isRequesting = true
                Task {
                    await app.libraryService.requestAccess()
                    await app.model.refresh()
                    isRequesting = false
                }
            } label: {
                Text("Allow Photos Access")
                    .font(Typo.control)
                    .frame(maxWidth: .infinity, minHeight: Hit.min)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
            .padding(.horizontal, Space.section)
            .padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
    }

    private func promiseRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.l) {
            Image(systemName: symbol)
                .font(Typo.glyph(22, .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(Typo.control)
                Text(detail)
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

/// Photos access was denied or is restricted. Both decisions were made outside the app and
/// can only be undone outside it, so the honest control is the one that goes there.
struct AccessDeniedView: View {
    var body: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(Typo.glyph(44, .medium))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)

            Text("No Photos Access")
                .font(Typo.sectionTitle)

            Text("Hidden needs access to your Photos library to show your hidden media. You can allow it in Settings.")
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.section)

            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Text("Open Settings")
                        .font(Typo.control)
                        .padding(.horizontal, Space.xl)
                        .frame(minHeight: Hit.min)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }
}

#Preview("Welcome") {
    WelcomeView()
}

#Preview("Denied") {
    AccessDeniedView()
}
