import CoreGraphics

/// The crow's foot marks of the cardinalities, Pele's, drawn over the end of a line where it meets a box: one bar
/// across the line for "one", a ring for "zero", a foot whose toes spread on the box for "many". Exactly one is two
/// bars, zero or one a bar and a ring, one or more a foot and a bar, zero or more a foot and a ring, and the parent
/// end a hollow diamond. Rings and the diamond are filled with the background, so that the line does not show
/// through them.
enum EntityRelationshipCardinalityDrawing {
    /// Half a bar's length across the line.
    static let barHalfLength: CGFloat = 5
    /// Half the spread of a foot's toes on the box.
    static let footHalfWidth: CGFloat = 6
    /// How far back from the box a foot's toes meet.
    static let footLength: CGFloat = 10
    static let ringRadius: CGFloat = 3.5
    /// The diamond's length along the line and half its width.
    static let diamondLength: CGFloat = 12
    static let diamondHalfWidth: CGFloat = 4
    /// How far back from the box each bar or ring's center is: the bars of exactly one, the bar and ring of zero or
    /// one, and the bar or ring behind a foot.
    static let nearBarSetback: CGFloat = 6
    static let farBarSetback: CGFloat = 10
    static let ringBehindBarSetback: CGFloat = 13.5
    static let barBehindFootSetback: CGFloat = 13.5
    static let ringBehindFootSetback: CGFloat = 14

    /// Adds a mark to the paths filled with the background (rings, the diamond) and stroked in the line color.
    static func addMark(_ mark: EntityRelationshipCardinalityMark, fills: CGMutablePath, outlines: CGMutablePath) {
        // `back` runs from the box along the line, `side` across it.
        func point(back: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(x: mark.tip.x - mark.direction.dx * back - mark.direction.dy * side, y: mark.tip.y - mark.direction.dy * back + mark.direction.dx * side)
        }
        func addBar(back: CGFloat) {
            outlines.move(to: point(back: back, side: -barHalfLength))
            outlines.addLine(to: point(back: back, side: barHalfLength))
        }
        func addFoot() {
            outlines.addLines(between: [point(back: 0, side: -footHalfWidth), point(back: footLength, side: 0), point(back: 0, side: footHalfWidth)])
        }
        func addRing(back: CGFloat) {
            let center = point(back: back, side: 0)
            let ring = CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: 2 * ringRadius, height: 2 * ringRadius)
            fills.addEllipse(in: ring)
            outlines.addEllipse(in: ring)
        }
        switch mark.cardinality {
        case .exactlyOne:
            addBar(back: nearBarSetback)
            addBar(back: farBarSetback)
        case .zeroOrOne:
            addBar(back: nearBarSetback)
            addRing(back: ringBehindBarSetback)
        case .oneOrMore:
            addFoot()
            addBar(back: barBehindFootSetback)
        case .zeroOrMore:
            addFoot()
            addRing(back: ringBehindFootSetback)
        case .parent:
            let diamond = [point(back: 0, side: 0), point(back: diamondLength / 2, side: diamondHalfWidth), point(back: diamondLength, side: 0),
                           point(back: diamondLength / 2, side: -diamondHalfWidth)]
            fills.addLines(between: diamond)
            fills.closeSubpath()
            outlines.addLines(between: diamond)
            outlines.closeSubpath()
        }
    }
}
