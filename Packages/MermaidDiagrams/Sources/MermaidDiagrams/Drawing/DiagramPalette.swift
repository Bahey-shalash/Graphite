import CoreGraphics

/// The colors a diagram is drawn in, by Pele's roles (`--pele-bg`, `--pele-fg`, `--pele-line`, `--pele-surface`,
/// `--pele-border`, `--pele-surface-alt`, `--pele-muted`), so that a theme's values map one to one. Colors are given at
/// draw time: a change of theme draws the same layout again.
public struct DiagramPalette: Sendable {
    /// Behind the diagram: the patch behind an edge's text is this color, so the line does not run through the text.
    public var background: CGColor
    /// Text.
    public var foreground: CGColor
    /// Edges and their marks.
    public var line: CGColor
    /// Inside node shapes.
    public var surface: CGColor
    /// Node outlines, and the outlines of groups' boxes.
    public var border: CGColor
    /// Inside a group's box, painted at `FlowchartDrawingParts.clusterFillOpacity` over what is behind it, so that a
    /// box inside another is darker.
    public var alternateSurface: CGColor
    /// The titles of groups.
    public var mutedForeground: CGColor

    /// Where Pele's own colors put the alternate surface and the muted text between its white page and its #1f1f1f
    /// text: the shares of the way from the background to the foreground.
    static let alternateSurfaceShare: CGFloat = 0.112
    static let mutedForegroundShare: CGFloat = 0.647

    /// A palette whose alternate surface and muted text lie between the background and the foreground where Pele's own
    /// colors put them.
    public init(background: CGColor, foreground: CGColor, line: CGColor, surface: CGColor, border: CGColor) {
        self.init(background: background, foreground: foreground, line: line, surface: surface, border: border,
                  alternateSurface: Self.mixed(background, foreground, share: Self.alternateSurfaceShare) ?? surface,
                  mutedForeground: Self.mixed(background, foreground, share: Self.mutedForegroundShare) ?? foreground)
    }

    public init(background: CGColor, foreground: CGColor, line: CGColor, surface: CGColor, border: CGColor, alternateSurface: CGColor,
                mutedForeground: CGColor) {
        self.background = background
        self.foreground = foreground
        self.line = line
        self.surface = surface
        self.border = border
        self.alternateSurface = alternateSurface
        self.mutedForeground = mutedForeground
    }

    /// Pele's own colors, for a light page.
    static let peleLight = DiagramPalette(background: gray(0xFF), foreground: gray(0x1F), line: gray(0x1F), surface: gray(0xF3), border: gray(0x8A),
                                          alternateSurface: gray(0xE6), mutedForeground: gray(0x6E))

    private static func gray(_ level: Int) -> CGColor {
        let component = CGFloat(level) / 255
        return CGColor(srgbRed: component, green: component, blue: component, alpha: 1)
    }

    /// `first` moved `share` of the way to `second`, component by component in sRGB, or nil when either has no sRGB form.
    static func mixed(_ first: CGColor, _ second: CGColor, share: CGFloat) -> CGColor? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let from = first.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let to = second.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              from.count == 4, to.count == 4 else { return nil }
        let components = zip(from, to).map { start, end in start + (end - start) * share }
        return CGColor(colorSpace: space, components: components)
    }
}
