import SwiftUI
import GraphiteCore

/// A graph drawn with its links, as Obsidian's graph view: drag to move around, pinch to
/// zoom, drag a node to move it, tap one to open it.
struct GraphCanvas: View {
    let graph: LinkGraph
    /// The note shown in the editor, drawn in the accent color.
    var highlightedIdentifier: String?
    var forces = GraphLayout.Forces()
    var showsArrows = false
    /// Names beside every node rather than only when zoomed in; for small graphs.
    var alwaysShowsLabels = false
    var previousPositions: [String: SIMD2<Double>] = [:]
    let open: (GraphNode) -> Void
    /// Called when the view goes, with where the nodes were.
    var keepPositions: (([String: SIMD2<Double>]) -> Void)?
    /// Changing it shows the whole graph again.
    var fitRequest = 0
    /// A node to center on, as when the local graph opens the whole graph; a new request
    /// centers on its node again.
    var centerRequest: GraphCenterRequest?
    /// A tag chosen with a tap: it and its notes stay bright, and their names show, until it
    /// is chosen again or the person taps beside the nodes. The owner keeps it, so it stays
    /// when the graph's tab comes back to the front.
    var chosenTag: Binding<String?> = .constant(nil)
    /// The colors the vault's groups give its files.
    var groupColoring = GraphGroupColoring()
    /// The node size, link thickness and zoom from which names show.
    var display = GraphDisplayOptions()

    @State private var model = GraphCanvasModel()
    @State private var viewport = GraphViewport()
    @State private var gestureStartScale: Double?
    @State private var gestureStartViewport: GraphViewport?
    @State private var draggedIdentifier: String?
    @State private var hoveredIndex: Int?
    /// What the view keeps in sight while the layout settles. Once the person moves or
    /// zooms, the view no longer follows the layout.
    @State private var framing = Framing.allNodes

