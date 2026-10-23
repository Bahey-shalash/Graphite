import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// The colors a diagram is painted in: the note's background and text, and between them the shapes' fill and
/// outline, the groups' boxes and their titles where Pele's own colors put them (5.4 %, 52 %, 11.2 % and 64.7 % of the
/// way from its white page to its #1f1f1f text). They are SwiftUI colors, so a change of appearance or theme paints
/// again without making anything else.
struct ReadingDiagramColors {
    static let surfaceShare = 0.054
    static let borderShare = 0.52
    static let alternateSurfaceShare = 0.112
    static let mutedShare = 0.647

    let background: Color
    let foreground: Color
    let surface: Color
    let border: Color
    /// Pele's series colors, which a chart's slices take in turn, the same on a light page and a dark one.
    let series: [Color]
    /// What a chart marks, a Gantt chart's tasks and today's line: the vault theme's accent, else the app's.
    let accent: Color
    /// A Gantt chart's critical tasks: Pele's critical color.
    let critical: Color
    /// What is drawn quieter, such as a timeline's periods before its first section and a Gantt chart's dates: the vault
    /// theme's muted text, else Pele's #6e6e6e, where it is between its white page and its text.
    let muted: Color
    /// A second surface, a Gantt chart's finished tasks and excluded days: where Pele's is between its page and text.
    let alternateSurface: Color

    /// Where Pele's muted text (#6e6e6e) and second surface (#e6e6e6) are from its white page to its #1f1f1f text.
    static let mutedShare = 0.647
    static let alternateSurfaceShare = 0.112

    init(background: Color, foreground: Color, accent: Color = .accentColor, muted: Color? = nil) {
        self.background = background
        self.foreground = foreground
        surface = background.mix(with: foreground, by: Self.surfaceShare, in: .device)
        border = background.mix(with: foreground, by: Self.borderShare, in: .device)
        series = DiagramPalette.peleSeries.map { color in Color(cgColor: color) }
        self.accent = accent
        critical = Color(cgColor: DiagramPalette.peleCritical)
        self.muted = muted ?? background.mix(with: foreground, by: Self.mutedShare, in: .device)
        alternateSurface = background.mix(with: foreground, by: Self.alternateSurfaceShare, in: .device)
    }

    /// The vault theme's background, text, accent and muted text where it sets them, else the system's.
    init(theme: NoteThemeStyle?) {
        self.init(background: Color(theme?.background ?? NoteThemeStyle.systemBackground), foreground: Color(theme?.textNormal ?? NoteThemeStyle.systemLabel),
                  accent: theme?.accent.map { accent in Color(accent) } ?? .accentColor, muted: theme?.textMuted.map { muted in Color(muted) })
    }

    /// The colors a mindmap's branches take in turn: Pele's series colors, the same on a light and a dark page, as in Pele.
    static let series: [Color] = DiagramPalette.peleSeries.map { color in Color(cgColor: color) }

    /// The color of the `index`th series, the colors taken in turn.
    static func seriesColor(_ index: Int) -> Color {
        series[index % series.count]
    }
}
