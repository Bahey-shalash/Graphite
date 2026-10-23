import CoreGraphics

/// The size of a participant around its text, and the stick figure of an actor, Pele's.
enum SequenceParticipantGeometry {
    /// Between a box's text and its sides.
    static let horizontalPadding: CGFloat = 16
    /// Between a box's text and its top and bottom.
    static let verticalPadding: CGFloat = 10
    static let minimumBoxWidth: CGFloat = 64
    /// What a box's height adds to one and a half lines of the participants' text: Mermaid's default height.
    static let boxHeightBeyondText: CGFloat = 20
    /// The stick figure's height, above the actor's text.
    static let figureHeight: CGFloat = 34
    static let figureTextGap: CGFloat = 4
    static let minimumFigureWidth: CGFloat = 40
    /// How much wider than its text an actor is.
    static let figureExtraWidth: CGFloat = 8

    /// The participant's size around text of `textSize`, its text in `fontSize`.
    static func size(of kind: SequenceParticipantKind, textSize: CGSize, fontSize: CGFloat) -> CGSize {
        switch kind {
        case .participant:
            let minimumHeight = (fontSize * CoreTextDiagramTextMeasurer.lineHeightRatio).rounded() + boxHeightBeyondText
            return CGSize(width: max(minimumBoxWidth, textSize.width + 2 * horizontalPadding),
                          height: max(minimumHeight, textSize.height + 2 * verticalPadding))
        case .actor:
            return CGSize(width: max(minimumFigureWidth, textSize.width + figureExtraWidth),
                          height: figureHeight + (textSize.height > 0 ? figureTextGap + textSize.height : 0))
        }
    }

    /// Where the participant's text is centered in its frame: in the box, or under the figure.
    static func textCenter(of kind: SequenceParticipantKind, in frame: CGRect, textHeight: CGFloat) -> CGPoint {
        switch kind {
        case .participant: CGPoint(x: frame.midX, y: frame.midY)
        case .actor: CGPoint(x: frame.midX, y: frame.minY + figureHeight + figureTextGap + textHeight / 2)
        }
    }

    /// The figure's head, a circle of radius 6 centered 7 points under the top.
    static func figureHead(in frame: CGRect) -> CGRect {
        let radius: CGFloat = 6
        let headCenterDepth: CGFloat = 7
        return CGRect(x: frame.midX - radius, y: frame.minY + headCenterDepth - radius, width: 2 * radius, height: 2 * radius)
    }

    /// The figure's body, arms and legs, as lines from point to point.
    static func figureLimbs(in frame: CGRect) -> [[CGPoint]] {
        let centerX = frame.midX
        let top = frame.minY
        func point(_ horizontal: CGFloat, _ depth: CGFloat) -> CGPoint { CGPoint(x: centerX + horizontal, y: top + depth) }
        return [[point(0, 13), point(0, 24)], [point(-10, 17), point(10, 17)], [point(-8, 34), point(0, 24), point(8, 34)]]
    }
}
