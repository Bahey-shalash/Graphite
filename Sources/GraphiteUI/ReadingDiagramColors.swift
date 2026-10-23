import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// The colors a diagram is painted in: the note's background and text, and between them the shapes' fill and
/// outline where Pele's own colors put them (5.4 % and 52 % of the way from its white page to its #1f1f1f text).
/// They are SwiftUI colors, so a change of appearance or theme paints again without making anything else.
struct ReadingDiagramColors {
    static let surfaceShare = 0.054
    static let borderShare = 0.52
    static let mutedShare = 0.647

    let background: Color
    let foreground: Color
    let surface: Color
    let border: Color
    /// What is drawn quieter, such as a timeline's periods before its first section: Pele's #6e6e6e on its white page.
    let muted: Color

    init(background: Color, foreground: Color) {
        self.background = background
        self.foreground = foreground
        surface = background.mix(with: foreground, by: Self.surfaceShare, in: .device)
        border = background.mix(with: foreground, by: Self.borderShare, in: .device)
        muted = background.mix(with: foreground, by: Self.mutedShare, in: .device)
    }

    /// The vault theme's background and text where it sets them, else the system's.
    init(theme: NoteThemeStyle?) {
        self.init(background: Color(theme?.background ?? NoteThemeStyle.systemBackground), foreground: Color(theme?.textNormal ?? NoteThemeStyle.systemLabel))
    }

    /// The colors a mindmap's branches take in turn: Pele's series colors, the same on a light and a dark page, as in Pele.
    static let series: [Color] = DiagramPalette.peleSeries.map { color in Color(cgColor: color) }

    /// The color of the `index`th series, the colors taken in turn.
    static func seriesColor(_ index: Int) -> Color {
        series[index % series.count]
    }
}
