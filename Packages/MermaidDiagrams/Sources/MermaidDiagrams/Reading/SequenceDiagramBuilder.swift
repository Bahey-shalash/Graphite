/// Collects a sequence diagram as its statements are read, with Mermaid's rules: participants by identifier in the
/// order they are first named, activations counted so that only an active participant is deactivated, and blocks
/// closed in order, each section in the block it belongs to.
struct SequenceDiagramBuilder {
    private var diagram = SequenceDiagram()
    private let limits: MermaidDiagramLimits
    private var participantIndexByIdentifier: [String: Int] = [:]
    /// How many activations each participant has open, by identifier, named or not.
    private var openActivationCountByIdentifier: [String: Int] = [:]
    /// Activations of a participant no statement had named when they were written: the event's index, the identifier
    /// and whether it starts or ends one. Mermaid draws them if the participant is named later, and drops them if not.
    private var activationsOfUnnamedParticipants: [(eventIndex: Int, identifier: String, isStart: Bool)] = []
    /// The blocks open now, innermost last.
    private var openBlocks: [OpenBlock] = []

    /// A block open while its statements are read: a framed block, a highlight or a box, with the line it opened on.
    private struct OpenBlock {
        let keyword: String
        /// The keyword of the sections this block may hold (`else`, `and`, `option`), or nil.
        let sectionKeyword: String?
        let line: Int
        /// Whether it is a `box`, which adds no event.
        let isBox: Bool
    }

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// Whether the innermost open block is a `box`, which holds participant statements only.
    var isInsideBox: Bool {
        openBlocks.last?.isBox == true
    }

    /// The index of the participant named `identifier`, added as a participant with its identifier as its text the
    /// first time it is named.
    mutating func participantIndex(for identifier: String) throws(MermaidDiagramReadError) -> Int {
        if let index = participantIndexByIdentifier[identifier] { return index }
        guard diagram.participants.count < limits.maximumNodeCount else { throw .tooManyParticipants(limit: limits.maximumNodeCount) }
        let index = diagram.participants.count
        diagram.participants.append(SequenceParticipant(identifier: identifier, label: DiagramLabel(identifier)))
        participantIndexByIdentifier[identifier] = index
        return index
    }

    /// `participant` or `actor`. A participant named before keeps its place; an alias gives it its text and its kind,
    /// and a declaration without one changes nothing, as in Mermaid.
    mutating func declareParticipant(_ identifier: String, kind: SequenceParticipantKind, alias: DiagramLabel?) throws(MermaidDiagramReadError) {
        let isNew = participantIndexByIdentifier[identifier] == nil
        let index = try participantIndex(for: identifier)
        guard isNew || alias != nil else { return }
        diagram.participants[index].kind = kind
        if let alias { diagram.participants[index].label = alias }
    }

    mutating func addMessage(_ message: SequenceMessage) throws(MermaidDiagramReadError) {
        try append(.message(message))
    }

    mutating func addNote(_ note: SequenceNote) throws(MermaidDiagramReadError) {
        try append(.note(note))
    }

    /// `activate`, or `+` before a message's target.
    mutating func activate(_ identifier: String) throws(MermaidDiagramReadError) {
        openActivationCountByIdentifier[identifier, default: 0] += 1
        try appendActivation(of: identifier, isStart: true)
    }

    /// `deactivate`, or `-` before a message's target (which ends the source's activation).
    mutating func deactivate(_ identifier: String, line: Int) throws(MermaidDiagramReadError) {
        guard let openCount = openActivationCountByIdentifier[identifier], openCount > 0 else {
            throw .invalidSyntax(line: line, problem: .sequence(.inactiveParticipantDeactivated(identifier: identifier)))
        }
        openActivationCountByIdentifier[identifier] = openCount - 1
        try appendActivation(of: identifier, isStart: false)
    }

