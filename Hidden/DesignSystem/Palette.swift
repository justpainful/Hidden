import SwiftUI

/// The chrome is the system's, not ours.
///
/// Every value here maps to a UIKit system colour, which is what makes the app read as part
/// of iOS rather than as a product with a brand palette: pure white on white, pure black on
/// black, the same separators and label greys Settings and Photos use, and the system tint
/// for anything interactive. The app's colour comes from the user's media and from nowhere
/// else.
enum Palette {
    static let canvas      = Color(uiColor: .systemBackground)
    /// The ground for card-based screens. Cards drawn in `surface` are only visible against
    /// *this*; on `canvas` they disappear in light mode (white on white).
    static let groupedCanvas = Color(uiColor: .systemGroupedBackground)
    static let surface     = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceSunk = Color(uiColor: .secondarySystemFill)

    static let textPrimary   = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)

    /// The quietest tone in the app, and the one that has to give way first: under Increase
    /// Contrast it becomes `secondaryLabel` everywhere at once, glyphs included.
    static let textTertiary = Color(uiColor: UIColor { traits in
        traits.accessibilityContrast == .high ? .secondaryLabel : .tertiaryLabel
    })

    /// The system tint. Selected tabs, links, toggles — the same blue every stock app uses.
    static let accent = Color.accentColor

    /// `separator` is a translucent hairline that all but disappears over a busy background;
    /// `opaqueSeparator` is what the system substitutes when a reader has asked for the
    /// structure of a screen to be visible rather than implied.
    static let hairline = Color(uiColor: UIColor { traits in
        traits.accessibilityContrast == .high ? .opaqueSeparator : .separator
    })

    /// Scrim over photography so overlaid type stays legible without dimming the image.
    static let photoScrim = Color.black.opacity(0.34)

    /// The heavier scrim a small label needs when it sits directly on a photograph — the
    /// duration badge on a video thumbnail.
    static let labelScrim = Color.black.opacity(0.55)
}

extension Color {
    /// Dynamic colour from two hex literals, for the few places that need a specific value
    /// the system does not provide.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue:  CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
