import SwiftUI
import GraphiteCore

public enum GraphiteTheme {
    /// Ink blue, the color of the blue pen preset (RGB 45, 93, 161): calm on paper white, and
    /// the app's one accent. In dark appearance it is lightened to stay readable, as any
    /// accent too light for light appearance is darkened (`AccentLegibility`).
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
    /// The height of the tab bar and of the rows below the navigation bar: Apple's standard
    /// 44-point touch height, so a bar's buttons take touches across all of it.
    static let barHeight: CGFloat = 44
    /// The corner radius of a tab, a tool or a row in use.
    static let cornerRadius: CGFloat = 8
    /// The fill behind the tab, tool or row in use, stronger when Increase Contrast is on.
    static let selectedFill = Color(PlatformColor.primaryText(opacity: 0.07, increasedContrastOpacity: 0.16))
    /// The color of a hairline between a bar and the page.
    static let hairline = Color(PlatformColor.primaryText(opacity: 0.1, increasedContrastOpacity: 0.3))
    /// The page's background, which the bars share so a document and its controls read
    /// as one surface.
    #if canImport(UIKit)
    static let barBackground = Color(uiColor: .systemBackground)
    #else
    static let barBackground = Color(nsColor: .textBackgroundColor)
    #endif
}

/// Graphite's motion: slides, folds and animated scrolling, which Apple asks apps to drop
/// when Reduce Motion is on, or to replace with a fade.
enum GraphiteMotion {
    static var isReduced: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }

    /// The animation, or none when Reduce Motion is on.
    static func animation(_ animation: Animation = .default) -> Animation? {
        isReduced ? nil : animation
    }

    /// A slide in from an edge, or a fade when Reduce Motion is on.
    static func slide(from edge: Edge) -> AnyTransition {
        isReduced ? .opacity : .move(edge: edge)
    }
}

/// A line one pixel thick and lighter than `Divider`, between a bar and the page.
struct Hairline: View {
    var axis: Axis = .horizontal
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let thickness = 1 / max(displayScale, 1)
        Rectangle()
            .fill(GraphiteChrome.hairline)
            .frame(width: axis == .vertical ? thickness : nil, height: axis == .horizontal ? thickness : nil)
            .accessibilityHidden(true)
    }
}

/// The four appearances a custom color is given for: light or dark, each with and without
/// Increase Contrast.
struct AppearanceVariants<Value> {
    var light: Value
    var lightIncreasedContrast: Value
    var dark: Value
    var darkIncreasedContrast: Value
}

extension PlatformColor {
    /// An accent from its `#rrggbb` value, readable as text in every appearance: the chosen
    /// color where it already reads, darkened just enough in light appearance and lightened
    /// just enough in dark appearance where it does not, and moved further when Increase
    /// Contrast is on (`AccentLegibility`).
    static func graphiteAccent(hex: String) -> PlatformColor? {
        guard let chosenColor = PlatformColor(graphiteHex: hex), let chosen = chosenColor.sRGBComponents else { return nil }
        func color(_ components: (red: Double, green: Double, blue: Double)) -> PlatformColor {
            PlatformColor.sRGB(red: components.red, green: components.green, blue: components.blue, alpha: chosen.alpha)
        }
        return appearanceDependent(AppearanceVariants(
            light: color(AccentLegibility.darkenedForLightBackground(red: chosen.red, green: chosen.green, blue: chosen.blue)),
            lightIncreasedContrast: color(AccentLegibility.darkenedForLightBackground(
                red: chosen.red, green: chosen.green, blue: chosen.blue, targetContrast: AccentLegibility.increasedTextContrast)),
            dark: color(AccentLegibility.lightenedForDarkBackground(red: chosen.red, green: chosen.green, blue: chosen.blue)),
            darkIncreasedContrast: color(AccentLegibility.lightenedForDarkBackground(
                red: chosen.red, green: chosen.green, blue: chosen.blue, targetContrast: AccentLegibility.increasedTextContrast))))
    }

