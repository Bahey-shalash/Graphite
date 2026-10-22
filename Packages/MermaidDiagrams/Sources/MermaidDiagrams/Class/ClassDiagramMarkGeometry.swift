import CoreGraphics

/// The sizes of a relation's marks, Pele's: a hollow triangle 12 points long and 12 wide, a diamond 16 long and
/// 10 wide, a ring 5 points in radius, and the flowchart's arrow.
enum ClassDiagramMarkGeometry {
    static let triangleLength: CGFloat = 12
    static let triangleHalfWidth: CGFloat = 6
    static let diamondLength: CGFloat = 16
    static let diamondHalfWidth: CGFloat = 5
    static let ringRadius: CGFloat = 5
    /// The longest mark, which the drawing's bounds leave room for around each tip.
    static let longestMark: CGFloat = diamondLength

    /// How much of a relation's line a mark takes, so that the line meets the mark's back.
    static func lineTrim(for end: ClassDiagramRelationEnd) -> CGFloat {
        switch end {
        case .none: 0
        case .inheritance: triangleLength
        case .composition, .aggregation: diamondLength
        case .arrow: DiagramEdgeMark.lineTrim(for: .arrow)
        case .lollipop: 2 * ringRadius
        }
    }
}
