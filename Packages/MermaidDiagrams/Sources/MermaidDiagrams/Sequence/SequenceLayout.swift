import CoreGraphics

/// A sequence diagram laid out on a page whose origin is the top left corner and whose y runs down, in points.
/// Drawing it needs only colors: every position, path and text measurement is here. Lists that overlap are back to
/// front: a highlight or an activation nested in another comes after it.
public struct SequenceLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the participants' text was measured in; messages, notes and blocks use it at their own sizes.
    public let font: DiagramFont
    /// Each participant above its lifeline, in the participants' order, then each again below it, as Pele mirrors them.
    public let participants: [SequenceLayoutParticipant]
    public let lifelines: [SequenceLayoutLifeline]
    /// `rect` backgrounds.
    public let highlights: [SequenceLayoutHighlight]
    /// Activation bars on the lifelines.
    public let activations: [CGRect]
    /// The frames of `loop`, `alt`, `opt`, `par`, `critical` and `break` blocks.
    public let blocks: [SequenceLayoutBlock]
    public let messages: [SequenceLayoutMessage]
    public let notes: [SequenceLayoutNote]
    /// The diagram's title above it, drawn bold, or nil.
    public let title: DiagramTextBlock?
}

public struct SequenceLayoutParticipant: Equatable, Sendable {
    public let kind: SequenceParticipantKind
    /// The box around the text, or the stick figure and the text under it.
    public let frame: CGRect
    public let text: DiagramTextBlock
}

/// A participant's lifeline, a vertical line at `x` from `top` to `bottom`.
public struct SequenceLayoutLifeline: Equatable, Sendable {
    public let x: CGFloat
    public let top: CGFloat
    public let bottom: CGFloat
}

public struct SequenceLayoutHighlight: Equatable, Sendable {
    public let frame: CGRect
    /// The color the `rect` names, or nil for the default shade.
    public let color: SequenceHighlightColor?
}

public struct SequenceLayoutBlock: Equatable, Sendable {
    public let frame: CGRect
    /// The tab in the frame's top left corner, which holds the keyword.
    public let tab: CGRect
    /// `loop`, `alt`, `opt`, `par`, `critical` or `break`, drawn bold in the tab.
    public let keyword: DiagramTextBlock
    /// The block's text in brackets beside the tab, or nil.
    public let title: DiagramTextBlock?
    /// Each section after the first (`else`, `and`, `option`): a dashed line across the frame and its text.
    public let sections: [SequenceLayoutBlockSection]
    /// The patches of the background behind texts a lifeline would run through.
    public let textPatches: [CGRect]
}

public struct SequenceLayoutBlockSection: Equatable, Sendable {
    /// Where the dashed line runs across the frame.
    public let lineY: CGFloat
    /// The section's text in brackets under the line, or nil.
    public let text: DiagramTextBlock?
}

public struct SequenceLayoutMessage: Equatable, Sendable {
    public let stroke: SequenceLineStroke
    /// The line, which stops where a head begins: straight between two lifelines, a loop back to a participant's own.
    public let path: DiagramPath
    public let heads: [SequenceLayoutArrowhead]
    /// The message's text, or nil when it has none.
    public let text: DiagramTextBlock?
    /// A patch of the background behind the text where a lifeline would run through it, or nil.
    public let textPatch: CGRect?
    /// The message's `autonumber` number, or nil.
    public let number: SequenceLayoutNumber?
}

/// The head at an end of a message's line: its kind, the point it touches, and the unit direction it points in.
public struct SequenceLayoutArrowhead: Equatable, Sendable {
    public let kind: SequenceArrowhead
    public let tip: CGPoint
    public let direction: CGVector
}

/// A message's number: a rounded badge in the line's color and the number on it.
public struct SequenceLayoutNumber: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock
}

public struct SequenceLayoutNote: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock
}

extension SequenceLayoutParticipant {
    func translated(by offset: CGVector) -> SequenceLayoutParticipant {
        SequenceLayoutParticipant(kind: kind, frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text.translated(by: offset))
    }
}

extension SequenceLayoutLifeline {
    func translated(by offset: CGVector) -> SequenceLayoutLifeline {
        SequenceLayoutLifeline(x: x + offset.dx, top: top + offset.dy, bottom: bottom + offset.dy)
    }
}

extension SequenceLayoutHighlight {
    func translated(by offset: CGVector) -> SequenceLayoutHighlight {
        SequenceLayoutHighlight(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), color: color)
    }
}

extension SequenceLayoutBlock {
    func translated(by offset: CGVector) -> SequenceLayoutBlock {
        SequenceLayoutBlock(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), tab: tab.offsetBy(dx: offset.dx, dy: offset.dy),
                            keyword: keyword.translated(by: offset), title: title?.translated(by: offset),
                            sections: sections.map { section in
                                SequenceLayoutBlockSection(lineY: section.lineY + offset.dy, text: section.text?.translated(by: offset))
                            },
                            textPatches: textPatches.map { patch in patch.offsetBy(dx: offset.dx, dy: offset.dy) })
    }
}

extension SequenceLayoutMessage {
    func translated(by offset: CGVector) -> SequenceLayoutMessage {
        SequenceLayoutMessage(stroke: stroke, path: path.translated(by: offset),
                              heads: heads.map { head in
                                  SequenceLayoutArrowhead(kind: head.kind, tip: head.tip.translated(by: offset), direction: head.direction)
                              },
                              text: text?.translated(by: offset), textPatch: textPatch?.offsetBy(dx: offset.dx, dy: offset.dy),
                              number: number.map { number in
                                  SequenceLayoutNumber(frame: number.frame.offsetBy(dx: offset.dx, dy: offset.dy), text: number.text.translated(by: offset))
                              })
    }
}

extension SequenceLayoutNote {
    func translated(by offset: CGVector) -> SequenceLayoutNote {
        SequenceLayoutNote(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text.translated(by: offset))
    }
}
