import SwiftUI
import GraphiteCore

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
    /// Inside a group's box, painted at half its opacity over what is behind it.
    let alternateSurface: Color
    /// The titles of groups.
    let muted: Color

    init(background: Color, foreground: Color) {
        self.background = background
        self.foreground = foreground
        surface = background.mix(with: foreground, by: Self.surfaceShare, in: .device)
        border = background.mix(with: foreground, by: Self.borderShare, in: .device)
        alternateSurface = background.mix(with: foreground, by: Self.alternateSurfaceShare, in: .device)
        muted = background.mix(with: foreground, by: Self.mutedShare, in: .device)
    }

    /// The vault theme's background and text where it sets them, else the system's.
    init(theme: NoteThemeStyle?) {
        self.init(background: Color(theme?.background ?? NoteThemeStyle.systemBackground), foreground: Color(theme?.textNormal ?? NoteThemeStyle.systemLabel))
    }
}
