import SwiftUI

/// One voice: SF Pro, on Apple's own type scale, scaled by Dynamic Type.
///
/// Every font here is a text style rather than a fixed point size, so the whole app answers
/// the reader's Dynamic Type setting without any font metrics arithmetic. The named constants
/// map onto the rungs Apple's scale already has.
enum Typo {
    static var hero: Font         { .largeTitle.weight(.semibold) }   // 34
    static var screenTitle: Font  { .title.weight(.semibold) }        // 28
    static var sectionTitle: Font { .title2.weight(.semibold) }       // 22
    static var body: Font         { .body }                           // 17

    static let control       = Font.callout.weight(.medium)      // 16
    static let label         = Font.subheadline                  // 15
    static let meta          = Font.footnote                     // 13
    static let overline      = Font.caption.weight(.semibold)    // 12
    static let tabLabel      = Font.caption2.weight(.medium)     // 11

    /// SF Pro at a one-off size, landed on the nearest rung of the scale so it still grows
    /// with the reader.
    static func scaled(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(style(nearest: size)).weight(weight)
    }

    /// A symbol drawn inside a control whose size is fixed by its own geometry — a 46-point
    /// round glass button, a badge in the corner of a thumbnail. These deliberately do not
    /// scale: a glyph that grows past the circle it is centred in becomes clipped, not more
    /// legible. The control's accessibility label is what serves a reader who needs more.
    static func glyph(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    /// The rung of Apple's type scale nearest a point size.
    private static func style(nearest size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5:  return .caption2      // 11
        case ..<12.5:  return .caption       // 12
        case ..<14:    return .footnote      // 13
        case ..<15.5:  return .subheadline   // 15
        case ..<16.5:  return .callout       // 16
        case ..<18.5:  return .body          // 17
        case ..<21:    return .title3        // 20
        case ..<25:    return .title2        // 22
        case ..<31:    return .title         // 28
        default:       return .largeTitle    // 34
        }
    }
}

extension View {
    /// Small uppercase overline used above section headlines.
    func overlineStyle() -> some View {
        self.font(Typo.overline)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Palette.textSecondary)
    }

    /// A ceiling on how far text inside a piece of fixed chrome is allowed to grow. Used only
    /// where the container genuinely cannot grow with it; content is never capped.
    func chromeTypeSize(_ ceiling: DynamicTypeSize = .accessibility1) -> some View {
        self.dynamicTypeSize(...ceiling)
    }
}

/// The spacing scale. Anything not on this scale is a mistake, not a decision.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let gutter: CGFloat = 20
    static let xl: CGFloat = 28
    static let section: CGFloat = 40
}

/// Corner radii, fixed per surface kind so related elements stay visually related.
enum Radius {
    static let hero: CGFloat = 28
    static let card: CGFloat = 22
    /// A small floating glass panel: chrome laid over content rather than content itself.
    static let panel: CGFloat = 18
    static let tile: CGFloat = 14
    static let thumb: CGFloat = 10
    /// One photograph in a dense grid — nearly square on purpose.
    static let gridTile: CGFloat = 6
}

/// The smallest square iOS will vouch for as something a finger can reliably hit.
enum Hit {
    static let min: CGFloat = 44
}
