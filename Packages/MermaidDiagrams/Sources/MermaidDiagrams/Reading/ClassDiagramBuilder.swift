/// Collects a class diagram as its statements are read: classes by identifier, relations and notes within the limits,
/// and the namespaces open at each point, which take the classes declared inside them. Classes, notes and the
/// interfaces of lollipop ends are the diagram's nodes, which `maximumNodeCount` bounds together.
struct ClassDiagramBuilder {
    private var diagram = ClassDiagram()
    private let limits: MermaidDiagramLimits
    private var classIndexByIdentifier: [String: Int] = [:]
    /// The identifier each note's `note for` names, by note index, found among the classes once all are declared.
    private var noteClassIdentifiers: [String?] = []
    private var interfaceCount = 0
    /// Indexes into `diagram.namespaces` of the namespaces open now, outermost first.
    private var openNamespaceIndices: [Int] = []

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// The diagram read, each note joined to the class its `note for` names when the diagram declares that class.
    func finished() -> ClassDiagram {
        var finished = diagram
        for (noteIndex, identifier) in noteClassIdentifiers.enumerated() {
            finished.notes[noteIndex].classIndex = identifier.flatMap { identifier in classIndexByIdentifier[identifier] }
        }
        return finished
    }

    private var nodeCount: Int { diagram.classes.count + diagram.notes.count + interfaceCount }

    /// The index of the class `name` names, added the first time it is named, with its name as its label and the
    /// generic type written then.
    mutating func classIndex(for name: ClassDiagramName) throws(MermaidDiagramReadError) -> Int {
        if let existing = classIndexByIdentifier[name.identifier] { return existing }
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        let index = diagram.classes.count
        diagram.classes.append(ClassDiagramClass(identifier: name.identifier, label: DiagramLabel(name.identifier), genericType: name.genericType))
        classIndexByIdentifier[name.identifier] = index
        return index
    }

    /// `class Name["Label"]`: a later label replaces an earlier one.
    mutating func setLabel(_ label: DiagramLabel, ofClassAt index: Int) {
        diagram.classes[index].label = label
    }

    mutating func addAnnotation(_ annotation: String, toClassAt index: Int) {
        diagram.classes[index].annotations.append(annotation)
    }

    /// A member as Mermaid sorts it: `<<…>>` is an annotation, text with a `)` after its first character a method
    /// (or an attribute when no `(` opens it), anything else an attribute. Empty text adds nothing.
    mutating func addMember(_ text: String, toClassAt index: Int) {
        guard !text.isEmpty else { return }
        if text.count >= 4, text.hasPrefix("<<"), text.hasSuffix(">>") {
            addAnnotation(String(text.dropFirst(2).dropLast(2)), toClassAt: index)
            return
        }
        let (member, isMethod) = ClassDiagramMemberSyntax.member(from: text)
        if isMethod { diagram.classes[index].methods.append(member) } else { diagram.classes[index].attributes.append(member) }
    }

    /// A relation between the classes its ends name, added when first named. A lollipop end facing no other mark
    /// names an interface of its own rather than a class (`bar ()-- foo`), as in Mermaid.
    mutating func addRelation(from sourceName: ClassDiagramName, to targetName: ClassDiagramName, operator relationOperator: ClassDiagramRelationOperator,
                              cardinalities: (source: String?, target: String?), label: DiagramLabel?) throws(MermaidDiagramReadError) {
        guard diagram.relations.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        let sourceIsInterface = relationOperator.sourceEnd == .lollipop && relationOperator.targetEnd == .none
        let targetIsInterface = relationOperator.targetEnd == .lollipop && relationOperator.sourceEnd == .none
        let source: ClassDiagramRelationEndpoint
        let target: ClassDiagramRelationEndpoint
        if sourceIsInterface {
            target = .classIndex(try classIndex(for: targetName))
            source = try interface(named: sourceName)
        } else {
            source = .classIndex(try classIndex(for: sourceName))
            target = targetIsInterface ? try interface(named: targetName) : .classIndex(try classIndex(for: targetName))
        }
        diagram.relations.append(ClassDiagramRelation(source: source, target: target, sourceEnd: relationOperator.sourceEnd,
                                                      targetEnd: relationOperator.targetEnd, line: relationOperator.line,
                                                      sourceCardinality: cardinalities.source, targetCardinality: cardinalities.target, label: label))
    }

    private mutating func interface(named name: ClassDiagramName) throws(MermaidDiagramReadError) -> ClassDiagramRelationEndpoint {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        interfaceCount += 1
        return .interface(DiagramLabel(name.identifier))
    }

    /// `note "text"`, or `note for Name "text"` with the identifier of the class it names.
    mutating func addNote(_ text: DiagramLabel, forClassIdentifiedBy identifier: String?) throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        diagram.notes.append(ClassDiagramNote(text: text))
        noteClassIdentifiers.append(identifier)
    }

    /// Opens a namespace inside the innermost one open, its identifier joined to that one's by a dot.
    mutating func openNamespace(named name: String, title: DiagramLabel?) {
        let identifier = innermostOpenNamespaceIdentifier.map { parent in parent + "." + name } ?? name
        diagram.namespaces.append(ClassDiagramNamespace(identifier: identifier, title: title ?? DiagramLabel(name)))
        openNamespaceIndices.append(diagram.namespaces.count - 1)
    }

    mutating func closeNamespace() {
        openNamespaceIndices.removeLast()
    }

    /// The identifier of the innermost namespace still open, or nil.
    var innermostOpenNamespaceIdentifier: String? {
        openNamespaceIndices.last.map { index in diagram.namespaces[index].identifier }
    }

    /// A class declared inside the innermost namespace open.
    mutating func addToInnermostNamespace(classAt index: Int) {
        guard let namespaceIndex = openNamespaceIndices.last, !diagram.namespaces[namespaceIndex].classIndices.contains(index) else { return }
        diagram.namespaces[namespaceIndex].classIndices.append(index)
    }

    mutating func setDirection(_ direction: FlowchartDirection) {
        diagram.direction = direction
    }

    mutating func setAccessibilityTitle(_ title: String) {
        diagram.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        diagram.accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        diagram.unappliedStatementCount += 1
    }
}
