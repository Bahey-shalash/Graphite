import CoreGraphics

/// The boxes of a flowchart's groups grouped by how they are painted, Pele's way: each box filled with the alternate
/// surface at half its opacity, one depth after another so that a box inside another is darker, the outlines in the
/// border color, and the titles in the muted color. A title an edge runs through is painted over the edges instead,
/// on a patch of its box's color: the background and, for each box it is inside and its own, the alternate surface at
/// half its opacity again.
public struct FlowchartClusterDrawingParts {
    /// The boxes at each depth, the top level first, each filled with the alternate surface at `fillOpacity`.
    public let fillsByDepth: [CGPath]
    /// The boxes' outlines, stroked one point wide in the border color.
    public let outlines: CGPath
    /// The titles no edge runs through, painted with the boxes.
    public let titles: [DiagramTextBlock]
    /// The patches behind the titles edges run through, by the depth of their box: painted after the edges, filled with
    /// the background and then `depth + 1` times with the alternate surface at `fillOpacity`.
    public let crossedTitlePatchesByDepth: [CGPath]
    /// The titles edges run through, painted on their patches.
    public let crossedTitles: [DiagramTextBlock]

    /// How much of the alternate surface a box shows over what is behind it: Pele's.
    public static let fillOpacity: CGFloat = 0.5
    /// How far the patch behind a crossed title reaches beyond its text, as Pele's outline around the letters does.
    static let crossedTitlePatchMargin: CGFloat = 2.5

    init(clusters: [FlowchartLayoutCluster]) {
        let depthCount = (clusters.map(\.depth).max() ?? -1) + 1
        let fills = (0..<depthCount).map { _ in CGMutablePath() }
        let patches = (0..<depthCount).map { _ in CGMutablePath() }
        let outlines = CGMutablePath()
        var titles: [DiagramTextBlock] = []
        var crossedTitles: [DiagramTextBlock] = []
        for cluster in clusters {
            let box = CGPath(roundedRect: cluster.frame, cornerWidth: FlowchartShapeDrawing.rectangleCornerRadius,
                             cornerHeight: FlowchartShapeDrawing.rectangleCornerRadius, transform: nil)
            fills[cluster.depth].addPath(box)
            outlines.addPath(box)
            guard let title = cluster.title else { continue }
            guard cluster.isTitleCrossed else {
                titles.append(title)
                continue
            }
            crossedTitles.append(title)
            patches[cluster.depth].addPath(CGPath(roundedRect: title.frame.insetBy(dx: -Self.crossedTitlePatchMargin, dy: 0),
                                                  cornerWidth: FlowchartDrawingParts.edgeTextPatchCornerRadius,
                                                  cornerHeight: FlowchartDrawingParts.edgeTextPatchCornerRadius, transform: nil))
        }
        fillsByDepth = fills
        self.outlines = outlines
        self.titles = titles
        crossedTitlePatchesByDepth = patches
        self.crossedTitles = crossedTitles
    }
}
