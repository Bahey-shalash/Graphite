import SwiftUI
import GraphiteCore

/// Runs a graph layout away from the main thread. Dragging a node goes through it too, so
/// a pin never races a step.
actor GraphSimulator {
    private var layout: GraphLayout

    init(layout: GraphLayout) {
        self.layout = layout
    }

    func advance(steps: Int) -> (positions: [SIMD2<Double>], isSettled: Bool) {
        for _ in 0..<steps where !layout.isSettled { layout.step() }
        return (layout.positions, layout.isSettled)
    }

    func pin(_ identifier: String, at position: SIMD2<Double>) {
        layout.pin(identifier, at: position)
        layout.reheat(to: 0.3)
    }

    func unpin(_ identifier: String) {
        layout.unpin(identifier)
    }

    func change(forces: GraphLayout.Forces) {
        layout.forces = forces
        layout.reheat(to: 0.5)
    }

    var positionsByIdentifier: [String: SIMD2<Double>] { layout.positionsByIdentifier }
}

/// The nodes on screen and where they are, updated as the layout settles.
@MainActor @Observable
final class GraphCanvasModel {
    private(set) var graph = LinkGraph(nodes: [], edges: [])
    private(set) var positions: [SIMD2<Double>] = []
    /// Each edge as the indexes of its nodes.
    private(set) var edgeIndexes: [(source: Int, target: Int)] = []
    private(set) var radii: [Double] = []
    private(set) var neighborIndexes: [Set<Int>] = []
    private(set) var isSettled = true
    @ObservationIgnored private var indexByIdentifier: [String: Int] = [:]
    @ObservationIgnored private var simulator: GraphSimulator?
    @ObservationIgnored private var runTask: Task<Void, Never>?

    func load(_ graph: LinkGraph, forces: GraphLayout.Forces, previousPositions: [String: SIMD2<Double>]) {
        runTask?.cancel()
        runTask = nil
        let layout = GraphLayout(graph: graph, forces: forces, previousPositions: previousPositions)
        self.graph = graph
        positions = layout.positions
        indexByIdentifier = Dictionary(uniqueKeysWithValues: layout.identifiers.enumerated().map { index, identifier in (identifier, index) })
        edgeIndexes = graph.edges.compactMap { edge in
            guard let source = indexByIdentifier[edge.source], let target = indexByIdentifier[edge.target] else { return nil }
            return (source, target)
        }
        var neighbors = Array(repeating: Set<Int>(), count: graph.nodes.count)
        for edge in edgeIndexes {
            neighbors[edge.source].insert(edge.target)
            neighbors[edge.target].insert(edge.source)
        }
        neighborIndexes = neighbors
        let linkCounts = graph.linkCounts
        // Obsidian draws well-linked notes larger.
        radii = graph.nodes.map { node in 4 + min(Double(linkCounts[node.id] ?? 0).squareRoot(), 8) * 1.3 }
        simulator = GraphSimulator(layout: layout)
        run()
    }

    func index(of identifier: String) -> Int? { indexByIdentifier[identifier] }

    func pin(_ identifier: String, at position: SIMD2<Double>) {
        guard let simulator else { return }
        if let index = indexByIdentifier[identifier] { positions[index] = position }
        Task {
            await simulator.pin(identifier, at: position)
            run()
        }
    }

    func unpin(_ identifier: String) {
        guard let simulator else { return }
        Task { await simulator.unpin(identifier) }
    }

    func change(forces: GraphLayout.Forces) {
        guard let simulator else { return }
        Task {
            await simulator.change(forces: forces)
            run()
        }
    }

    var positionsByIdentifier: [String: SIMD2<Double>] {
        Dictionary(uniqueKeysWithValues: graph.nodes.indices.map { index in (graph.nodes[index].id, positions[index]) })
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
    }

