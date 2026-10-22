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
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    /// From this zoom on, every note shows its name.
    private static let labelScale = 1.4
    /// Tags are fewer and gather notes, so their names show from further out.
    private static let tagLabelScale = 0.7

    /// Whether a node of this kind shows its name at this zoom, without a hover or a choice.
    static func showsName(of kind: GraphNode.Kind, atScale scale: Double) -> Bool {
        scale >= nameScale(of: kind)
    }

    /// The zoom from which a node of this kind shows its name.
    private static func nameScale(of kind: GraphNode.Kind) -> Double {
        kind == .tag ? tagLabelScale : labelScale
    }

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
        let scale = viewport.scale
        let points = positions.map { position in viewport.screenPoint(position, in: size) }
        let focused = focusedIndex
        let highlighted = highlightedIdentifier.flatMap(model.index(of:))
        let lineColor = colorScheme == .dark ? Color.white : Color.black

        var links = Path()
        var focusedLinks = Path()
        for edge in model.edgeIndexes {
            if edge.source == focused || edge.target == focused {
                focusedLinks.move(to: points[edge.source]); focusedLinks.addLine(to: points[edge.target])
            } else {
                links.move(to: points[edge.source]); links.addLine(to: points[edge.target])
            }
        }
        context.stroke(links, with: .color(lineColor.opacity(focused == nil ? 0.18 : 0.08)), lineWidth: max(0.5, min(1.2, scale)))
        context.stroke(focusedLinks, with: .color(accent.opacity(0.8)), lineWidth: max(1, min(2, scale * 1.5)))
        if showsArrows { drawArrows(in: &context, points: points) }

        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40)
        for index in points.indices where visible.contains(points[index]) {
            let node = model.graph.nodes[index]
            let isNeighborOfFocused = focused.map { focusedIndex in model.neighborIndexes[focusedIndex].contains(index) } ?? false
            let isFaded = focused != nil && focused != index && !isNeighborOfFocused
            let radius = model.radii[index] * max(0.5, min(scale, 2))
            let circle = Path(ellipseIn: CGRect(x: points[index].x - radius, y: points[index].y - radius, width: radius * 2, height: radius * 2))
            let color = nodeColor(at: index, isHighlighted: index == highlighted || index == focused)
            if node.kind == .unresolved {
                context.stroke(circle, with: .color(color.opacity(isFaded ? 0.2 : 0.6)), lineWidth: 1.2)
            } else {
                context.fill(circle, with: .color(color.opacity(isFaded ? 0.25 : 1)))
            }
            let showsNameFromZoom = alwaysShowsLabels || Self.showsName(of: node.kind, atScale: scale)
            guard showsNameFromZoom || index == highlighted || index == focused || isNeighborOfFocused else { continue }
            let label = Text(node.title).font(.system(size: index == highlighted ? 12 : 11, weight: index == highlighted ? .semibold : .regular))
                .foregroundStyle(isFaded ? Color.secondary.opacity(0.4) : Color.primary.opacity(0.85))
            context.draw(label, at: CGPoint(x: points[index].x, y: points[index].y + radius + 2), anchor: .top)
        }
    }

    private func drawArrows(in context: inout GraphicsContext, points: [CGPoint]) {
        let scale = viewport.scale
        var arrows = Path()
        for edge in model.edgeIndexes {
            let start = points[edge.source], end = points[edge.target]
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 1 else { continue }
            let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
            let tip = CGPoint(x: end.x - direction.x * model.radii[edge.target] * max(0.5, min(scale, 2)), y: end.y - direction.y * model.radii[edge.target] * max(0.5, min(scale, 2)))
            let size = 5.0
            arrows.move(to: tip)
            arrows.addLine(to: CGPoint(x: tip.x - direction.x * size - direction.y * size * 0.6, y: tip.y - direction.y * size + direction.x * size * 0.6))
            arrows.addLine(to: CGPoint(x: tip.x - direction.x * size + direction.y * size * 0.6, y: tip.y - direction.y * size - direction.x * size * 0.6))
            arrows.closeSubpath()
        }
        context.fill(arrows, with: .color(.secondary.opacity(0.5)))
    }

    /// The accent for the open or focused node, else the color of the group that colors it,
    /// else its kind's.
    private func nodeColor(at index: Int, isHighlighted: Bool) -> Color {
        if isHighlighted { return accent }
        if let groupIndex = model.groupIndexes[index], let groupColor = groupColoring.color(ofGroup: groupIndex) { return groupColor }
        switch model.graph.nodes[index].kind {
        case .note: return Color.secondary
        case .attachment: return Color(red: 0.85, green: 0.62, blue: 0.12)
        case .tag: return Color(red: 0.25, green: 0.65, blue: 0.35)
        case .unresolved: return Color.secondary
        }
    }

    // MARK: Interaction

    private func nodeIndex(at location: CGPoint, in size: CGSize) -> Int? {
        let scale = viewport.scale
        var best: (index: Int, distance: Double)?
        for index in model.positions.indices where index < model.radii.count {
            let point = viewport.screenPoint(model.positions[index], in: size)
            let distance = hypot(point.x - location.x, point.y - location.y)
            // A finger needs room: at least 22 points around small nodes.
            let reach = max(model.radii[index] * max(0.5, min(scale, 2)) + 6, 22)
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
        centered.center(on: model.positions[index], zoomingInTo: Self.labelScale)
        show(centered, animated: animated)
    }

    /// Shows the whole graph, names included, at most a little larger than its natural size.
    private func fit(in size: CGSize, animated: Bool) {
        let names = model.graph.nodes.map { node in
            GraphViewport.NameRoom(characterCount: node.title.count, shownFromScale: alwaysShowsLabels ? 0 : Self.nameScale(of: node.kind))
        }
        guard let fitted = GraphViewport.fitting(model.positions, names: names, in: size) else { return }
        show(fitted, animated: animated)
    }

    private func show(_ newViewport: GraphViewport, animated: Bool) {
        if animated { withAnimation(GraphiteMotion.animation(.snappy)) { viewport = newViewport } } else { viewport = newViewport }
    }
}
