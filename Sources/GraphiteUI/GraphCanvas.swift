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
    /// Where the view was left, which it starts from and keeps when it goes, so that it
    /// comes back at the same zoom and position; nil to fit the graph each time.
    var keptPlace: Binding<GraphCanvasPlace?> = .constant(nil)

    @State private var model = GraphCanvasModel()
    @State private var viewport = GraphViewport()
    @State private var gestureStartScale: Double?
    @State private var gestureStartViewport: GraphViewport?
    @State private var draggedIdentifier: String?
    @State private var hoveredIndex: Int?
    /// What the view keeps in sight while the layout settles. Once the person moves or
    /// zooms, the view no longer follows the layout.
    @State private var framing = GraphCanvasPlace.Framing.allNodes
    /// The last center request followed, kept with the place.
    @State private var servedCenterRequest: GraphCenterRequest?
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
                .onTapGesture { location in tap(at: location, in: geometry.size) }
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
                .onChange(of: centerRequest) { follow(centerRequest, in: geometry.size) }
        }
        .clipped()
        .overlay {
            if model.isCalming { ProgressView() }
        }
        .task(id: graph) { await show(graph) }
        .onChange(of: forces) { model.change(forces: forces) }
        .onChange(of: groupColoring) { model.colorNodes(by: groupColoring.groupIndexByIdentifier) }
        .onDisappear(perform: keepWhereTheGraphIs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Graph of \(model.counts.summary)")
        .accessibilityChildren {
            ForEach(graph.nodes) { node in
                Button(node.title) { open(node) }
            }
        }
    }

    // MARK: Showing and keeping the graph

    /// Shows the graph's nodes: the first time from the place the graph was left at, after
    /// the nodes change (as after a filter) all of them again; a center request not followed
    /// yet wins over both.
    private func show(_ graph: LinkGraph) async {
        let isFirstLoad = model.graph.nodes.isEmpty
        let kept = isFirstLoad ? keptPlace.wrappedValue : GraphCanvasPlace(viewport: viewport, framing: .allNodes, servedCenterRequest: servedCenterRequest)
        let start = GraphCanvasPlace.starting(from: kept, centerRequest: centerRequest)
        viewport = start.viewport
        framing = start.framing
        servedCenterRequest = start.servedCenterRequest
        // The nodes shown now win over the places kept when the view last went.
        let knownPositions = previousPositions.merging(model.positionsByIdentifier) { _, shownPosition in shownPosition }
        await model.load(graph, forces: forces, previousPositions: knownPositions, groupIndexByIdentifier: groupColoring.groupIndexByIdentifier)
    }

    /// Keeps where the nodes are and where the view is, for when the graph comes back.
    private func keepWhereTheGraphIs() {
        keepPositions?(model.positionsByIdentifier)
        keptPlace.wrappedValue = GraphCanvasPlace(viewport: viewport, framing: framing, servedCenterRequest: servedCenterRequest)
        model.stop()
    }

    private func follow(_ centerRequest: GraphCenterRequest?, in size: CGSize) {
        guard let centerRequest else { return }
        framing = .node(centerRequest.identifier)
        servedCenterRequest = centerRequest
        center(on: centerRequest.identifier, in: size, animated: !GraphiteMotion.isReduced)
    }

    // MARK: Drawing

    /// The node the drag or hover is on, else the chosen tag, whose links stand out.
    private var focusedIndex: Int? {
        draggedIdentifier.flatMap(model.index(of:)) ?? hoveredIndex ?? chosenTag.wrappedValue.flatMap(model.index(of:))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let emphasis = GraphEmphasis(focusedIndex: focusedIndex, openIndex: highlightedIdentifier.flatMap(model.index(of:)),
                                     neighborIndexes: model.neighborIndexes)
        let look = GraphCanvasLook(display: display, palette: palette(in: context.environment), accent: accent, groupColoring: groupColoring,
                                   showsArrows: showsArrows, alwaysShowsNames: alwaysShowsLabels)
        GraphCanvasRenderer(model: model, viewport: viewport, emphasis: emphasis, look: look).draw(in: &context, size: size)
    }

    /// The graph's colors for this appearance, against the accent as it is drawn here.
    private func palette(in environment: EnvironmentValues) -> GraphPalette {
        let resolvedAccent = accent.resolve(in: environment)
        let accentColor = ThemeColor(red: Double(resolvedAccent.red), green: Double(resolvedAccent.green), blue: Double(resolvedAccent.blue))
        return GraphPalette(appearance: colorScheme == .dark ? .dark : .light, accent: accentColor)
    }

    // MARK: Interaction

    private func tap(at location: CGPoint, in size: CGSize) {
        switch model.tap(nodeAt: nodeIndex(at: location, in: size), chosenTag: chosenTag.wrappedValue) {
        case .open(let node): open(node)
        case .choose(let tag): chosenTag.wrappedValue = tag
        }
    }

    private func nodeIndex(at location: CGPoint, in size: CGSize) -> Int? {
        var best: (index: Int, distance: Double)?
        for index in model.positions.indices where index < model.radii.count {
            let point = viewport.screenPoint(model.positions[index], in: size)
            let distance = hypot(point.x - location.x, point.y - location.y)
            let reach = max(model.screenRadius(ofNodeAt: index, in: viewport, display: display) + Self.nodeReachMarginPoints, Self.minimumFingerReachPoints)
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
