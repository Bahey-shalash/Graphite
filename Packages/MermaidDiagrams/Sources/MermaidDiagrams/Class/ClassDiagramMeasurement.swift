import CoreGraphics

/// The fonts a class diagram's text is measured in, as Pele sizes them: class names and the title in bold at the
/// note's size; members, notes, interfaces and relation text at seven eighths of it; annotations and cardinalities at
/// four fifths.
struct ClassDiagramTextMeasurers<Measurer: DiagramTextMeasuring> {
    let names: Measurer
    let members: Measurer
    let marks: Measurer

    /// The height of a row of annotations or cardinalities: 1.4 times their size, rounded, as in Pele.
    var markRowHeight: CGFloat { (marks.fontSize * ClassDiagramBox.markRowHeightRatio).rounded() }
}

/// A class diagram's text measured and its nodes sized: what the layout needs before it places anything. Its nodes
/// are the classes, then the notes, then the interfaces of lollipop ends, in Pele's order; its edges are the lines
/// from notes to their classes, then the relations.
struct ClassDiagramMeasurement {
    /// A node's kind, with the index of what it draws.
    enum Node {
        case classBox(Int)
        case note(Int)
        case interface(Int)
    }

    /// An edge between two nodes, with its text measured.
    struct Edge {
        let source: Int
        let target: Int
        let sourceEnd: ClassDiagramRelationEnd
        let targetEnd: ClassDiagramRelationEnd
        let line: ClassDiagramLineStyle
        /// The relation's index, or nil for a note's line.
        let relationIndex: Int?
        let text: DiagramTextBlock?
        let sourceCardinality: DiagramTextBlock?
        let targetCardinality: DiagramTextBlock?

        var isSelfLoop: Bool { source == target }
    }

    static let noteWrappingWidth: CGFloat = 260
    static let textWrappingWidth: CGFloat = 200
    static let notePadding = CGSize(width: 12, height: 8)
    static let noteMinimumWidth: CGFloat = 40
    /// An interface's name takes 2 points more on each side, and is 12 points across at least.
    static let interfaceMargin: CGFloat = 2
    static let interfaceMinimumExtent: CGFloat = 12
    /// When several relations leave or reach a class, the gap each needs along its side: 14 points, or the widest
    /// cardinality there and 24 more; the box is widened to that, up to 480 points, in a flow that runs down.
    static let crowdedEndGap: CGFloat = 14
    static let crowdedCardinalityGap: CGFloat = 24
    static let crowdedSideClearance: CGFloat = 24
    static let crowdedMaximumWidth: CGFloat = 480

    private(set) var nodes: [Node] = []
    /// Each node's drawn size: a class's box, a note's, an interface name's.
    private(set) var sizes: [CGSize] = []
    private(set) var boxes: [ClassDiagramBox] = []
    private(set) var noteTexts: [DiagramTextBlock] = []
    private(set) var interfaceTexts: [DiagramTextBlock] = []
    private(set) var edges: [Edge] = []

    init<Measurer: DiagramTextMeasuring>(diagram: ClassDiagram, measurers: ClassDiagramTextMeasurers<Measurer>) {
        for declared in diagram.classes {
            let box = ClassDiagramBox(declared, measurers: measurers)
            nodes.append(.classBox(boxes.count))
            boxes.append(box)
            sizes.append(box.size)
        }
        let firstNoteNode = nodes.count
        for note in diagram.notes {
            let text = DiagramTextBlock(label: note.text, measurer: measurers.members, maximumWidth: Self.noteWrappingWidth)
            nodes.append(.note(noteTexts.count))
            noteTexts.append(text)
            sizes.append(CGSize(width: max(text.size.width + 2 * Self.notePadding.width, Self.noteMinimumWidth),
                                height: text.size.height + 2 * Self.notePadding.height))
        }
        for (noteIndex, note) in diagram.notes.enumerated() {
            guard let classIndex = note.classIndex else { continue }
            edges.append(Edge(source: firstNoteNode + noteIndex, target: classIndex, sourceEnd: .none, targetEnd: .none, line: .dotted,
                              relationIndex: nil, text: nil, sourceCardinality: nil, targetCardinality: nil))
        }
        for (relationIndex, relation) in diagram.relations.enumerated() {
            edges.append(Edge(source: node(for: relation.source, measurers: measurers), target: node(for: relation.target, measurers: measurers),
                              sourceEnd: relation.sourceEnd, targetEnd: relation.targetEnd, line: relation.line, relationIndex: relationIndex,
                              text: relation.label.map { label in
                                  DiagramTextBlock(label: label, measurer: measurers.members, maximumWidth: Self.textWrappingWidth)
                              }.flatMap { text in text.lines.isEmpty ? nil : text },
                              sourceCardinality: cardinality(relation.sourceCardinality, measurers: measurers),
                              targetCardinality: cardinality(relation.targetCardinality, measurers: measurers)))
        }
    }

