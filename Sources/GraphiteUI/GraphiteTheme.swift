import SwiftUI

public enum GraphiteTheme {
    /// Graphite's blue (RGB 48, 104, 232).
    static let defaultAccentHex = "#3068e8"

    /// The accents offered in Appearance. Any other color can be picked as well.
    static let accentPresets: [(name: String, hex: String)] = [
        ("Blue", "#3068e8"), ("Indigo", "#5e6ad2"), ("Purple (Obsidian)", "#8a6cef"), ("Teal", "#1fa7a0"),
        ("Green", "#2fa864"), ("Amber", "#e0a100"), ("Orange", "#ee7a2c"), ("Red", "#e5484d"),
        ("Pink", "#e05295"), ("Graphite", "#8e8e93"),
    ]
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