    private func run() {
        guard runTask == nil || isSettled, let simulator else { return }
        isSettled = false
        // Two steps a frame settle a graph in about three seconds; a large one takes longer
        // per step, so it is drawn less often.
        let stepsPerUpdate = graph.nodes.count > 3_000 ? 8 : 2
        runTask = Task { [weak self] in
            while !Task.isCancelled {
                let (positions, isSettled) = await simulator.advance(steps: stepsPerUpdate)
                guard let self, !Task.isCancelled else { return }
                self.positions = positions
                if isSettled {
                    self.isSettled = true
                    self.runTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

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

    @State private var model = GraphCanvasModel()
    @State private var scale = 1.0
    @State private var offset = CGSize.zero
    @State private var gestureStartScale: Double?
    @State private var gestureStartOffset: CGSize?
    @State private var draggedIdentifier: String?
    @State private var hoveredIndex: Int?
    /// Once the person moves or zooms, the view no longer fits itself to the graph.
    @State private var isFollowingLayout = true
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    /// From this zoom on, every node shows its name.
    private static let labelScale = 1.4

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in draw(in: &context, size: size) }
                .contentShape(Rectangle())
                .gesture(dragGesture(in: geometry.size))
                .simultaneousGesture(magnifyGesture(in: geometry.size))
                .onTapGesture { location in
                    guard let index = nodeIndex(at: location, in: geometry.size) else { return }
                    open(model.graph.nodes[index])
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hoveredIndex = nodeIndex(at: location, in: geometry.size)
                    case .ended: hoveredIndex = nil
                    }
                }
                .onChange(of: model.positions) {
                    if isFollowingLayout { fit(in: geometry.size, animated: false) }
                }
                .onChange(of: geometry.size) { if isFollowingLayout { fit(in: geometry.size, animated: false) } }
                .onChange(of: fitRequest) {
                    isFollowingLayout = true
                    fit(in: geometry.size, animated: true)
                }
        }
        .clipped()
        .task(id: graph) {
            // Other nodes, as after a filter changes: show them all again.
            isFollowingLayout = true
            model.load(graph, forces: forces, previousPositions: previousPositions.isEmpty ? model.positionsByIdentifier : previousPositions)
        }
        .onChange(of: forces) { model.change(forces: forces) }
        .onDisappear {
            keepPositions?(model.positionsByIdentifier)
            model.stop()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Graph of \(graph.nodes.count) items and \(graph.edges.count) links")
        .accessibilityChildren {
            ForEach(graph.nodes) { node in
                Button(node.title) { open(node) }
            }
        }
    }

    // MARK: Drawing

    private func screenPoint(_ position: SIMD2<Double>, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + offset.width + position.x * scale, y: size.height / 2 + offset.height + position.y * scale)
    }

    private func graphPosition(_ point: CGPoint, in size: CGSize) -> SIMD2<Double> {
        SIMD2((point.x - size.width / 2 - offset.width) / scale, (point.y - size.height / 2 - offset.height) / scale)
    }

    /// The node the hover or drag is on, whose links stand out.
    private var focusedIndex: Int? {
        draggedIdentifier.flatMap(model.index(of:)) ?? hoveredIndex
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let positions = model.positions
        guard positions.count == model.graph.nodes.count, !positions.isEmpty else { return }
        let points = positions.map { position in screenPoint(position, in: size) }
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
        let labelsFromZoom = alwaysShowsLabels || scale >= Self.labelScale
        for index in points.indices where visible.contains(points[index]) {
            let node = model.graph.nodes[index]
            let isNeighborOfFocused = focused.map { focusedIndex in model.neighborIndexes[focusedIndex].contains(index) } ?? false
            let isFaded = focused != nil && focused != index && !isNeighborOfFocused
            let radius = model.radii[index] * max(0.5, min(scale, 2))
            let circle = Path(ellipseIn: CGRect(x: points[index].x - radius, y: points[index].y - radius, width: radius * 2, height: radius * 2))
            let color = nodeColor(node, isHighlighted: index == highlighted || index == focused)
            if node.kind == .unresolved {
                context.stroke(circle, with: .color(color.opacity(isFaded ? 0.2 : 0.6)), lineWidth: 1.2)
            } else {
                context.fill(circle, with: .color(color.opacity(isFaded ? 0.25 : 1)))
            }
            guard labelsFromZoom || index == highlighted || index == focused || isNeighborOfFocused else { continue }
            let label = Text(node.title).font(.system(size: index == highlighted ? 12 : 11, weight: index == highlighted ? .semibold : .regular))
                .foregroundStyle(isFaded ? Color.secondary.opacity(0.4) : Color.primary.opacity(0.85))
            context.draw(label, at: CGPoint(x: points[index].x, y: points[index].y + radius + 2), anchor: .top)
        }
    }

