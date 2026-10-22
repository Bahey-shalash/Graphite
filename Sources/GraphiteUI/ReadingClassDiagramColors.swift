import SwiftUI

/// The colors a class diagram is painted in: a diagram's (`ReadingDiagramColors`), and between the note's background
/// and text the two more Pele's class diagram uses, where Pele's own colors put them: its muted text (#6e6e6e, 65 %
/// of the way from its white page to its #1f1f1f text) for annotations and cardinalities, and its alternate surface
/// (#e6e6e6, 11 %) inside notes.
struct ReadingClassDiagramColors {
    static let mutedShare = 0.647
    static let noteSurfaceShare = 0.112

    let diagram: ReadingDiagramColors
    let muted: Color
    let noteSurface: Color

    init(diagram: ReadingDiagramColors) {
        self.diagram = diagram
        muted = diagram.background.mix(with: diagram.foreground, by: Self.mutedShare, in: .device)
        noteSurface = diagram.background.mix(with: diagram.foreground, by: Self.noteSurfaceShare, in: .device)
    }
}
