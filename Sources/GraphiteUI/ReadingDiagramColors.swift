import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// The colors a diagram is painted in: the note's background and text, and between them the shapes' fill and
/// outline where Pele's own colors put them (5.4 % and 52 % of the way from its white page to its #1f1f1f text).
/// They are SwiftUI colors, so a change of appearance or theme paints again without making anything else.
struct ReadingDiagramColors {
    static let surfaceShare = 0.054
    static let borderShare = 0.52

    let background: Color
    let foreground: Color
    let surface: Color
    let border: Color
    /// Pele's series colors, which a chart's slices take in turn, the same on a light page and a dark one.
    let series: [Color]

    init(background: Color, foreground: Color) {
        self.background = background
        self.foreground = foreground
        surface = background.mix(with: foreground, by: Self.surfaceShare, in: .device)
        border = background.mix(with: foreground, by: Self.borderShare, in: .device)
        series = DiagramPalette.peleSeries.map { color in Color(cgColor: color) }
    }

    /// The vault theme's background and text where it sets them, else the system's.
    init(theme: NoteThemeStyle?) {
        self.init(background: Color(theme?.background ?? NoteThemeStyle.systemBackground), foreground: Color(theme?.textNormal ?? NoteThemeStyle.systemLabel))
    }
}
