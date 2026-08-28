import SwiftUI

/// The opaque cover shown whenever the scene is not active, and the lock screen when the
/// app's own lock is engaged. Deliberately quiet: an icon, a word, and — when locked and in
/// the foreground — one unlock button. Nothing about the library shows through.
struct PrivacyCoverView: View {
    /// True when the lock screen should offer the unlock button (foreground and locked, as
    /// opposed to merely covered for the app switcher).
    var showsUnlock: Bool

    @Environment(\.app) private var app
    @State private var didAutoPrompt = false

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            VStack(spacing: Space.l) {
                Image(systemName: "lock.fill")
                    .font(Typo.glyph(44, .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)

                Text("Hidden")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)

                if showsUnlock {
                    Button {
                        Task { await app.lock.unlock() }
                    } label: {
                        Label(String(localized: "Unlock"), systemImage: "faceid")
                            .font(Typo.control)
                            .padding(.horizontal, Space.xl)
                            .frame(minHeight: Hit.min)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Space.l)

                    if let error = app.lock.lastError {
                        Text(error)
                            .font(Typo.meta)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Space.section)
                    }
                }
            }
        }
        .task(id: showsUnlock) {
            // Offer Face ID once, immediately, the way a banking app does — but only once,
            // so a cancelled prompt leaves a button rather than a loop of prompts.
            if showsUnlock && !didAutoPrompt {
                didAutoPrompt = true
                await app.lock.unlock()
            }
        }
    }
}

#Preview {
    PrivacyCoverView(showsUnlock: true)
}
