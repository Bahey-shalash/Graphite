import SwiftUI
import GraphiteCore

/// The graph's colors in light or dark appearance, chosen against the accent: notes are a
/// quiet gray, attachments amber and tags green, each standing out from the page by at least
/// the contrast WCAG asks of shapes, and the accent keeps the open note and the focused
/// links to itself. When the accent's hue is near the tags' green (a green or teal accent)
/// tags turn purple, and when it is near the attachments' amber (an amber, orange or red
/// accent) attachments turn blue, so the open note never looks like a tag or an attachment.
struct GraphPalette: Equatable {
    enum Appearance: Equatable {
        case light, dark
    }

    let note: ThemeColor
    let attachment: ThemeColor
    let tag: ThemeColor
    /// The outline of a link target without a file, which is not a note.
    let unresolved: ThemeColor
    let link: ThemeColor
    /// A link while another node's links stand out.
    let dimmedLink: ThemeColor

    /// An accent within this many degrees of a kind's hue gives the kind its other color.
    static let accentHueClearanceDegrees = 45.0
    /// An accent less saturated than this is a gray, which no kind's color can be mistaken for.
    static let grayAccentSaturation = 0.2

    private static let tagGreen = (light: ThemeColor(red: 0.18, green: 0.55, blue: 0.33), dark: ThemeColor(red: 0.30, green: 0.75, blue: 0.48))
    private static let tagPurple = (light: ThemeColor(red: 0.52, green: 0.36, blue: 0.82), dark: ThemeColor(red: 0.70, green: 0.58, blue: 0.98))
    private static let attachmentAmber = (light: ThemeColor(red: 0.70, green: 0.45, blue: 0.04), dark: ThemeColor(red: 0.90, green: 0.66, blue: 0.22))
    private static let attachmentBlue = (light: ThemeColor(red: 0.10, green: 0.50, blue: 0.66), dark: ThemeColor(red: 0.35, green: 0.75, blue: 0.90))

    init(appearance: Appearance, accent: ThemeColor) {
        let isDark = appearance == .dark
        note = isDark ? ThemeColor(red: 0.60, green: 0.60, blue: 0.63) : ThemeColor(red: 0.47, green: 0.47, blue: 0.50)
        unresolved = isDark ? ThemeColor(red: 0.50, green: 0.50, blue: 0.53) : ThemeColor(red: 0.52, green: 0.52, blue: 0.55)
        link = isDark ? ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.2) : ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.18)
        dimmedLink = isDark ? ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.08) : ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.07)
        let green = isDark ? Self.tagGreen.dark : Self.tagGreen.light
        let amber = isDark ? Self.attachmentAmber.dark : Self.attachmentAmber.light
        tag = Self.isNear(accent, green) ? (isDark ? Self.tagPurple.dark : Self.tagPurple.light) : green
        attachment = Self.isNear(accent, amber) ? (isDark ? Self.attachmentBlue.dark : Self.attachmentBlue.light) : amber
    }

    /// The color of a node of this kind that no group colors.
    func color(of kind: GraphNode.Kind) -> ThemeColor {
        switch kind {
        case .note: note
        case .attachment: attachment
        case .tag: tag
        case .unresolved: unresolved
        }
    }

    /// Whether nodes of this kind are drawn as a dashed outline rather than filled: a link
    /// target without a file is not a note.
    static func isDrawnHollow(_ kind: GraphNode.Kind) -> Bool {
        switch kind {
        case .unresolved: true
        case .note, .attachment, .tag: false
        }
    }

    /// The hue of a color, in degrees from 0 to 360; nil for a gray.
    static func hueDegrees(of color: ThemeColor) -> Double? {
        let largest = max(color.red, color.green, color.blue), smallest = min(color.red, color.green, color.blue)
        let range = largest - smallest
        guard largest > 0, range / largest >= grayAccentSaturation else { return nil }
        let sector: Double
        switch largest {
        case color.red: sector = (color.green - color.blue) / range
        case color.green: sector = (color.blue - color.red) / range + 2
        default: sector = (color.red - color.green) / range + 4
        }
        let degrees = sector * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// The distance between two hues around the color wheel, from 0 to 180 degrees.
    static func hueDistanceDegrees(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private static func isNear(_ accent: ThemeColor, _ kindColor: ThemeColor) -> Bool {
        guard let accentHue = hueDegrees(of: accent), let kindHue = hueDegrees(of: kindColor) else { return false }
        return hueDistanceDegrees(accentHue, kindHue) < accentHueClearanceDegrees
    }
}
