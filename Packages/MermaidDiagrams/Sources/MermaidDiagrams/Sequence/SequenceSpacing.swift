import CoreGraphics

/// Pele's measurements of a sequence diagram at Mermaid's default configuration, in points.
enum SequenceSpacing {
    /// The least space between two participants' boxes.
    static let participantGap: CGFloat = 40
    /// Above a message's text, from the row before it.
    static let messageGap: CGFloat = 14
    /// Between a message's text and the lifelines at its ends.
    static let messagePadding: CGFloat = 12
    /// How far a message to its own participant loops out to the right, and how tall the loop is.
    static let selfLoopWidth: CGFloat = 28
    static let selfLoopHeight: CGFloat = 22
    /// The radius of the loop's two corners.
    static let selfLoopCornerRadius: CGFloat = 6
    /// Between a loop and its text.
    static let selfLoopTextGap: CGFloat = 8
    /// What a loop's room adds beyond its text, its corners and its activation, on the right.
    static let selfLoopTextRoom: CGFloat = 16
    static let activationWidth: CGFloat = 10
    /// How far right each nested activation of one participant moves.
    static let activationStep: CGFloat = 4
    static let activationMinimumHeight: CGFloat = 14
    /// Between a note and the lifeline it is beside.
    static let noteGap: CGFloat = 10
    /// How far a note over several lifelines reaches past the outer ones.
    static let noteOverhang: CGFloat = 16
    /// Between a note's text and its sides, and its top and bottom.
    static let notePadding: CGFloat = 10
    static let noteVerticalPadding: CGFloat = 6
    /// Above a note, from the row before it.
    static let noteGapAbove: CGFloat = 10
    /// Between a block's frame and what it holds, across; a block in another is this much further in.
    static let framePadding: CGFloat = 20
    static let frameNesting: CGFloat = 10
    /// Above a block's frame, and below what it holds; a highlight starts 8 points down.
    static let frameGap: CGFloat = 12
    static let highlightGap: CGFloat = 8
    static let tabHeight: CGFloat = 20
    /// What a tab adds to its keyword's width.
    static let tabExtraWidth: CGFloat = 14
    /// Between the frame's left side or its tab and a text in it.
    static let frameTextInset: CGFloat = 8
    /// The width a block's text wraps at, at least.
    static let frameTextWidth: CGFloat = 240
    /// The width a message's or note's text wraps at, when it wraps (`wrap:`).
    static let wrappingWidth: CGFloat = 160
    static let numberHeight: CGFloat = 16
    /// What a number's badge adds to its text's width.
    static let numberExtraWidth: CGFloat = 8
    /// Below the participants at the top before the first row, and after the last row before the participants
    /// mirrored at the bottom.
    static let firstRowGap: CGFloat = 6
    static let lastRowGap: CGFloat = 20
    /// Between a message's line and the bottom of its text.
    static let messageTextGap: CGFloat = 4
    /// The room Pele leaves under a message's text, under a block's title and above a section's text.
    static let textRoom: CGFloat = 2
    /// The height a message without text takes above its line.
    static let messageWithoutTextHeight: CGFloat = 6
    /// Around the whole diagram, and between the title and the diagram.
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// The patch of the background behind a text a lifeline crosses: wider than the text by this on each side, and
    /// shorter by `textPatchInset` at the top and the bottom.
    static let textPatchOutset: CGFloat = 3
    static let textPatchInset: CGFloat = 2
}