    private enum Framing: Equatable {
        case allNodes
        case node(String)
        case free
    }
    private static let arrowOpacity = 0.6
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
    /// A touch this far outside a node still takes it.
    private static let nodeReachMarginPoints = 6.0
    /// A finger needs room: a touch this close to a small node's center takes it.
    private static let minimumFingerReachPoints = 22.0
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in draw(in: &context, size: size) }
                .contentShape(Rectangle())
                .gesture(dragGesture(in: geometry.size))
                .simultaneousGesture(magnifyGesture(in: geometry.size))
                .onTapGesture { location in
                    switch model.tap(nodeAt: nodeIndex(at: location, in: geometry.size), chosenTag: chosenTag.wrappedValue) {
                    case .open(let node): open(node)
                    case .choose(let tag): chosenTag.wrappedValue = tag
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hoveredIndex = nodeIndex(at: location, in: geometry.size)
                    case .ended: hoveredIndex = nil
                    }
                }
                .onChange(of: model.positions) { followLayout(in: geometry.size) }
                .onChange(of: geometry.size) { followLayout(in: geometry.size) }
                .onChange(of: fitRequest) {
                    framing = .allNodes
                    fit(in: geometry.size, animated: !GraphiteMotion.isReduced)
                }
                .onChange(of: centerRequest) {
                    guard let centerRequest else { return }
                    framing = .node(centerRequest.identifier)
                    center(on: centerRequest.identifier, in: geometry.size, animated: !GraphiteMotion.isReduced)
                }
        }
        .clipped()
        .task(id: graph) {
            // Other nodes, as after a filter changes: show them all again, or the node asked for.
            framing = centerRequest.map { request in Framing.node(request.identifier) } ?? .allNodes
            model.load(graph, forces: forces, previousPositions: previousPositions.isEmpty ? model.positionsByIdentifier : previousPositions,
                       groupIndexByIdentifier: groupColoring.groupIndexByIdentifier)
        }
        .onChange(of: forces) { model.change(forces: forces) }
        .onChange(of: groupColoring) { model.colorNodes(by: groupColoring.groupIndexByIdentifier) }
        .onDisappear {
            keepPositions?(model.positionsByIdentifier)
            model.stop()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Graph of \(model.counts.summary)")
        .accessibilityChildren {
            ForEach(graph.nodes) { node in
                Button(node.title) { open(node) }
            }
        }
    }

    // MARK: Drawing

    /// The node the drag or hover is on, else the chosen tag, whose links stand out.
    private var focusedIndex: Int? {
        draggedIdentifier.flatMap(model.index(of:)) ?? hoveredIndex ?? chosenTag.wrappedValue.flatMap(model.index(of:))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let positions = model.positions
        guard positions.count == model.graph.nodes.count, !positions.isEmpty else { return }
        let points = positions.map { position in viewport.screenPoint(position, in: size) }
        let emphasis = GraphEmphasis(focusedIndex: focusedIndex, openIndex: highlightedIdentifier.flatMap(model.index(of:)),
                                     neighborIndexes: model.neighborIndexes)
        let palette = palette(in: context.environment)
        drawLinks(in: &context, points: points, emphasis: emphasis, palette: palette)
        if showsArrows { drawArrows(in: &context, points: points, palette: palette) }
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -Self.offScreenMarginPoints, dy: -Self.offScreenMarginPoints)
        let visibleIndexes = points.indices.filter { index in visible.contains(points[index]) }
        // The open note goes last, over its halo and over the nodes around it.
        let openIndex = emphasis.openIndex.flatMap { openIndex in visibleIndexes.contains(openIndex) ? openIndex : nil }
        for index in visibleIndexes where index != openIndex {
            drawNode(at: index, in: &context, points: points, emphasis: emphasis, palette: palette)
        }
        if let openIndex {
            drawHalo(in: &context, at: points[openIndex], nodeRadius: screenRadius(ofNodeAt: openIndex))
            drawNode(at: openIndex, in: &context, points: points, emphasis: emphasis, palette: palette)
        }
        drawNames(in: &context, points: points, indexes: visibleIndexes, emphasis: emphasis)
    }

    private func drawNode(at index: Int, in context: inout GraphicsContext, points: [CGPoint], emphasis: GraphEmphasis, palette: GraphPalette) {
        let radius = screenRadius(ofNodeAt: index)
        let circle = Path(ellipseIn: CGRect(x: points[index].x - radius, y: points[index].y - radius, width: radius * 2, height: radius * 2))
        let color = nodeColor(at: index, isHighlighted: emphasis.isAccented(index), palette: palette)
        let isFaded = emphasis.isDimmed(index)
        if GraphPalette.isDrawnHollow(model.graph.nodes[index].kind) {
            context.stroke(circle, with: .color(color.opacity(isFaded ? 0.25 : 1)),
                           style: StrokeStyle(lineWidth: Self.hollowNodeLinePoints, dash: [Self.hollowNodeDashPoints, Self.hollowNodeDashPoints]))
        } else {
            context.fill(circle, with: .color(color.opacity(isFaded ? 0.25 : 1)))
        }
    }

    /// The graph's colors for this appearance, against the accent as it is drawn here.
    private func palette(in environment: EnvironmentValues) -> GraphPalette {
        let resolvedAccent = accent.resolve(in: environment)
        let accentColor = ThemeColor(red: Double(resolvedAccent.red), green: Double(resolvedAccent.green), blue: Double(resolvedAccent.blue))
        return GraphPalette(appearance: colorScheme == .dark ? .dark : .light, accent: accentColor)
    }

    /// A soft glow and a ring in the accent around the open note, never smaller than a
    /// finger's tip, so the note can be found in a vault of thousands.
    private func drawHalo(in context: inout GraphicsContext, at point: CGPoint, nodeRadius: Double) {
        let halo = Self.haloRadii(ofNodeRadius: nodeRadius)
        func circle(_ radius: Double) -> Path { Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)) }
        context.fill(circle(halo.glow), with: .radialGradient(Gradient(colors: [accent.opacity(Self.haloGlowOpacity), accent.opacity(0)]),
                                                              center: point, startRadius: nodeRadius, endRadius: halo.glow))
        context.stroke(circle(halo.ring), with: .color(accent.opacity(Self.haloRingOpacity)), lineWidth: Self.haloRingWidthPoints)
    }

    /// The open note's ring, just outside the node, and its glow, which reaches beyond the
    /// ring; both keep a size that can be seen when the node is a dot.
    static func haloRadii(ofNodeRadius nodeRadius: Double) -> (ring: Double, glow: Double) {
        let ring = max(nodeRadius + haloRingGapPoints, smallestHaloRingRadiusPoints)
        return (ring, ring + haloGlowReachPoints)
    }

    private func drawLinks(in context: inout GraphicsContext, points: [CGPoint], emphasis: GraphEmphasis, palette: GraphPalette) {
        var links = Path()
        var focusedLinks = Path()
        for edge in model.edgeIndexes {
            if emphasis.isFocusedLink(source: edge.source, target: edge.target) {
                focusedLinks.move(to: points[edge.source]); focusedLinks.addLine(to: points[edge.target])
            } else {
                links.move(to: points[edge.source]); links.addLine(to: points[edge.target])
            }
        }
        let linkColor = emphasis.focusedIndex == nil ? palette.link : palette.dimmedLink
        context.stroke(links, with: .color(Color(NoteThemeStyle.platformColor(linkColor))), lineWidth: viewport.linkWidth(isFocused: false) * display.linkThicknessMultiplier)
        context.stroke(focusedLinks, with: .color(accent.opacity(0.8)), lineWidth: viewport.linkWidth(isFocused: true) * display.linkThicknessMultiplier)
    }

    /// The names at this zoom, over the nodes: fading in as the zoom nears the name zoom, and
    /// whole for the open note, the focused node and its neighbors. A name that would cover
    /// one placed before it is left out at this zoom (`GraphNamePlacement`).
    private func drawNames(in context: inout GraphicsContext, points: [CGPoint], indexes: [Int], emphasis: GraphEmphasis) {
        var candidates: [GraphNamePlacement.Candidate] = []
        var opacities: [Int: Double] = [:]
        for index in indexes {
            let importance = emphasis.nameImportance(ofNodeAt: index)
            let zoomOpacity = alwaysShowsLabels ? 1 : display.nameOpacity(of: model.graph.nodes[index].kind, atScale: viewport.scale)
            guard importance > 0 || zoomOpacity > 0 else { continue }
            let nameSize = measuredNameSize(at: index, isOpenNote: index == emphasis.openIndex, in: context)
            let top = nameTop(at: index, points: points)
            let frame = CGRect(x: top.x - nameSize.width / 2, y: top.y, width: nameSize.width, height: nameSize.height)
            candidates.append(GraphNamePlacement.Candidate(nodeIndex: index, frame: frame.insetBy(dx: -Self.nameMarginPoints, dy: -Self.nameMarginPoints),
                                                           importance: importance, nodeRadius: screenRadius(ofNodeAt: index)))
            opacities[index] = importance > 0 ? 1 : zoomOpacity
        }
        for index in GraphNamePlacement.placedNames(candidates) {
            let color = emphasis.isDimmed(index) ? Color.secondary.opacity(0.4) : Color.primary.opacity(0.85)
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

    /// A node's radius on screen: its size from its links, the person's node size and the zoom.
    private func screenRadius(ofNodeAt index: Int) -> Double {
        viewport.screenRadius(ofNodeRadius: model.radii[index] * display.nodeSizeMultiplier)
    }

    private func drawArrows(in context: inout GraphicsContext, points: [CGPoint], palette: GraphPalette) {
        var arrows = Path()
        for edge in model.edgeIndexes {
            let start = points[edge.source], end = points[edge.target]
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 1 else { continue }
            let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
            let targetRadius = screenRadius(ofNodeAt: edge.target)
            let tip = CGPoint(x: end.x - direction.x * targetRadius, y: end.y - direction.y * targetRadius)
            let size = 5.0
            arrows.move(to: tip)
            arrows.addLine(to: CGPoint(x: tip.x - direction.x * size - direction.y * size * 0.6, y: tip.y - direction.y * size + direction.x * size * 0.6))
            arrows.addLine(to: CGPoint(x: tip.x - direction.x * size + direction.y * size * 0.6, y: tip.y - direction.y * size - direction.x * size * 0.6))
            arrows.closeSubpath()
        }
        context.fill(arrows, with: .color(Color(NoteThemeStyle.platformColor(palette.note)).opacity(Self.arrowOpacity)))
    }

    /// The accent for the open or focused node, else the color of the group that colors it,
    /// else its kind's in the palette.
    private func nodeColor(at index: Int, isHighlighted: Bool, palette: GraphPalette) -> Color {
        if isHighlighted { return accent }
        if let groupIndex = model.groupIndexes[index], let groupColor = groupColoring.color(ofGroup: groupIndex) { return groupColor }
        return Color(NoteThemeStyle.platformColor(palette.color(of: model.graph.nodes[index].kind)))
    }

    // MARK: Interaction

    private func nodeIndex(at location: CGPoint, in size: CGSize) -> Int? {
        var best: (index: Int, distance: Double)?
        for index in model.positions.indices where index < model.radii.count {
            let point = viewport.screenPoint(model.positions[index], in: size)
            let distance = hypot(point.x - location.x, point.y - location.y)
            let reach = max(screenRadius(ofNodeAt: index) + Self.nodeReachMarginPoints, Self.minimumFingerReachPoints)
            if distance <= reach, distance < (best?.distance ?? .infinity) { best = (index, distance) }
        }
        return best?.index
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggedIdentifier == nil, gestureStartViewport == nil {
                    if let index = nodeIndex(at: value.startLocation, in: size) {
                        draggedIdentifier = model.graph.nodes[index].id
                        // Fitting while dragging would move the graph under the finger.
                        framing = .free
                    } else {
                        gestureStartViewport = viewport
                        framing = .free
                    }
                }
                if let draggedIdentifier {
                    model.pin(draggedIdentifier, at: viewport.graphPosition(value.location, in: size))
                } else if let gestureStartViewport {
                    var moved = gestureStartViewport
                    moved.move(by: SIMD2(value.translation.width, value.translation.height))
                    viewport = moved
                }
            }
            .onEnded { _ in
                if let draggedIdentifier { model.unpin(draggedIdentifier) }
                draggedIdentifier = nil
                gestureStartViewport = nil
            }
    }

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if gestureStartScale == nil {
                    gestureStartScale = viewport.scale
                    framing = .free
                }
                guard let startScale = gestureStartScale else { return }
                // Zooms around the fingers: the point under them stays put.
                viewport.zoom(to: startScale * value.magnification, keepingInPlace: value.startLocation, in: size)
            }
            .onEnded { _ in gestureStartScale = nil }
    }

    /// Keeps what the view follows in sight as the nodes move or the view changes size.
    private func followLayout(in size: CGSize) {
        switch framing {
        case .allNodes: fit(in: size, animated: false)
        case .node(let identifier): center(on: identifier, in: size, animated: false)
        case .free: break
        }
    }

    /// Puts a node in the middle, zoomed in far enough for names to show.
    private func center(on identifier: String, in size: CGSize, animated: Bool) {
        guard size.width > 0, size.height > 0, let index = model.index(of: identifier), model.positions.indices.contains(index) else { return }
        var centered = viewport
        centered.center(on: model.positions[index], zoomingInTo: display.nameScale(of: .note))
        show(centered, animated: animated)
    }

    /// Shows the whole graph, names included, at most a little larger than its natural size.
    private func fit(in size: CGSize, animated: Bool) {
        let names = model.graph.nodes.map { node in
            GraphViewport.NameRoom(characterCount: node.title.count, shownFromScale: alwaysShowsLabels ? 0 : display.nameFadeStartScale(of: node.kind))
        }
        guard let fitted = GraphViewport.fitting(model.positions, names: names, in: size) else { return }
        show(fitted, animated: animated)
    }

    private func show(_ newViewport: GraphViewport, animated: Bool) {
        if animated { withAnimation(GraphiteMotion.animation(.snappy)) { viewport = newViewport } } else { viewport = newViewport }
    }
}
