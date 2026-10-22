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
    /// The colors of a chart's series (`--pele-series-1` to `--pele-series-8`), taken in turn: the first series is
    /// in the first color, the ninth in the first again.
    public var series: [CGColor]

    public init(background: CGColor, foreground: CGColor, line: CGColor, surface: CGColor, border: CGColor, series: [CGColor] = peleSeries) {
        self.background = background
        self.foreground = foreground
        self.line = line
        self.surface = surface
        self.border = border
        self.series = series
    }

    /// The color of the series at `index`, the colors taken in turn; the line color when there are none.
    public func seriesColor(at index: Int) -> CGColor {
        series.isEmpty ? line : series[index % series.count]
    }

    /// Pele's eight series colors, the same on a light page and a dark one.
    public static let peleSeries = [0x4C78A8, 0xF58518, 0x54A24B, 0xE45756, 0x72B7B2, 0xEECA3B, 0xB279A2, 0x9D755D].map(hexadecimalColor)

    /// Pele's own colors, for a light page.
    static let peleLight = DiagramPalette(background: gray(0xFF), foreground: gray(0x1F), line: gray(0x1F), surface: gray(0xF3), border: gray(0x8A))

    private static func hexadecimalColor(_ value: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private static func gray(_ level: Int) -> CGColor {
        let component = CGFloat(level) / 255
        return CGColor(srgbRed: component, green: component, blue: component, alpha: 1)
    }
}
