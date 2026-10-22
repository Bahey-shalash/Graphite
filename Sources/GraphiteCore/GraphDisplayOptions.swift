import Foundation

/// What Obsidian's graph "Display" settings change beside Arrows: the size of the nodes, the
/// thickness of the links and the zoom from which names show.
public struct GraphDisplayOptions: Equatable, Sendable {
    /// A multiple of each node's size, which grows with its links.
    public var nodeSizeMultiplier: Double
    /// A multiple of each link's width.
    public var linkThicknessMultiplier: Double
    /// The zoom from which every note shows its name (Names From Zoom, Obsidian's "text fade
    /// threshold"); tags show theirs from half of it.
    public var nameScale: Double

    public static let nodeSizeMultipliers = 0.25...3.0
    public static let linkThicknessMultipliers = 0.25...4.0
    public static let nameScales = 0.3...3.0
    /// Tags are fewer and gather notes, so their names show from this share of a note's zoom.
    static let tagNameScaleRatio = 0.5
    /// Names begin to fade in at this share of the zoom where they are drawn whole, so that
    /// they come in as the person zooms rather than all at once.
    static let nameFadeStartRatio = 0.75

    public init(nodeSizeMultiplier: Double = 1, linkThicknessMultiplier: Double = 1, nameScale: Double = 1.4) {
        self.nodeSizeMultiplier = nodeSizeMultiplier
        self.linkThicknessMultiplier = linkThicknessMultiplier
        self.nameScale = nameScale
    }

    /// The zoom from which a node of this kind draws its name whole, without a hover or a
    /// choice; it fades in from `nameFadeStartScale(of:)`.
    public func nameScale(of kind: GraphNode.Kind) -> Double {
        switch kind {
        case .tag: nameScale * Self.tagNameScaleRatio
        case .note, .attachment, .unresolved: nameScale
        }
    }

    /// The zoom from which a node of this kind begins to show its name, faintly.
    public func nameFadeStartScale(of kind: GraphNode.Kind) -> Double {
        nameScale(of: kind) * Self.nameFadeStartRatio
    }

    /// How strongly a node of this kind draws its name at this zoom, without a hover or a
    /// choice: nothing below its fade start, then more as the zoom nears its name zoom, whole
    /// from there on.
    public func nameOpacity(of kind: GraphNode.Kind, atScale scale: Double) -> Double {
        let fadeStart = nameFadeStartScale(of: kind), whole = nameScale(of: kind)
        guard scale > fadeStart else { return 0 }
        return min((scale - fadeStart) / (whole - fadeStart), 1)
    }

    /// Whether a node of this kind shows its name at this zoom, faintly or whole, without a
    /// hover or a choice.
    public func showsName(of kind: GraphNode.Kind, atScale scale: Double) -> Bool {
        nameOpacity(of: kind, atScale: scale) > 0
    }
}
