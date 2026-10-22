import SwiftUI
import GraphiteCore

/// How the graph is drawn, as the person's settings and the theme choose it.
struct GraphCanvasLook {
    let display: GraphDisplayOptions
    let palette: GraphPalette
    let accent: Color
    let groupColoring: GraphGroupColoring
    let showsArrows: Bool
    /// Names beside every node rather than from a zoom; for small graphs.
    let alwaysShowsNames: Bool
}

/// Draws one frame of the graph from the values the canvas hands it: the links, the nodes,
/// the open note's halo, the names and the arrows. It is made for each frame and keeps
/// nothing; the only thing it remembers across frames is the names' sizes, in the model.
@MainActor
struct GraphCanvasRenderer {
    let model: GraphCanvasModel
    let viewport: GraphViewport
    let emphasis: GraphEmphasis
    let look: GraphCanvasLook

    private static let arrowOpacity = 0.6
    /// An arrow's length and its half width as a share of it, in points.
    private static let arrowLengthPoints = 5.0
    private static let arrowHalfWidthRatio = 0.6
    /// The links of the focused node, in the accent at this strength.
    private static let focusedLinkOpacity = 0.8
    /// A node that steps back keeps this much of its color.
    private static let dimmedNodeOpacity = 0.25
    /// A name drawn in full, and one whose node steps back.
    private static let nameOpacity = 0.85
    private static let dimmedNameOpacity = 0.4
    /// A link target without a file is a dashed ring of this width, with dashes this long.
    private static let hollowNodeLinePoints = 1.5
    private static let hollowNodeDashPoints = 2.5
    /// The open note's ring sits this far outside the node.
    private static let haloRingGapPoints = 3.0
    /// Far out, where a node is a dot, the ring keeps this radius.
    private static let smallestHaloRingRadiusPoints = 9.0
    /// The glow reaches this far beyond the ring.
    private static let haloGlowReachPoints = 7.0
    private static let haloRingWidthPoints = 1.5
    private static let haloRingOpacity = 0.7
    /// The glow's strength at the node's edge, fading to nothing at its rim.
    private static let haloGlowOpacity = 0.35
    /// Nodes this far outside the view are still drawn, so a node and its name slide in whole.
    private static let offScreenMarginPoints = 40.0
    /// The room between a node and its name.
    private static let nameGapPoints = 2.0
    /// The room a name keeps around it, which no other name may take.
    private static let nameMarginPoints = 2.0
    private static let namePoints = 11.0
    /// The open note's name is a little larger and bold.
    private static let openNoteNamePoints = 12.0

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let positions = model.positions
        guard positions.count == model.graph.nodes.count, !positions.isEmpty else { return }
        let points = positions.map { position in viewport.screenPoint(position, in: size) }
        drawLinks(in: &context, points: points)
        if look.showsArrows { drawArrows(in: &context, points: points) }
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -Self.offScreenMarginPoints, dy: -Self.offScreenMarginPoints)
        let visibleIndexes = points.indices.filter { index in visible.contains(points[index]) }
        // The open note goes last, over its halo and over the nodes around it.
        let openIndex = emphasis.openIndex.flatMap { openIndex in visibleIndexes.contains(openIndex) ? openIndex : nil }
        for index in visibleIndexes where index != openIndex {
            drawNode(at: index, in: &context, points: points)
        }
        if let openIndex {
            drawHalo(in: &context, at: points[openIndex], nodeRadius: screenRadius(ofNodeAt: openIndex))
            drawNode(at: openIndex, in: &context, points: points)
        }
        drawNames(in: &context, points: points, indexes: visibleIndexes)
    }

    /// The open note's ring, just outside the node, and its glow, which reaches beyond the
    /// ring; both keep a size that can be seen when the node is a dot.
    static func haloRadii(ofNodeRadius nodeRadius: Double) -> (ring: Double, glow: Double) {
        let ring = max(nodeRadius + haloRingGapPoints, smallestHaloRingRadiusPoints)
        return (ring, ring + haloGlowReachPoints)
    }

    private func screenRadius(ofNodeAt index: Int) -> Double {
        model.screenRadius(ofNodeAt: index, in: viewport, display: look.display)
    }

    private func drawLinks(in context: inout GraphicsContext, points: [CGPoint]) {
        var links = Path()
        var focusedLinks = Path()
        for edge in model.edgeIndexes {
            if emphasis.isFocusedLink(source: edge.source, target: edge.target) {
                focusedLinks.move(to: points[edge.source]); focusedLinks.addLine(to: points[edge.target])
            } else {
                links.move(to: points[edge.source]); links.addLine(to: points[edge.target])
            }
        }
        let thickness = look.display.linkThicknessMultiplier
        let linkColor = emphasis.focusedIndex == nil ? look.palette.link : look.palette.dimmedLink
        context.stroke(links, with: .color(Color(NoteThemeStyle.platformColor(linkColor))), lineWidth: viewport.linkWidth(isFocused: false) * thickness)
        context.stroke(focusedLinks, with: .color(look.accent.opacity(Self.focusedLinkOpacity)), lineWidth: viewport.linkWidth(isFocused: true) * thickness)
    }

    private func drawNode(at index: Int, in context: inout GraphicsContext, points: [CGPoint]) {
        let radius = screenRadius(ofNodeAt: index)
        let circle = Path(ellipseIn: CGRect(x: points[index].x - radius, y: points[index].y - radius, width: radius * 2, height: radius * 2))
        let color = nodeColor(at: index).opacity(emphasis.isDimmed(index) ? Self.dimmedNodeOpacity : 1)
        if GraphPalette.isDrawnHollow(model.graph.nodes[index].kind) {
            context.stroke(circle, with: .color(color),
                           style: StrokeStyle(lineWidth: Self.hollowNodeLinePoints, dash: [Self.hollowNodeDashPoints, Self.hollowNodeDashPoints]))
        } else {
            context.fill(circle, with: .color(color))
        }
    }

    /// The accent for the open or focused node, else the color of the group that colors it,
    /// else its kind's in the palette.
    private func nodeColor(at index: Int) -> Color {
        if emphasis.isAccented(index) { return look.accent }
        if let groupIndex = model.groupIndexes[index], let groupColor = look.groupColoring.color(ofGroup: groupIndex) { return groupColor }
        return Color(NoteThemeStyle.platformColor(look.palette.color(of: model.graph.nodes[index].kind)))
    }

    /// A soft glow and a ring in the accent around the open note, never smaller than a
    /// finger's tip, so the note can be found in a vault of thousands.
    private func drawHalo(in context: inout GraphicsContext, at point: CGPoint, nodeRadius: Double) {
        let halo = Self.haloRadii(ofNodeRadius: nodeRadius)
        func circle(_ radius: Double) -> Path { Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)) }
        context.fill(circle(halo.glow), with: .radialGradient(Gradient(colors: [look.accent.opacity(Self.haloGlowOpacity), look.accent.opacity(0)]),
                                                              center: point, startRadius: nodeRadius, endRadius: halo.glow))
        context.stroke(circle(halo.ring), with: .color(look.accent.opacity(Self.haloRingOpacity)), lineWidth: Self.haloRingWidthPoints)
    }

    /// The names at this zoom, over the nodes: fading in as the zoom nears the name zoom, and
    /// whole for the open note, the focused node and its neighbors. A name that would cover
    /// one placed before it is left out at this zoom (`GraphNamePlacement`).
    private func drawNames(in context: inout GraphicsContext, points: [CGPoint], indexes: [Int]) {
        var candidates: [GraphNamePlacement.Candidate] = []
        var opacities: [Int: Double] = [:]
        for index in indexes {
            let importance = emphasis.nameImportance(ofNodeAt: index)
            let zoomOpacity = look.alwaysShowsNames ? 1 : look.display.nameOpacity(of: model.graph.nodes[index].kind, atScale: viewport.scale)
            guard importance > 0 || zoomOpacity > 0 else { continue }
            let nameSize = measuredNameSize(at: index, isOpenNote: index == emphasis.openIndex, in: context)
            let top = nameTop(at: index, points: points)
            let frame = CGRect(x: top.x - nameSize.width / 2, y: top.y, width: nameSize.width, height: nameSize.height)
            candidates.append(GraphNamePlacement.Candidate(nodeIndex: index, frame: frame.insetBy(dx: -Self.nameMarginPoints, dy: -Self.nameMarginPoints),
                                                           importance: importance, nodeRadius: screenRadius(ofNodeAt: index)))
            opacities[index] = importance > 0 ? 1 : zoomOpacity
        }
        for index in GraphNamePlacement.placedNames(candidates) {
            let color = emphasis.isDimmed(index) ? Color.secondary.opacity(Self.dimmedNameOpacity) : Color.primary.opacity(Self.nameOpacity)
            let name = nameText(of: index, isOpenNote: index == emphasis.openIndex).foregroundStyle(color.opacity(opacities[index] ?? 1))
            context.draw(name, at: nameTop(at: index, points: points), anchor: .top)
        }
    }

    /// Where a node's name is drawn: centered under it.
    private func nameTop(at index: Int, points: [CGPoint]) -> CGPoint {
        CGPoint(x: points[index].x, y: points[index].y + screenRadius(ofNodeAt: index) + Self.nameGapPoints)
    }

    /// A node's name; a link target without a file is named in italics, as it is not a note.
    private func nameText(of index: Int, isOpenNote: Bool) -> Text {
        let node = model.graph.nodes[index]
        return Text(node.title)
            .font(.system(size: isOpenNote ? Self.openNoteNamePoints : Self.namePoints, weight: isOpenNote ? .semibold : .regular))
            .italic(GraphPalette.isDrawnHollow(node.kind))
    }

    /// A name's size: measured once at the names' font, the open note's at its own.
    private func measuredNameSize(at index: Int, isOpenNote: Bool, in context: GraphicsContext) -> CGSize {
        let unbounded = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        guard !isOpenNote else { return context.resolve(nameText(of: index, isOpenNote: true)).measure(in: unbounded) }
        return model.nameSize(ofNodeAt: index) { context.resolve(nameText(of: index, isOpenNote: false)).measure(in: unbounded) }
    }

    private func drawArrows(in context: inout GraphicsContext, points: [CGPoint]) {
        var arrows = Path()
        let length = Self.arrowLengthPoints, halfWidth = Self.arrowLengthPoints * Self.arrowHalfWidthRatio
        for edge in model.edgeIndexes {
            let start = points[edge.source], end = points[edge.target]
            let distance = hypot(end.x - start.x, end.y - start.y)
            guard distance > 1 else { continue }
            let direction = CGPoint(x: (end.x - start.x) / distance, y: (end.y - start.y) / distance)
            let targetRadius = screenRadius(ofNodeAt: edge.target)
            let tip = CGPoint(x: end.x - direction.x * targetRadius, y: end.y - direction.y * targetRadius)
            arrows.move(to: tip)
            arrows.addLine(to: CGPoint(x: tip.x - direction.x * length - direction.y * halfWidth, y: tip.y - direction.y * length + direction.x * halfWidth))
            arrows.addLine(to: CGPoint(x: tip.x - direction.x * length + direction.y * halfWidth, y: tip.y - direction.y * length - direction.x * halfWidth))
            arrows.closeSubpath()
        }
        context.fill(arrows, with: .color(Color(NoteThemeStyle.platformColor(look.palette.note)).opacity(Self.arrowOpacity)))
    }
}
