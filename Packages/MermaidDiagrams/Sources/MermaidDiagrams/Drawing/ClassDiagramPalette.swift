import CoreGraphics

/// The colors a class diagram is drawn in: a diagram's (`DiagramPalette`) and the two more Pele's class diagram uses,
/// `--pele-muted` for annotations and cardinalities and `--pele-surface-alt` inside notes. Colors are given at draw
/// time: a change of theme draws the same layout again.
public struct ClassDiagramPalette: Sendable {
    public var diagram: DiagramPalette
    /// Annotations and cardinalities.
    public var muted: CGColor
    /// Inside notes.
    public var noteSurface: CGColor

    public init(diagram: DiagramPalette, muted: CGColor, noteSurface: CGColor) {
        self.diagram = diagram
        self.muted = muted
        self.noteSurface = noteSurface
    }

    /// Pele's own colors, for a light page.
    static let peleLight = ClassDiagramPalette(diagram: .peleLight, muted: CGColor(srgbRed: 0x6E / 255, green: 0x6E / 255, blue: 0x6E / 255, alpha: 1),
                                               noteSurface: CGColor(srgbRed: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE6 / 255, alpha: 1))
}
