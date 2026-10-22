import CoreGraphics

/// A laid-out sequence diagram's geometry grouped by how it is painted, so that drawing it in any colors is a handful
/// of fills and strokes, by Core Graphics (`SequenceRenderer`) or by a view's own shapes. Back to front, as Pele
/// draws: the highlights, the lifelines, the activations, the block frames, the messages and their numbers, the
/// messages' texts, the notes, the participants, the title. Besides `DiagramPalette`'s roles, Pele paints with a
/// muted text color and a second surface, which sit between the background and the foreground (`mutedShare`,
/// `surfaceAlternateShare`).
public struct SequenceDrawingParts {
    /// The `rect` backgrounds, back to front, each with its color or nil for the default shade: the second surface at
    /// half opacity.
    public let highlights: [SequenceDrawingHighlight]
    /// Stroked one point wide in the border color.
    public let lifelines: CGPath
    /// Activation bars, back to front, each filled with the surface and outlined in the border color.
    public let activations: [CGPath]
    /// The blocks' frames, stroked in the border color; their section lines, dashed.
    public let blockOutlines: CGPath
    public let blockSectionLines: CGPath
    /// The patches behind block texts a lifeline crosses, filled in the background color.
    public let blockTextPatches: CGPath
    /// The blocks' titles and section texts, in the muted color.
    public let blockTexts: [DiagramTextBlock]
    /// The tabs, filled with the surface and outlined in the border color, and their keywords, bold and muted.
    public let blockTabs: CGPath
    public let blockKeywords: [DiagramTextBlock]
    /// Messages' lines in the line color, one point wide with round caps; dotted ones dashed.
    public let solidMessageLines: CGPath
    public let dottedMessageLines: CGPath
    /// Arrowheads, filled in the line color; crosses and open heads, stroked one point wide with round joins.
    public let filledHeads: CGPath
    public let strokedHeads: CGPath
    /// The numbers' badges, filled in the line color, and the numbers on them, in the background color.
    public let numberBadges: CGPath
    public let numberTexts: [DiagramTextBlock]
    /// The patches behind messages' texts a lifeline crosses, in the background color, and the texts.
    public let messageTextPatches: CGPath
    public let messageTexts: [DiagramTextBlock]
    /// Notes, filled with the second surface and outlined in the border color, and their text.
    public let notes: CGPath
    public let noteTexts: [DiagramTextBlock]
    /// Participants' boxes and actors' heads, filled with the surface and outlined in the border color; actors'
    /// bodies, arms and legs, stroked in the border color.
    public let participantShapes: CGPath
    public let participantFigureLines: CGPath
    public let participantTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    /// Dotted messages and block sections: dashes of 4, gaps of 4.
    public static let dashLengths: [CGFloat] = [4, 4]
    /// Pele's muted text (#6e6e6e) and second surface (#e6e6e6), as shares of the way from its white page to its
    /// #1f1f1f text.
    public static let mutedShare: CGFloat = 145.0 / 224.0
    public static let surfaceAlternateShare: CGFloat = 25.0 / 224.0
    /// The opacity of a highlight without a color of its own.
    public static let defaultHighlightOpacity: CGFloat = 0.5
    /// Pele's `--pele-radius`, the corners of frames, tabs, notes, boxes and highlights; activations have smaller ones.
    static let cornerRadius: CGFloat = 4
    static let activationCornerRadius: CGFloat = 2
    /// An open head's half height, Pele's.
    static let openHeadHalfHeight: CGFloat = 4.5

    public init(layout: SequenceLayout) {
        highlights = layout.highlights.map { highlight in SequenceDrawingHighlight(path: Self.roundedRectangle(highlight.frame), color: highlight.color) }
        let lifelines = CGMutablePath()
        for lifeline in layout.lifelines where lifeline.bottom > lifeline.top {
            lifelines.move(to: CGPoint(x: lifeline.x, y: lifeline.top))
            lifelines.addLine(to: CGPoint(x: lifeline.x, y: lifeline.bottom))
        }
        self.lifelines = lifelines
        activations = layout.activations.map { activation in
            CGPath(roundedRect: activation, cornerWidth: Self.activationCornerRadius, cornerHeight: Self.activationCornerRadius, transform: nil)
        }
        let blocks = BlockPaths(blocks: layout.blocks)
        blockOutlines = blocks.outlines
        blockSectionLines = blocks.sectionLines
        blockTextPatches = blocks.textPatches
        blockTexts = layout.blocks.flatMap { block in [block.title].compactMap { title in title } + block.sections.compactMap(\.text) }
        blockTabs = blocks.tabs
        blockKeywords = layout.blocks.map(\.keyword)
        let messages = MessagePaths(messages: layout.messages)
        solidMessageLines = messages.solidLines
        dottedMessageLines = messages.dottedLines
        filledHeads = messages.filledHeads
        strokedHeads = messages.strokedHeads
        numberBadges = messages.numberBadges
        numberTexts = layout.messages.compactMap { message in message.number?.text }
        messageTextPatches = messages.textPatches
        messageTexts = layout.messages.compactMap(\.text)
        let notes = CGMutablePath()
        for note in layout.notes { notes.addPath(Self.roundedRectangle(note.frame)) }
        self.notes = notes
        noteTexts = layout.notes.map(\.text)
        let participants = ParticipantPaths(participants: layout.participants)
        participantShapes = participants.shapes
        participantFigureLines = participants.figureLines
        participantTexts = layout.participants.map(\.text)
        title = layout.title
    }

