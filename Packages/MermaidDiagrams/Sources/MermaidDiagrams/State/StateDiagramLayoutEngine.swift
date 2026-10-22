import CoreGraphics

/// Lays a state diagram out in Pele's style: boxes sized around their names, wrapped at 200 points, and the small
/// marks of starts, ends, choices, forks and joins; the states in ranks along the diagram's direction, 40 points apart
/// in a rank and 44 points between ranks, starts first and the others in the order transitions first name them;
/// transitions as S curves that spread along the sides of boxes; transitions to a state itself as loops beside it;
/// notes beside their states across the flow; and the title above.
public enum StateDiagramLayoutEngine {
    static let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 44)
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// The widest a line of a state's or a transition's text is before it wraps.
    static let wrappingWidth: CGFloat = 200
    /// The widest a line of a note is before it wraps.
    static let noteWrappingWidth: CGFloat = 320
    /// The room a transition's text takes beyond its lines, for the patch drawn behind it.
    static let transitionTextRoom = CGSize(width: 12, height: 4)
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12

    public static func layout(_ diagram: StateDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits) throws(StateDiagramLayoutError) -> StateDiagramLayout {
        try layout(diagram, nameText: typography.nodeText, smallText: typography.edgeText, font: typography.font, limits: limits)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: StateDiagram, nameText: Measurer, smallText: Measurer, font: DiagramFont,
                                                       limits: MermaidDiagramLimits) throws(StateDiagramLayoutError) -> StateDiagramLayout {
        guard diagram.composites.isEmpty else { throw .compositeStatesNotLaidOut }
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let measured = StateDiagramMeasurement(diagram: diagram, nameText: nameText, smallText: smallText, flowIsVertical: flowAxes.flowIsVertical,
                                               wrappingWidth: wrappingWidth, noteWrappingWidth: noteWrappingWidth)
        let surroundings = StateDiagramSurroundings(diagram: diagram, measured: measured, axes: flowAxes)
        let order = flowOrder(of: diagram)
        var positionOfState = [Int](repeating: 0, count: order.count)
        for (position, state) in order.enumerated() { positionOfState[state] = position }
        let layeredTransitionIndices = diagram.transitions.indices.filter { transitionIndex in
            diagram.transitions[transitionIndex].sourceIndex != diagram.transitions[transitionIndex].targetIndex
        }
        let graph = LayeredGraph(nodeSizes: order.map { state in surroundings.placeSizes[state] },
                                 edges: layeredTransitionIndices.map { transitionIndex in
                                     let transition = diagram.transitions[transitionIndex]
                                     let labelSize = measured.transitionTexts[transitionIndex].map { text in
                                         flowAxes.flowSize(of: CGSize(width: text.size.width + transitionTextRoom.width,
                                                                      height: text.size.height + transitionTextRoom.height))
                                     }
                                     return LayeredEdge(source: positionOfState[transition.sourceIndex], target: positionOfState[transition.targetIndex],
                                                        minimumRankSpan: 1, labelSize: labelSize)
                                 })
        guard let placement = LayeredLayout.place(graph, spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount) else {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = StateDiagramPageAssembly(diagram: diagram, measured: measured, surroundings: surroundings,
                                            axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: placement.extent.height))
        page.placeStates(flowCenters: diagram.states.indices.map { state in placement.nodeCenters[positionOfState[state]] })
        page.placeTransitions(layeredTransitionIndices: layeredTransitionIndices, placement: placement)
        page.placeSelfLoops()
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: nameText, maximumWidth: .greatestFiniteMagnitude) }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }

    /// The states in the order the layout takes them, Pele's: starts first, then the others in the order transitions
    /// first name them, then those no transition names, each group in the diagram's order. A state declared before
    /// the transitions does not become the top of the flow.
    static func flowOrder(of diagram: StateDiagram) -> [Int] {
        var firstAppearance = [Int](repeating: .max, count: diagram.states.count)
        var appearanceCount = 0
        for transition in diagram.transitions {
            for state in [transition.sourceIndex, transition.targetIndex] where firstAppearance[state] == .max {
                firstAppearance[state] = appearanceCount
                appearanceCount += 1
            }
        }
        return diagram.states.indices.sorted { first, second in
            (diagram.states[first].kind.isStart ? 0 : 1, firstAppearance[first], first)
                < (diagram.states[second].kind.isStart ? 0 : 1, firstAppearance[second], second)
        }
    }
}

extension StateDiagramStateKind {
    /// Whether the layout takes the state before the others in its order.
    var isStart: Bool {
        switch self {
        case .start: true
        case .state, .end, .choice, .fork, .join: false
        }
    }
}
