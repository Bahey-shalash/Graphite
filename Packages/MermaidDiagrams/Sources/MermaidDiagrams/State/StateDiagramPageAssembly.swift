import CoreGraphics

/// Puts a placed state diagram on the page: states at their centers, transitions from one state's side to the other's
/// through their passing points, loops beside their states, notes beside theirs with their dashed lines, then
/// everything moved inside the padding below the title.
struct StateDiagramPageAssembly {
    let diagram: StateDiagram
    let measured: StateDiagramMeasurement
    let surroundings: StateDiagramSurroundings
    let axes: FlowchartFlowAxes
    private(set) var stateCenters: [CGPoint] = []
    /// By transition index; nil until the transition is placed.
    private var transitions: [StateDiagramLayoutTransition?]

    init(diagram: StateDiagram, measured: StateDiagramMeasurement, surroundings: StateDiagramSurroundings, axes: FlowchartFlowAxes) {
        self.diagram = diagram
        self.measured = measured
        self.surroundings = surroundings
        self.axes = axes
        transitions = Array(repeating: nil, count: diagram.transitions.count)
    }

    mutating func placeStates(flowCenters: [CGPoint]) {
        stateCenters = flowCenters.map(axes.pagePoint)
    }

    /// The transitions between two different states, along their routes. `layeredTransitionIndices[i]` is the
    /// transition of the placement's `i`-th route.
    mutating func placeTransitions(layeredTransitionIndices: [Int], placement: LayeredPlacement) {
        var ends: [StateDiagramEdgePorts.End] = []
        for (layeredIndex, transitionIndex) in layeredTransitionIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex]
            let transition = diagram.transitions[transitionIndex]
            let leavesDownstream = route[1].y > route[0].y
            let arrivesFromUpstream = route[route.count - 2].y < route[route.count - 1].y
            ends.append(StateDiagramEdgePorts.End(transitionIndex: transitionIndex, isSourceEnd: true, state: transition.sourceIndex,
                                                  side: leavesDownstream ? axes.downstreamSide : axes.upstreamSide, neighbor: axes.pagePoint(route[1])))
            ends.append(StateDiagramEdgePorts.End(transitionIndex: transitionIndex, isSourceEnd: false, state: transition.targetIndex,
                                                  side: arrivesFromUpstream ? axes.upstreamSide : axes.downstreamSide,
                                                  neighbor: axes.pagePoint(route[route.count - 2])))
        }
        let ports = StateDiagramEdgePorts(ends: ends, transitionCount: diagram.transitions.count, stateCenters: stateCenters,
                                          kinds: diagram.states.map(\.kind), stateSizes: measured.stateSizes)
        for (layeredIndex, transitionIndex) in layeredTransitionIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex]
            guard let sourcePoint = ports.sourcePoints[transitionIndex], let targetPoint = ports.targetPoints[transitionIndex] else { continue }
            let points = [sourcePoint] + route.dropFirst().dropLast().map(axes.pagePoint) + [targetPoint]
            let drawn = DiagramRouteDrawing.path(through: points, flowIsVertical: axes.flowIsVertical, startTrim: 0,
                                                 endTrim: DiagramEdgeMark.lineTrim(for: .arrow))
            let textCenter = placement.edgeLabelCenters[layeredIndex].map(axes.pagePoint)
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            transitions[transitionIndex] = StateDiagramLayoutTransition(
                path: drawn.path, arrow: DiagramEdgeMark(arrowhead: .arrow, tip: targetPoint, direction: drawn.endDirection),
                text: centered(measured.transitionTexts[transitionIndex], at: textCenter))
        }
    }

    /// The loops of every state that has transitions to itself.
    mutating func placeSelfLoops() {
        for (state, loopTransitionIndices) in measured.selfLoopTransitionIndices.enumerated() where !loopTransitionIndices.isEmpty {
            let loops = StateDiagramSelfLoops.loops(center: stateCenters[state], size: measured.stateSizes[state], flowIsVertical: axes.flowIsVertical,
                                                    textSizes: loopTransitionIndices.map { transitionIndex in measured.transitionTexts[transitionIndex]?.size })
            for (transitionIndex, loop) in zip(loopTransitionIndices, loops) {
                transitions[transitionIndex] = StateDiagramLayoutTransition(
                    path: loop.path, arrow: loop.arrow,
                    text: loop.textCenter.flatMap { center in centered(measured.transitionTexts[transitionIndex], at: center) })
            }
        }
    }

    /// Each note beside its state, with the dashed line from the state's side that faces it.
    func notes() -> [StateDiagramLayoutNote] {
        diagram.notes.enumerated().map { noteIndex, note in
            let stateCenter = stateCenters[note.stateIndex]
            let offset = surroundings.noteOffsets[noteIndex]
            let size = measured.noteSizes[noteIndex]
            let center = CGPoint(x: stateCenter.x + offset.dx, y: stateCenter.y + offset.dy)
            let stateSide = noteSide(note.side)
            let stateSize = measured.stateSizes[note.stateIndex]
            let stackPosition = surroundings.noteStackPositions[noteIndex]
            let offsets = StateDiagramEdgePorts.offsets(count: stackPosition.count, placement: diagram.states[note.stateIndex].kind.portPlacement,
                                                        sideLength: stateSide.isHorizontal ? stateSize.width : stateSize.height)
            let start = StateDiagramEdgePorts.sidePoint(center: stateCenter, size: stateSize, side: stateSide, offset: offsets[stackPosition.index])
            let end = StateDiagramEdgePorts.sidePoint(center: center, size: size, side: opposite(stateSide), offset: 0)
            let connector = DiagramRouteDrawing.path(through: [start, end], flowIsVertical: !axes.flowIsVertical, startTrim: 0, endTrim: 0).path
            var text = measured.noteTexts[noteIndex]
            text.center = center
            return StateDiagramLayoutNote(frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                                          text: text, connector: connector)
        }
    }

    /// The side of a state that faces its notes on `side`: across the flow, before or after it.
    private func noteSide(_ side: StateDiagramNoteSide) -> DiagramSide {
        switch side {
        case .left: axes.flowIsVertical ? .left : .top
        case .right: axes.flowIsVertical ? .right : .bottom
        }
    }

    private func opposite(_ side: DiagramSide) -> DiagramSide {
        switch side {
        case .top: .bottom
        case .bottom: .top
        case .left: .right
        case .right: .left
        }
    }

    private func centered(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        guard var text else { return nil }
        text.center = center
        return text
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat) -> StateDiagramLayout {
        let states = diagram.states.indices.map { index in placedState(at: index) }
        let placedTransitions = transitions.compactMap { transition in transition }
        let placedNotes = notes()
        let bounds = StateDiagramLayoutBounds.union(states: states, transitions: placedTransitions, notes: placedNotes)
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        return StateDiagramLayout(size: size, font: font, states: states.map { state in state.translated(by: offset) },
                                  transitions: placedTransitions.map { transition in transition.translated(by: offset) },
                                  notes: placedNotes.map { note in note.translated(by: offset) }, title: placedTitle)
    }

    /// A state's frame, its name in the top of a box and its other descriptions below the line under the name.
    private func placedState(at index: Int) -> StateDiagramLayoutState {
        let center = stateCenters[index]
        let size = measured.stateSizes[index]
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let name = measured.names[index].map { block in
            var placed = block
            placed.center = CGPoint(x: center.x, y: frame.minY + StateDiagramMeasurement.verticalPadding + block.size.height / 2)
            return placed
        }
        let details = measured.details[index].map { block in
            var placed = block
            let top = (name?.frame.maxY ?? frame.minY) + StateDiagramMeasurement.detailsGap
            placed.center = CGPoint(x: center.x, y: top + block.size.height / 2)
            return placed
        }
        return StateDiagramLayoutState(kind: diagram.states[index].kind, frame: frame, name: name, details: details)
    }
}
