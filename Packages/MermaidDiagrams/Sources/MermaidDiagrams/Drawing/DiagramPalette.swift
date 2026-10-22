import CoreGraphics

/// The colors a diagram is drawn in, by Pele's roles (`--pele-bg`, `--pele-fg`, `--pele-line`, `--pele-surface`,
/// `--pele-border`), so that a theme's values map one to one. Colors are given at draw time: a change of theme draws
/// the same layout again.
public struct DiagramPalette: Sendable {
    /// Behind the diagram: the patch behind an edge's text is this color, so the line does not run through the text.
    public var background: CGColor
    /// Text.
    public var foreground: CGColor
    /// Edges and their marks.
    public var line: CGColor
    /// Inside node shapes.
    public var surface: CGColor
    /// Node outlines.
    public var border: CGColor

    public init(background: CGColor, foreground: CGColor, line: CGColor, surface: CGColor, border: CGColor) {
        self.background = background
        self.foreground = foreground
        self.line = line
        self.surface = surface
        self.border = border
    }

    /// Pele's own colors, for a light page.
    static let peleLight = DiagramPalette(background: gray(0xFF), foreground: gray(0x1F), line: gray(0x1F), surface: gray(0xF3), border: gray(0x8A))

    private static func gray(_ level: Int) -> CGColor {
        let component = CGFloat(level) / 255
        return CGColor(srgbRed: component, green: component, blue: component, alpha: 1)
    }

    /// The colors that a mindmap's branches (and other types' series) take in turn: Pele's `--pele-series-1` to
    /// `--pele-series-8` unless set.
    public var series: [CGColor] = DiagramPalette.peleSeries

    /// The color of the `index`th series, the colors taken in turn; the line color when `series` is empty.
    public func seriesColor(_ index: Int) -> CGColor {
        series.isEmpty ? line : series[index % series.count]
    }

    /// Pele's eight series colors.
    public static let peleSeries: [CGColor] = [0x4C78A8, 0xF58518, 0x54A24B, 0xE45756, 0x72B7B2, 0xEECA3B, 0xB279A2, 0x9D755D].map { hex in
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