    /// Text or a symbol drawn in a system color on a light tint of the same color, as a
    /// callout's title: the system color in dark appearance, where it reads on the dark
    /// tint, and darkened just enough to read on the tint in light appearance.
    static func legibleOnOwnTint(_ systemColor: PlatformColor, tintOpacity: Double) -> PlatformColor {
        func darkened(_ resolvedColor: PlatformColor, targetContrast: Double) -> PlatformColor {
            guard let resolved = resolvedColor.sRGBComponents else { return resolvedColor }
            let darkenedComponents = AccentLegibility.darkenedForOwnTint(red: resolved.red, green: resolved.green, blue: resolved.blue,
                                                                        tintOpacity: tintOpacity, targetContrast: targetContrast)
            return PlatformColor.sRGB(red: darkenedComponents.red, green: darkenedComponents.green, blue: darkenedComponents.blue, alpha: resolved.alpha)
        }
        #if canImport(UIKit)
        return UIColor { traitCollection in
            let resolvedColor = systemColor.resolvedColor(with: traitCollection)
            guard traitCollection.userInterfaceStyle != .dark else { return resolvedColor }
            let targetContrast = traitCollection.accessibilityContrast == .high ? AccentLegibility.increasedTextContrast : AccentLegibility.minimumTextContrast
            return darkened(resolvedColor, targetContrast: targetContrast)
        }
        #else
        return NSColor(name: nil) { appearance in
            var resolvedColor = systemColor
            appearance.performAsCurrentDrawingAppearance { resolvedColor = systemColor.usingColorSpace(.sRGB) ?? systemColor }
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            switch match {
            case .darkAqua?, .accessibilityHighContrastDarkAqua?: return resolvedColor
            case .accessibilityHighContrastAqua?: return darkened(resolvedColor, targetContrast: AccentLegibility.increasedTextContrast)
            default: return darkened(resolvedColor, targetContrast: AccentLegibility.minimumTextContrast)
            }
        }
        #endif
    }

    /// The primary text color at a low opacity, for fills and lines that set chrome apart,
    /// at a higher opacity when Increase Contrast is on.
    static func primaryText(opacity: Double, increasedContrastOpacity: Double) -> PlatformColor {
        #if canImport(UIKit)
        return UIColor { traitCollection in
            UIColor.label.resolvedColor(with: traitCollection)
                .withAlphaComponent(traitCollection.accessibilityContrast == .high ? increasedContrastOpacity : opacity)
        }
        #else
        return NSColor(name: nil) { appearance in
            let isIncreasedContrast = [.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua].contains(
                appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]))
            return NSColor.labelColor.withAlphaComponent(isIncreasedContrast ? increasedContrastOpacity : opacity)
        }
        #endif
    }

    /// One color per appearance, chosen as the system draws.
    static func appearanceDependent(_ variants: AppearanceVariants<PlatformColor>) -> PlatformColor {
        #if canImport(UIKit)
        return UIColor { traitCollection in
            let isIncreasedContrast = traitCollection.accessibilityContrast == .high
            if traitCollection.userInterfaceStyle == .dark { return isIncreasedContrast ? variants.darkIncreasedContrast : variants.dark }
            return isIncreasedContrast ? variants.lightIncreasedContrast : variants.light
        }
        #else
        return NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua?: variants.dark
            case .accessibilityHighContrastDarkAqua?: variants.darkIncreasedContrast
            case .accessibilityHighContrastAqua?: variants.lightIncreasedContrast
            default: variants.light
            }
        }
        #endif
    }

    /// The color's sRGB components, or nil when it has none (a pattern color).
    var sRGBComponents: (red: Double, green: Double, blue: Double, alpha: Double)? {
        #if canImport(UIKit)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return (red, green, blue, alpha)
        #else
        guard let components = usingColorSpace(.sRGB) else { return nil }
        return (components.redComponent, components.greenComponent, components.blueComponent, components.alphaComponent)
        #endif
    }

    static func sRGB(red: Double, green: Double, blue: Double, alpha: Double) -> PlatformColor {
        #if canImport(UIKit)
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #else
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
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

extension View {
    /// A bar at the top or bottom of the sidebar, over the rows that scroll under it. The
    /// iPad draws it on the bars' material, which hides the rows. The Mac leaves it on the
    /// sidebar's own material, with the system's scroll edge effect fading the rows under
    /// it, as Finder's and Mail's sidebars do: the bars' material is opaque there, and drew
    /// a white box behind the sidebar's picker, up under the toolbar, and a white band
    /// under the vault switcher.
    func sidebarBar<Bar: View>(edge: VerticalEdge, spacing: CGFloat? = 0, @ViewBuilder content: () -> Bar) -> some View {
        #if os(macOS)
        safeAreaBar(edge: edge, spacing: spacing, content: content)
        #else
        safeAreaInset(edge: edge, spacing: spacing) { content().background(.bar) }
        #endif
    }

    /// A form section's explanation under its section's leading edge, as System Settings
    /// sets them. The Mac's grouped forms set footers flush right, the place of a button
    /// such as "Details…", which made paragraphs ragged on the left.
    func formFooterAlignment() -> some View {
        #if os(macOS)
        frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            // In line with the section's header, which is inset from the section's edge.
            .padding(.leading, 10)
        #else
        self
        #endif
    }
}
