import CoreGraphics

/// What sits beside each state across the flow: the loops of its transitions to itself, and its notes, `left of` on
/// the side before it (left of a diagram that runs down or up, above one that runs across) and `right of` on the side
/// after it. A state takes its place in its rank with all of them, widened equally on both sides, so that its
/// transitions still meet it in the middle of its place.
struct StateDiagramSurroundings {
    /// Between a state and its notes: Pele's rank gap, since a note and its state sit in ranks of a group of their own.
    static let noteGap: CGFloat = 44
    /// Between the notes stacked on one side of a state: Pele's gap between the nodes of a rank.
    static let noteSeparation: CGFloat = 40

    /// Each state's place in its rank, in flow space.
    let placeSizes: [LayeredSize]
    /// Each note's center, from its state's center, on the page: notes on one side are stacked down the page beside a
    /// diagram that runs down or up, and across it beside one that runs across.
    let noteOffsets: [CGVector]
    /// Each note's place in the stack on its side of its state, which orders the dashed lines leaving that side.
    let noteStackPositions: [StackPosition]

    /// A note's place among the notes on one side of a state.
    struct StackPosition {
        let index: Int
        let count: Int
    }

    init(diagram: StateDiagram, measured: StateDiagramMeasurement, axes: FlowchartFlowAxes) {
        var notesBySide = [[Int]](repeating: [], count: diagram.states.count * StateDiagramNoteSide.allCases.count)
        for (noteIndex, note) in diagram.notes.enumerated() { notesBySide[Self.slot(state: note.stateIndex, side: note.side)].append(noteIndex) }
        var placeSizes: [LayeredSize] = []
        var noteOffsets = [CGVector](repeating: .zero, count: diagram.notes.count)
        var noteStackPositions = [StackPosition](repeating: StackPosition(index: 0, count: 1), count: diagram.notes.count)
        placeSizes.reserveCapacity(diagram.states.count)
        for state in diagram.states.indices {
            let shape = axes.flowSize(of: measured.stateSizes[state])
            let loopTextSizes = measured.selfLoopTransitionIndices[state].map { transitionIndex in measured.transitionTexts[transitionIndex]?.size }
            let loops = StateDiagramSelfLoops.extent(textSizes: loopTextSizes, flowIsVertical: axes.flowIsVertical)
            let halfAcross = shape.across / 2 + loops.room
            var along = max(shape.along, loops.textAlong)
            var noteRoom: CGFloat = 0
            for side in StateDiagramNoteSide.allCases {
                let noteIndices = notesBySide[Self.slot(state: state, side: side)]
                guard !noteIndices.isEmpty else { continue }
                let stack = Self.stack(noteIndices.map { noteIndex in axes.flowSize(of: measured.noteSizes[noteIndex]) })
                let acrossOffset = (side == .left ? -1 : 1) * (halfAcross + Self.noteGap + stack.widest / 2)
                for (position, (noteIndex, alongOffset)) in zip(noteIndices, stack.alongOffsets).enumerated() {
                    noteOffsets[noteIndex] = axes.flowIsVertical ? CGVector(dx: acrossOffset, dy: alongOffset) : CGVector(dx: alongOffset, dy: acrossOffset)
                    noteStackPositions[noteIndex] = StackPosition(index: position, count: noteIndices.count)
                }
                noteRoom = max(noteRoom, Self.noteGap + stack.widest)
                along = max(along, stack.length)
            }
            placeSizes.append(LayeredSize(across: 2 * (halfAcross + noteRoom), along: along))
        }
        self.placeSizes = placeSizes
        self.noteOffsets = noteOffsets
        self.noteStackPositions = noteStackPositions
    }

    /// The notes of one side stacked along the flow, centered on their state: the widest across, the stack's length,
    /// and each note's center from the stack's middle.
    private static func stack(_ sizes: [LayeredSize]) -> (widest: CGFloat, length: CGFloat, alongOffsets: [CGFloat]) {
        let length = sizes.reduce(0) { total, size in total + size.along } + noteSeparation * CGFloat(sizes.count - 1)
        var position = -length / 2
        let offsets = sizes.map { size in
            defer { position += size.along + noteSeparation }
            return position + size.along / 2
        }
        return (sizes.map(\.across).max() ?? 0, length, offsets)
    }

    private static func slot(state: Int, side: StateDiagramNoteSide) -> Int {
        switch side {
        case .left: 2 * state
        case .right: 2 * state + 1
        }
    }
}
