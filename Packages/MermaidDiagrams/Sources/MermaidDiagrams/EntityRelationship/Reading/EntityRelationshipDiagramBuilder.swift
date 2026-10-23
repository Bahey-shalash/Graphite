/// Collects an entity relationship diagram as its statements are read: entities by name, added when the statement
/// that names them is complete, relationships within the limits, and the groups open at each point.
struct EntityRelationshipDiagramBuilder {
    private(set) var diagram = EntityRelationshipDiagram()
    private let limits: MermaidDiagramLimits
    private var entityIndexByIdentifier: [String: Int] = [:]
    /// The identifiers of the `subgraph` groups open now, outermost first.
    private var openSubgraphIdentifiers: [String] = []

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// The index of the entity `name` names, added with its name as its text the first time it is named.
    mutating func entityIndex(for name: EntityRelationshipName) throws(MermaidDiagramReadError) -> Int {
        if let existing = entityIndexByIdentifier[name.text] { return existing }
        guard diagram.entities.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        diagram.entities.append(EntityRelationshipEntity(identifier: name.text, label: name.label))
        entityIndexByIdentifier[name.text] = diagram.entities.count - 1
        return diagram.entities.count - 1
    }

    /// Gives the entity an alias, unless an earlier statement gave it one: Mermaid keeps the first.
    mutating func setAlias(_ alias: DiagramLabel, ofEntityAt index: Int) {
        guard !diagram.entities[index].hasAlias else { return }
        diagram.entities[index].label = alias
        diagram.entities[index].hasAlias = true
    }

    /// Adds the rows of one `{ … }` block after those of the entity's earlier blocks.
    mutating func addAttributes(_ attributes: [EntityRelationshipAttribute], toEntityAt index: Int) {
        diagram.entities[index].attributes.append(contentsOf: attributes)
    }

    mutating func addRelationship(_ relationship: EntityRelationship) throws(MermaidDiagramReadError) {
        guard diagram.relationships.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        diagram.relationships.append(relationship)
    }

    /// A `direction` inside a group sets the group's direction, which is not laid out yet; outside, the diagram's.
    mutating func setDirection(_ direction: FlowchartDirection) {
        guard openSubgraphIdentifiers.isEmpty else { return }
        diagram.direction = direction
    }

    mutating func openSubgraph(identifier: String) {
        openSubgraphIdentifiers.append(identifier)
        diagram.subgraphCount += 1
    }

    /// Closes the innermost group; false when none is open.
    mutating func closeSubgraph() -> Bool {
        openSubgraphIdentifiers.popLast() != nil
    }

    /// The identifier of the innermost group still open, or nil.
    var innermostOpenSubgraphIdentifier: String? {
        openSubgraphIdentifiers.last
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
