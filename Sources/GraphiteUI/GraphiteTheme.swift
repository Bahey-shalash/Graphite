import SwiftUI
import GraphiteCore

public enum GraphiteTheme {
    /// Ink blue, the color of the blue pen preset (RGB 45, 93, 161): calm on paper white, and
    /// the app's one accent. In dark appearance it is lightened to stay readable
    /// (`AccentLegibility`).
    static let defaultAccentHex = "#2d5da1"

    /// The accents offered in Appearance. Any other color can be picked as well.
    static let accentPresets: [(name: String, hex: String)] = [
        ("Ink Blue", "#2d5da1"), ("Graphite", "#6e6e73"), ("Teal", "#1f8f8a"), ("Green", "#2f8f5b"),
        ("Amber", "#b8860b"), ("Orange", "#d2691e"), ("Red", "#c4312b"), ("Pink", "#c2497f"),
        ("Bright Blue", "#3068e8"), ("Purple (Obsidian)", "#8a6cef"),
    ]
}

/// The quiet chrome every workspace shares, after Obsidian's Minimal theme: bars take the
/// page's own background and are set off from it by a hairline, icons stay muted until
/// they are in use, and the tab, tool or row in use is marked by a faint fill and full
/// strength text rather than by a colored block.
enum GraphiteChrome {
    /// The height of the tab bar and of the rows below the navigation bar.
    static let barHeight: CGFloat = 40
    /// The corner radius of a tab, a tool or a row in use.
    static let cornerRadius: CGFloat = 8
    /// The fill behind the tab, tool or row in use.
    static let selectedFill = Color.primary.opacity(0.07)
    /// The page's background, which the bars share so a document and its controls read
    /// as one surface.
    #if canImport(UIKit)
    static let barBackground = Color(uiColor: .systemBackground)
    #else
    static let barBackground = Color(nsColor: .textBackgroundColor)
    #endif
}

/// A line one pixel thick and lighter than `Divider`, between a bar and the page.
struct Hairline: View {
    var axis: Axis = .horizontal
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let thickness = 1 / max(displayScale, 1)
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: axis == .vertical ? thickness : nil, height: axis == .horizontal ? thickness : nil)
            .accessibilityHidden(true)
    }
}

extension PlatformColor {
    /// An accent from its `#rrggbb` value: as chosen in light appearance, lightened just
    /// enough to read in dark appearance.
    static func graphiteAccent(hex: String) -> PlatformColor? {
        guard let chosenColor = PlatformColor(graphiteHex: hex) else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        guard chosenColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return chosenColor }
        #else
        guard let components = chosenColor.usingColorSpace(.sRGB) else { return chosenColor }
        red = components.redComponent; green = components.greenComponent; blue = components.blueComponent; alpha = components.alphaComponent
        #endif
        let lightened = AccentLegibility.lightenedForDarkBackground(red: red, green: green, blue: blue)
        #if canImport(UIKit)
        let darkAppearanceColor = UIColor(red: lightened.red, green: lightened.green, blue: lightened.blue, alpha: alpha)
        return UIColor { traitCollection in traitCollection.userInterfaceStyle == .dark ? darkAppearanceColor : chosenColor }
        #else
        let darkAppearanceColor = NSColor(srgbRed: lightened.red, green: lightened.green, blue: lightened.blue, alpha: alpha)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkAppearanceColor : chosenColor
        }
        #endif
    }
}

extension Color {
    /// See `PlatformColor.graphiteAccent(hex:)`.
    static func graphiteAccent(hex: String) -> Color? {
        PlatformColor.graphiteAccent(hex: hex).map { accent in Color(accent) }
    }
}

extension EnvironmentValues {
    /// The accent chosen in Appearance. Controls get it through `.tint`; this carries it
    /// where a concrete color is needed, such as link text and map markers.
    @Entry var accent: Color = Color(graphiteHex: GraphiteTheme.defaultAccentHex) ?? .blue
}

extension Color {
    /// `#rrggbb` in sRGB, for storing a color picked in settings: the accent and the
    /// Colors palette.
    var sRGBHex: String? {
        #if canImport(UIKit)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #else
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = components.redComponent, green = components.greenComponent, blue = components.blueComponent
        #endif
        func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }
}