    private func drawArrows(in context: inout GraphicsContext, points: [CGPoint]) {
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

    private func nodeColor(_ node: GraphNode, isHighlighted: Bool) -> Color {
        if isHighlighted { return accent }
        switch node.kind {
        case .note: return Color.secondary
        case .attachment: return Color(red: 0.85, green: 0.62, blue: 0.12)
        case .tag: return Color(red: 0.25, green: 0.65, blue: 0.35)
        case .unresolved: return Color.secondary
        }
    }

    // MARK: Interaction

    private func nodeIndex(at location: CGPoint, in size: CGSize) -> Int? {
        var best: (index: Int, distance: Double)?
        for index in model.positions.indices where index < model.radii.count {
            let point = screenPoint(model.positions[index], in: size)
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
                if draggedIdentifier == nil, gestureStartOffset == nil {
                    if let index = nodeIndex(at: value.startLocation, in: size) {
                        draggedIdentifier = model.graph.nodes[index].id
                        // Fitting while dragging would move the graph under the finger.
                        isFollowingLayout = false
                    } else {
                        gestureStartOffset = offset
                        isFollowingLayout = false
                    }
                }
                if let draggedIdentifier {
                    model.pin(draggedIdentifier, at: graphPosition(value.location, in: size))
                } else if let gestureStartOffset {
                    offset = CGSize(width: gestureStartOffset.width + value.translation.width, height: gestureStartOffset.height + value.translation.height)
                }
            }
            .onEnded { _ in
                if let draggedIdentifier { model.unpin(draggedIdentifier) }
                draggedIdentifier = nil
                gestureStartOffset = nil
            }
    }

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if gestureStartScale == nil {
                    gestureStartScale = scale
                    isFollowingLayout = false
                }
                guard let startScale = gestureStartScale else { return }
                // Zooms around the fingers: the point under them stays put.
                let anchor = graphPosition(value.startLocation, in: size)
                scale = min(max(startScale * value.magnification, 0.05), 6)
                let anchorAfter = screenPoint(anchor, in: size)
                offset.width += value.startLocation.x - anchorAfter.x
                offset.height += value.startLocation.y - anchorAfter.y
            }
            .onEnded { _ in gestureStartScale = nil }
    }

    /// Shows the whole graph, names included, at most a little larger than its natural size.
    private func fit(in size: CGSize, animated: Bool) {
        let positions = model.positions
        guard size.width > 0, size.height > 0, positions.count == model.graph.nodes.count, let first = positions.first else { return }
        var lower = first, upper = first
        for position in positions {
            lower = pointwiseMin(lower, position)
            upper = pointwiseMax(upper, position)
        }
        let margin = 16.0
        let width = max(upper.x - lower.x, 1), height = max(upper.y - lower.y, 1)
        var fitted = min(max(min((size.width - margin * 2) / width, (size.height - margin * 2) / height), 0.05), 2.2)
        // Names show on every node when zoomed in this far (see `draw`), so they need room.
        let showsLabels = alwaysShowsLabels || fitted >= Self.labelScale
        let labelHeight = showsLabels ? 26.0 : 0
        // A name is about 6 points a letter at 11 points, centered under its node.
        let labelHalfWidths = model.graph.nodes.map { node in showsLabels ? Double(node.title.count) * 3.2 : 0 }
        fitted = min(fitted, max((size.height - margin * 2 - labelHeight) / height, 0.05))
        var screenCenterX = (lower.x + upper.x) / 2 * fitted
        // Names at the edges need room too: shrink until the widest reach fits.
        for _ in 0..<6 {
            var left = Double.infinity, right = -Double.infinity
            for index in positions.indices {
                left = min(left, positions[index].x * fitted - labelHalfWidths[index])
                right = max(right, positions[index].x * fitted + labelHalfWidths[index])
            }
            screenCenterX = (left + right) / 2
            let overflow = (right - left) - (size.width - margin * 2)
            guard overflow > 0.5 else { break }
            fitted = max(fitted * max((width * fitted - overflow) / (width * fitted), 0.5), 0.05)
        }
        let screenCenterY = ((lower.y + upper.y) / 2) * fitted + labelHeight / 2
        let change = {
            scale = fitted
            offset = CGSize(width: -screenCenterX, height: -screenCenterY)
        }
        if animated { withAnimation(.snappy) { change() } } else { change() }
    }
}