    /// The node a relation's endpoint is: its class's, or a new interface's.
    private mutating func node<Measurer: DiagramTextMeasuring>(for endpoint: ClassDiagramRelationEndpoint,
                                                               measurers: ClassDiagramTextMeasurers<Measurer>) -> Int {
        switch endpoint {
        case .classIndex(let index): return index
        case .interface(let label):
            let text = DiagramTextBlock(label: label, measurer: measurers.members, maximumWidth: Self.textWrappingWidth)
            nodes.append(.interface(interfaceTexts.count))
            interfaceTexts.append(text)
            sizes.append(CGSize(width: max(text.size.width, Self.interfaceMinimumExtent) + 2 * Self.interfaceMargin,
                                height: max(text.size.height, Self.interfaceMinimumExtent)))
            return nodes.count - 1
        }
    }

    private func cardinality<Measurer: DiagramTextMeasuring>(_ text: String?, measurers: ClassDiagramTextMeasurers<Measurer>) -> DiagramTextBlock? {
        text.map { text in DiagramTextBlock(label: DiagramLabel(text), measurer: measurers.marks, maximumWidth: .greatestFiniteMagnitude) }
    }

    /// Widens each class whose sides many relations meet, so that they and their cardinalities fit side by side
    /// (in a flow that runs down, as Pele does): edges leaving a class are counted on one side and edges reaching it
    /// on the other.
    mutating func widenCrowdedClasses() {
        var leaving = [(count: Int, room: CGFloat)](repeating: (0, 0), count: nodes.count)
        var reaching = leaving
        for edge in edges where !edge.isSelfLoop {
            leaving[edge.source].count += 1
            leaving[edge.source].room = max(leaving[edge.source].room, edge.sourceCardinality?.size.width ?? 0)
            reaching[edge.target].count += 1
            reaching[edge.target].room = max(reaching[edge.target].room, edge.targetCardinality?.size.width ?? 0)
        }
        for (node, kind) in nodes.enumerated() {
            guard case .classBox(let boxIndex) = kind else { continue }
            let needed = min(Self.crowdedMaximumWidth, max(Self.crowdedWidth(leaving[node]), Self.crowdedWidth(reaching[node])))
            guard needed > sizes[node].width else { continue }
            sizes[node].width = needed
            boxes[boxIndex].size.width = needed
        }
    }

    private static func crowdedWidth(_ side: (count: Int, room: CGFloat)) -> CGFloat {
        guard side.count > 1 else { return 0 }
        let gap = side.room > 0 ? side.room + crowdedCardinalityGap : crowdedEndGap
        return CGFloat(side.count - 1) * gap + crowdedSideClearance
    }

    /// For each node, the indexes of its edges to itself, in their order.
    var selfLoopEdgeIndices: [[Int]] {
        var loops = [[Int]](repeating: [], count: nodes.count)
        for (edgeIndex, edge) in edges.enumerated() where edge.isSelfLoop { loops[edge.source].append(edgeIndex) }
        return loops
    }

    /// Each node's size in its rank: its drawn size, widened on both sides by the room its loops take beside it.
    func layoutSizes(selfLoops: [[Int]]) -> [CGSize] {
        sizes.enumerated().map { node, size in
            let room = selfLoops[node].reduce(0) { room, edgeIndex in room + ClassDiagramSelfLoops.room(textWidth: edges[edgeIndex].text?.size.width) }
            return CGSize(width: size.width + 2 * room, height: size.height)
        }
    }
}