    static func roundedRectangle(_ frame: CGRect) -> CGPath {
        CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }

    /// The blocks' frames, section lines, text patches and tabs.
    private struct BlockPaths {
        let outlines = CGMutablePath()
        let sectionLines = CGMutablePath()
        let textPatches = CGMutablePath()
        let tabs = CGMutablePath()

        init(blocks: [SequenceLayoutBlock]) {
            for block in blocks {
                outlines.addPath(SequenceDrawingParts.roundedRectangle(block.frame))
                for section in block.sections {
                    sectionLines.move(to: CGPoint(x: block.frame.minX, y: section.lineY))
                    sectionLines.addLine(to: CGPoint(x: block.frame.maxX, y: section.lineY))
                }
                for patch in block.textPatches { textPatches.addPath(SequenceDrawingParts.roundedRectangle(patch)) }
                tabs.addPath(SequenceDrawingParts.roundedRectangle(block.tab))
            }
        }
    }

    /// The messages' lines by stroke, their heads, their numbers' badges and their text patches.
    private struct MessagePaths {
        let solidLines = CGMutablePath()
        let dottedLines = CGMutablePath()
        let filledHeads = CGMutablePath()
        let strokedHeads = CGMutablePath()
        let numberBadges = CGMutablePath()
        let textPatches = CGMutablePath()

        init(messages: [SequenceLayoutMessage]) {
            for message in messages {
                switch message.stroke {
                case .solid: solidLines.addPath(DiagramEdgeDrawing.path(message.path))
                case .dotted: dottedLines.addPath(DiagramEdgeDrawing.path(message.path))
                }
                for head in message.heads { addHead(head) }
                if let number = message.number {
                    let radius = number.frame.height / 2
                    numberBadges.addPath(CGPath(roundedRect: number.frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
                }
                if let patch = message.textPatch { textPatches.addPath(SequenceDrawingParts.roundedRectangle(patch)) }
            }
        }

        /// An arrow and a cross as a flowchart's edges draw them; an open head as two strokes back from the tip.
        private func addHead(_ head: SequenceLayoutArrowhead) {
            switch head.kind {
            case .none: return
            case .arrow, .cross:
                let arrowhead: FlowchartArrowhead = head.kind == .arrow ? .arrow : .cross
                DiagramEdgeDrawing.addMark(DiagramEdgeMark(arrowhead: arrowhead, tip: head.tip, direction: head.direction), filled: filledHeads,
                                           stroked: strokedHeads)
            case .open:
                let length = DiagramEdgeMark.arrowLength
                let back = CGPoint(x: head.tip.x - head.direction.dx * length, y: head.tip.y - head.direction.dy * length)
                let normal = CGVector(dx: -head.direction.dy, dy: head.direction.dx)
                let halfHeight = SequenceDrawingParts.openHeadHalfHeight
                strokedHeads.addLines(between: [CGPoint(x: back.x + normal.dx * halfHeight, y: back.y + normal.dy * halfHeight), head.tip,
                                                CGPoint(x: back.x - normal.dx * halfHeight, y: back.y - normal.dy * halfHeight)])
            }
        }
    }

    /// The participants' boxes and heads, and the actors' limbs.
    private struct ParticipantPaths {
        let shapes = CGMutablePath()
        let figureLines = CGMutablePath()

        init(participants: [SequenceLayoutParticipant]) {
            for participant in participants {
                switch participant.kind {
                case .participant: shapes.addPath(SequenceDrawingParts.roundedRectangle(participant.frame))
                case .actor:
                    shapes.addEllipse(in: SequenceParticipantGeometry.figureHead(in: participant.frame))
                    for limb in SequenceParticipantGeometry.figureLimbs(in: participant.frame) { figureLines.addLines(between: limb) }
                }
            }
        }
    }
}

/// A `rect` background's shape and its color, or nil for the default shade.
public struct SequenceDrawingHighlight {
    public let path: CGPath
    public let color: SequenceHighlightColor?
}