    mutating func openBlock(_ kind: SequenceBlockKind, keyword: String, label: DiagramLabel, line: Int) throws(MermaidDiagramReadError) {
        let sectionKeyword: String? = switch kind {
        case .alternatives: "else"
        case .parallel: "and"
        case .critical: "option"
        case .loop, .optional, .break, .highlight: nil
        }
        try append(.blockStart(kind: kind, label: label))
        openBlocks.append(OpenBlock(keyword: keyword, sectionKeyword: sectionKeyword, line: line, isBox: false))
    }

    /// `box`, which groups participants and adds no event.
    mutating func openBox(line: Int) {
        diagram.statementsNotLaidOut.insert(.box)
        openBlocks.append(OpenBlock(keyword: "box", sectionKeyword: nil, line: line, isBox: true))
    }

    /// `else`, `and` or `option`, which must be in the block that has such sections.
    mutating func addSection(keyword: String, label: DiagramLabel, line: Int) throws(MermaidDiagramReadError) {
        guard let innermost = openBlocks.last, innermost.sectionKeyword == keyword else {
            throw .invalidSyntax(line: line, problem: .sequence(.sectionOutsideItsBlock(keyword: keyword)))
        }
        try append(.blockSection(label: label))
    }

    /// `end`.
    mutating func closeBlock(line: Int) throws(MermaidDiagramReadError) {
        guard let closed = openBlocks.popLast() else { throw .invalidSyntax(line: line, problem: .sequence(.endWithoutBlock)) }
        if !closed.isBox { try append(.blockEnd) }
    }

    mutating func addNumbering(_ numbering: SequenceNumbering) throws(MermaidDiagramReadError) {
        try append(.numbering(numbering))
    }

    mutating func noteStatementNotLaidOut(_ statement: SequenceStatementNotLaidOut) {
        diagram.statementsNotLaidOut.insert(statement)
    }

    mutating func setTitle(_ title: String) {
        diagram.title = title
    }

    mutating func setAccessibilityTitle(_ title: String) {
        diagram.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        diagram.accessibilityDescription = description
    }

    /// The diagram, once every block is closed. Activations of participants named later point at them now; those of
    /// participants never named are dropped.
    func finished() throws(MermaidDiagramReadError) -> SequenceDiagram {
        if let unclosed = openBlocks.last {
            throw .invalidSyntax(line: unclosed.line, problem: .sequence(.unclosedBlock(keyword: unclosed.keyword)))
        }
        guard !activationsOfUnnamedParticipants.isEmpty else { return diagram }
        var resolved = diagram
        var droppedEventIndices = Set<Int>()
        for activation in activationsOfUnnamedParticipants {
            guard let index = participantIndexByIdentifier[activation.identifier] else {
                droppedEventIndices.insert(activation.eventIndex)
                continue
            }
            resolved.events[activation.eventIndex] = activation.isStart ? .activationStart(participantIndex: index) : .activationEnd(participantIndex: index)
        }
        if !droppedEventIndices.isEmpty {
            resolved.events = resolved.events.enumerated().filter { eventIndex, _ in !droppedEventIndices.contains(eventIndex) }.map { _, event in event }
        }
        return resolved
    }

    private mutating func appendActivation(of identifier: String, isStart: Bool) throws(MermaidDiagramReadError) {
        guard let index = participantIndexByIdentifier[identifier] else {
            activationsOfUnnamedParticipants.append((diagram.events.count, identifier, isStart))
            // A stand-in that `finished()` replaces or drops.
            try append(isStart ? .activationStart(participantIndex: -1) : .activationEnd(participantIndex: -1))
            return
        }
        try append(isStart ? .activationStart(participantIndex: index) : .activationEnd(participantIndex: index))
    }

    private mutating func append(_ event: SequenceEvent) throws(MermaidDiagramReadError) {
        guard diagram.events.count < limits.maximumEdgeCount else { throw .tooManySequenceStatements(limit: limits.maximumEdgeCount) }
        diagram.events.append(event)
    }
}
