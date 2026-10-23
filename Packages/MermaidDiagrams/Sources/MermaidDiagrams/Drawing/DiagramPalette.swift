import CoreGraphics

/// The colors a diagram is drawn in, by Pele's roles (`--pele-bg`, `--pele-fg`, `--pele-line`, `--pele-surface`,
/// `--pele-border`, `--pele-series-1` to `--pele-series-8`, `--pele-accent`, `--pele-critical`, `--pele-muted`,
/// `--pele-surface-alt`), so that a theme's values map one to one. Colors are given at draw time: a change of theme
/// draws the same layout again.
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
    /// The colors of a chart's series (`--pele-series-1` to `--pele-series-8`), taken in turn: a pie chart's slices,
    /// a mindmap's branches, a timeline's sections. The first series is in the first color, the ninth in the first again.
    public var series: [CGColor]
    /// What a chart marks (`--pele-accent`): a Gantt chart's tasks and today's line.
    public var accent: CGColor
    /// What a chart marks as critical (`--pele-critical`): a Gantt chart's `crit` tasks.
    public var critical: CGColor
    /// What is drawn quieter than the rest (`--pele-muted`): a Gantt chart's axis dates and finished tasks' text, a
    /// timeline's periods before its first section, the titles of a flowchart's groups.
    public var muted: CGColor
    /// A second surface (`--pele-surface-alt`): a Gantt chart's finished tasks and excluded days, and the inside of a
    /// flowchart group's box, painted at `FlowchartDrawingParts.clusterFillOpacity` so that a box inside another is darker.
    public var alternateSurface: CGColor

    /// Where Pele's own colors put the muted text and the second surface between its white page and its #1f1f1f text:
    /// the shares of the way from the background to the foreground.
    static let mutedShare: CGFloat = 0.647
    static let alternateSurfaceShare: CGFloat = 0.112

    /// A palette in these colors. The series, accent and critical colors are Pele's unless given; the muted text and
    /// the second surface lie between the background and the foreground where Pele's own colors put them unless given.
    public init(background: CGColor, foreground: CGColor, line: CGColor, surface: CGColor, border: CGColor, series: [CGColor] = peleSeries,
                accent: CGColor = peleAccent, critical: CGColor = peleCritical, muted: CGColor? = nil, alternateSurface: CGColor? = nil) {
        self.background = background
        self.foreground = foreground
        self.line = line
        self.surface = surface
        self.border = border
        self.series = series
        self.accent = accent
        self.critical = critical
        self.muted = muted ?? Self.mixed(background, foreground, share: Self.mutedShare) ?? Self.peleMuted
        self.alternateSurface = alternateSurface ?? Self.mixed(background, foreground, share: Self.alternateSurfaceShare) ?? surface
    }

    /// The color of the series at `index`, the colors taken in turn; the line color when there are none.
    public func seriesColor(at index: Int) -> CGColor {
        series.isEmpty ? line : series[index % series.count]
    }

    /// Pele's accent, `#5b7bd5`.
    public static let peleAccent = hexadecimalColor(0x5B7BD5)
    /// Pele's critical color, `#e45756`, which is none of the series colors' places, as a theme may order those.
    public static let peleCritical = hexadecimalColor(0xE45756)
    /// Pele's muted text, `#6e6e6e`.
    public static let peleMuted = gray(0x6E)
    /// Pele's second surface, `#e6e6e6`.
    public static let peleAlternateSurface = gray(0xE6)

    /// Pele's eight series colors, the same on a light page and a dark one.
    public static let peleSeries = [0x4C78A8, 0xF58518, 0x54A24B, 0xE45756, 0x72B7B2, 0xEECA3B, 0xB279A2, 0x9D755D].map(hexadecimalColor)

    /// Pele's own colors, for a light page.
    static let peleLight = DiagramPalette(background: gray(0xFF), foreground: gray(0x1F), line: gray(0x1F), surface: gray(0xF3), border: gray(0x8A),
                                          muted: peleMuted, alternateSurface: peleAlternateSurface)

    /// `first` moved `share` of the way to `second`, component by component in sRGB, or nil when either has no sRGB form.
    static func mixed(_ first: CGColor, _ second: CGColor, share: CGFloat) -> CGColor? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let from = first.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let to = second.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              from.count == 4, to.count == 4 else { return nil }
        let components = zip(from, to).map { start, end in start + (end - start) * share }
        return CGColor(colorSpace: space, components: components)
    }

    private static func hexadecimalColor(_ value: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private static func gray(_ level: Int) -> CGColor {
        let component = CGFloat(level) / 255
        return CGColor(srgbRed: component, green: component, blue: component, alpha: 1)
    }
}
