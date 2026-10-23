import CoreGraphics

/// The geometry of a mindmap node, Pele's: what it is drawn as, its size around its text, and how far inside its
/// bounding box the outline is where a link meets the middle of its left or right side. The shapes a flowchart has
/// too take the flowchart's sizes.
extension MindmapNodeOutline {
    /// The outline of a node: its written shape; without delimiters, a stadium for the root, a pill for a node with
    /// children and its text alone otherwise.
    init(shape: MindmapNodeShape, isRoot: Bool, hasChildren: Bool) {
        switch shape {
        case .plain: self = isRoot ? .stadium : hasChildren ? .pill : .text
        case .rectangle: self = .rectangle
        case .roundedRectangle: self = .roundedRectangle
        case .circle: self = .circle
        case .cloud: self = .cloud
        case .bang: self = .bang
        case .hexagon: self = .hexagon
        }
    }

    /// The flowchart shape this outline is drawn and sized as, or nil for one of the mindmap's own.
    var flowchartShape: FlowchartNodeShape? {
        switch self {
        case .stadium: .stadium
        case .rectangle: .rectangle
        case .roundedRectangle: .roundedRectangle
        case .circle: .circle
        case .hexagon: .hexagon
        case .cloud, .bang, .pill, .text: nil
        }
    }

    /// The size around a text of `textSize`, whose center is the outline's.
    func size(around textSize: CGSize) -> CGSize {
        let width = textSize.width
        let height = textSize.height
        if let flowchartShape { return FlowchartShapeGeometry.size(of: flowchartShape, textSize: textSize).size }
        let horizontalPadding = FlowchartShapeGeometry.horizontalPadding
        let verticalPadding = FlowchartShapeGeometry.verticalPadding
        switch self {
        case .cloud: return CGSize(width: width + 2 * horizontalPadding + Self.cloudRoom.width, height: height + 2 * verticalPadding + Self.cloudRoom.height)
        case .bang: return CGSize(width: width + 2 * horizontalPadding + Self.bangRoom.width, height: height + 2 * verticalPadding + Self.bangRoom.height)
        case .pill: return CGSize(width: width + 2 * Self.pillPadding, height: height + Self.pillExtraHeight)
        case .text: return CGSize(width: width + 2 * Self.textPadding, height: height)
        case .stadium, .rectangle, .roundedRectangle, .circle, .hexagon: return textSize
        }
    }

    /// How far inside the bounding box the outline is at the middle of its left or right side, where links meet it.
    func sideInset(size: CGSize) -> CGFloat {
        switch self {
        case .cloud: Self.cloudSideInset
        case .bang: Self.bangSideInset
        case .stadium, .rectangle, .roundedRectangle, .circle, .hexagon:
            flowchartShape.map { shape in FlowchartShapeGeometry.inset(of: shape, size: size, side: .left, offset: 0) } ?? 0
        case .pill, .text: 0
        }
    }

    /// The room a cloud's lobes and a bang's spikes take beyond a rectangle's padding.
    static let cloudRoom = CGSize(width: 32, height: 24)
    static let bangRoom = CGSize(width: 28, height: 24)
    /// How far a cloud's and a bang's outlines are inside their boxes at the middle of a side.
    static let cloudSideInset: CGFloat = 2
    static let bangSideInset: CGFloat = 3
    /// Across, on each side of a pill's text.
    static let pillPadding: CGFloat = 12
    /// How much taller than its text a pill is.
    static let pillExtraHeight: CGFloat = 6
    /// Across, on each side of a text drawn alone, which a link stops short of.
    static let textPadding: CGFloat = 6
}
