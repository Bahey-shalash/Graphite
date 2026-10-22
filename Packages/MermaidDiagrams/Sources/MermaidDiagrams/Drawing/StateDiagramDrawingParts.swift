import CoreGraphics

/// A laid-out state diagram's geometry grouped by how it is painted, so that drawing it in any colors is a handful of
/// fills and strokes, by Core Graphics (`StateDiagramRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// the transitions, the dashed lines to the notes and the arrows; the patches behind transition text and that text; the
/// states and their text; the notes and their text; the title.
public struct StateDiagramDrawingParts {
    /// The transitions' lines, stroked one point wide with round caps in the line color.
    public let transitionLines: CGPath
    /// The lines from states to their notes, stroked one point wide in dashes of 3 and gaps of 4 in the border color.
    public let noteConnectors: CGPath
    /// The arrows at the ends of transitions, filled in the line color.
    public let arrows: CGPath
    /// The patches behind transition text, filled in the background color.
    public let transitionTextPatches: CGPath
    public let transitionTexts: [DiagramTextBlock]
    /// The boxes and the choices' diamonds, filled in the surface color.
    public let stateFills: CGPath
    /// The boxes' and diamonds' outlines, and the lines under the names of boxes with several descriptions, stroked one
    /// point wide in the border color.
    public let stateOutlines: CGPath
    /// The rings of ends, filled in the background color and stroked one point wide in the line color.
    public let endRings: CGPath
    /// Starts, the dots of ends, and the bars of forks and joins, filled in the line color.
    public let solidMarks: CGPath
    /// The states' names, and the descriptions under them in smaller type.
    public let stateTexts: [DiagramTextBlock]
    /// The notes' sheets, filled in the background color and stroked one point wide in the border color, with the folds
    /// of their corners (`noteFolds`) stroked the same.
    public let noteSheets: CGPath
    public let noteFolds: CGPath
    /// The notes' text, in a color between the background and the text (`DiagramPalette.noteText`).
    public let noteTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let noteConnectorDashLengths: [CGFloat] = [3, 4]

    /// The corner radius of the patch behind a transition's text.
    static let transitionTextPatchCornerRadius: CGFloat = 3
    /// How much wider than its text the patch behind a transition's text is.
    static let transitionTextPatchExtraWidth: CGFloat = 8

    public init(layout: StateDiagramLayout) {
        let transitions = TransitionPaths(transitions: layout.transitions, notes: layout.notes)
        let states = StatePaths(states: layout.states)
        let notes = NotePaths(notes: layout.notes)
        transitionLines = transitions.lines
        noteConnectors = transitions.noteConnectors
        arrows = transitions.arrows
        transitionTextPatches = transitions.textPatches
        transitionTexts = layout.transitions.compactMap(\.text)
        stateFills = states.fills
        stateOutlines = states.outlines
        endRings = states.endRings
        solidMarks = states.solidMarks
        stateTexts = layout.states.flatMap { state in [state.name, state.details].compactMap { text in text } }
        noteSheets = notes.sheets
        noteFolds = notes.folds
        noteTexts = layout.notes.map(\.text)
        title = layout.title
    }

    /// The transitions' lines and arrows, the patches behind their text, and the lines to the notes.
    private struct TransitionPaths {
        let lines = CGMutablePath()
        let noteConnectors = CGMutablePath()
        let arrows = CGMutablePath()
        let textPatches = CGMutablePath()

        init(transitions: [StateDiagramLayoutTransition], notes: [StateDiagramLayoutNote]) {
            // A transition's arrow is only filled: nothing is ever stroked.
            let strokedMarks = CGMutablePath()
            for transition in transitions {
                lines.addPath(DiagramEdgeDrawing.path(transition.path))
                DiagramEdgeDrawing.addMark(transition.arrow, filled: arrows, stroked: strokedMarks)
                if let text = transition.text {
                    let patch = text.frame.insetBy(dx: -StateDiagramDrawingParts.transitionTextPatchExtraWidth / 2, dy: 0)
                    textPatches.addPath(CGPath(roundedRect: patch, cornerWidth: StateDiagramDrawingParts.transitionTextPatchCornerRadius,
                                               cornerHeight: StateDiagramDrawingParts.transitionTextPatchCornerRadius, transform: nil))
                }
            }
            for note in notes { noteConnectors.addPath(DiagramEdgeDrawing.path(note.connector)) }
        }
    }

    /// The states' shapes, by how each part is painted.
    private struct StatePaths {
        let fills = CGMutablePath()
        let outlines = CGMutablePath()
        let endRings = CGMutablePath()
        let solidMarks = CGMutablePath()

        init(states: [StateDiagramLayoutState]) {
            for state in states {
                let frame = state.frame
                switch state.kind {
                case .state:
                    let box = StateDiagramShapeDrawing.box(in: frame)
                    fills.addPath(box)
                    outlines.addPath(box)
                    if state.details != nil, let name = state.name { outlines.addPath(StateDiagramShapeDrawing.rule(in: frame, below: name)) }
                case .choice:
                    let diamond = StateDiagramShapeDrawing.diamond(in: frame)
                    fills.addPath(diamond)
                    outlines.addPath(diamond)
                case .start: solidMarks.addEllipse(in: frame)
                case .end:
                    endRings.addPath(StateDiagramShapeDrawing.endRing(in: frame))
                    solidMarks.addPath(StateDiagramShapeDrawing.endDot(in: frame))
                case .fork, .join: solidMarks.addPath(StateDiagramShapeDrawing.bar(in: frame))
                }
            }
        }
    }

    /// The notes' sheets and folds.
    private struct NotePaths {
        let sheets = CGMutablePath()
        let folds = CGMutablePath()

        init(notes: [StateDiagramLayoutNote]) {
            for note in notes {
                sheets.addPath(StateDiagramShapeDrawing.noteSheet(in: note.frame))
                folds.addPath(StateDiagramShapeDrawing.noteFold(in: note.frame))
            }
        }
    }
}
