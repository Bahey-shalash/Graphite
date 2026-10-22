/// Reads an entity relationship diagram's statements after its `erDiagram` keyword, as Mermaid's grammar does:
/// entities, with an alias (`p[Person]`), classes (`:::name`) and attributes (`{ … }`); relationships
/// (`A ||--o{ B : label`); groups (`subgraph … end`); `direction`; accessibility text; and the statements that only
/// style the diagram, which are counted and left. A statement needs no separator before the next one.
struct EntityRelationshipParser {
    private var lexer: EntityRelationshipLexer
    private var builder: EntityRelationshipDiagramBuilder
    /// The token being looked at, and a cursor at its first byte.
    private var current: EntityRelationshipToken = .endOfText
    private var currentStart: MermaidTextCursor

    /// Reads the diagram whose keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> EntityRelationshipDiagram {
        var parser = EntityRelationshipParser(lexer: EntityRelationshipLexer(cursor: cursor), builder: EntityRelationshipDiagramBuilder(limits: limits),
                                              currentStart: cursor)
        try parser.advance()
        try parser.readStatements()
        return parser.builder.diagram
    }

    private mutating func advance() throws(MermaidDiagramReadError) {
        (current, currentStart) = try lexer.readToken()
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            switch current {
            case .endOfText:
                if let identifier = builder.innermostOpenSubgraphIdentifier {
                    throw .invalidSyntax(line: currentStart.line, problem: .unclosedSubgraph(identifier: identifier))
                }
                return
            case .lineBreak: try advance()
            case .name: try readEntityStatement()
            case .keyword(let keyword): try readKeywordStatement(keyword)
            case .accessibilityTitle(let title):
                builder.setAccessibilityTitle(title)
                try advance()
            case .accessibilityDescription(let description):
                builder.setAccessibilityDescription(description)
                try advance()
            case .direction(let direction):
                builder.setDirection(direction)
                try advance()
            case .quotedText, .cardinality, .identification, .openingBrace, .openingBracket, .closingBracket, .classSeparator, .colon, .comma,
                 .unexpectedCharacter:
                throw unexpectedToken()
            }
        }
    }

    private mutating func readKeywordStatement(_ keyword: EntityRelationshipKeyword) throws(MermaidDiagramReadError) {
        switch keyword {
        case .diagram: throw unexpectedToken()
        case .style, .classDefinition:
            // Styles take the rest of their line, and are not applied yet.
            lexer.cursor.skipToEndOfLine()
            builder.countUnappliedStatement()
            try advance()
        case .classAssignment:
            try advance()
            try readClassNames()
            try readClassNames()
            builder.countUnappliedStatement()
        case .subgraph: try readSubgraphOpening()
        case .end:
            guard builder.closeSubgraph() else { throw .invalidSyntax(line: currentStart.line, problem: .endWithoutSubgraph) }
            try advance()
        }
    }

    /// An entity, with an alias, classes and attributes, or the first entity of a relationship.
    private mutating func readEntityStatement() throws(MermaidDiagramReadError) {
        let name = try readName()
        if current == .openingBracket { return try readAliasedEntity(name) }
        try readClassShorthand()
        if case .cardinality(let firstCardinality) = current { return try readRelationship(from: name, firstCardinality: firstCardinality) }
        let attributes = try readAttributeBlock(of: name)
        let index = try builder.entityIndex(for: name)
        builder.addAttributes(attributes, toEntityAt: index)
    }

    /// `name[alias]`, then classes and attributes. As in Mermaid, no relationship follows an alias in one statement.
    private mutating func readAliasedEntity(_ name: EntityRelationshipName) throws(MermaidDiagramReadError) {
        let openingLine = currentStart.line
        try advance()
        guard case .name(let aliasText, let aliasForm) = current else { throw unclosedAlias(openingLine: openingLine) }
        try advance()
        guard current == .closingBracket else { throw unclosedAlias(openingLine: openingLine) }
        try advance()
        try readClassShorthand()
        let attributes = try readAttributeBlock(of: name)
        let index = try builder.entityIndex(for: name)
        builder.setAlias(EntityRelationshipName(text: aliasText, form: aliasForm).label, ofEntityAt: index)
        builder.addAttributes(attributes, toEntityAt: index)
    }

    /// The rest of `first ||--o{ second : label`, from its first cardinality.
    private mutating func readRelationship(from first: EntityRelationshipName,
                                           firstCardinality: EntityRelationshipCardinality) throws(MermaidDiagramReadError) {
        try advance()
        guard case .identification(let identification) = current else { throw problem(.expectedRelationshipLine) }
        try advance()
        guard case .cardinality(let secondCardinality) = current else { throw problem(.expectedCardinality) }
        try advance()
        guard case .name = current else { throw problem(.expectedNode) }
        let second = try readName()
        try readClassShorthand()
        guard current == .colon else { throw problem(.expectedRelationshipLabel) }
        try advance()
        let label = try readRelationshipLabel()
        let firstIndex = try builder.entityIndex(for: first)
        let secondIndex = try builder.entityIndex(for: second)
        try builder.addRelationship(EntityRelationship(firstEntityIndex: firstIndex, secondEntityIndex: secondIndex, firstEntityCardinality: firstCardinality,
                                                       secondEntityCardinality: secondCardinality, identification: identification, label: label))
    }

    /// A word, a quoted name or other quoted text; a number is no label in Mermaid's grammar.
    private mutating func readRelationshipLabel() throws(MermaidDiagramReadError) -> DiagramLabel {
        let label: DiagramLabel
        switch current {
        case .name(let text, let form) where form != .number: label = EntityRelationshipName(text: text, form: form).label
        case .quotedText(let text): label = DiagramLabelDecoder.label(from: text, form: .markdown)
        case .name, .cardinality, .identification, .keyword, .accessibilityTitle, .accessibilityDescription, .direction, .openingBrace,
             .openingBracket, .closingBracket, .classSeparator, .colon, .comma, .lineBreak, .endOfText, .unexpectedCharacter:
            throw problem(.expectedRelationshipLabel)
        }
        try advance()
        return label
    }

    /// The `{ … }` after an entity, or no attributes when there is none.
    private mutating func readAttributeBlock(of name: EntityRelationshipName) throws(MermaidDiagramReadError) -> [EntityRelationshipAttribute] {
        guard current == .openingBrace else { return [] }
        let attributes = try EntityRelationshipAttributeSyntax.readBlock(&lexer.cursor, entity: name.text)
        try advance()
        return attributes
    }

    /// `subgraph name` or `subgraph name [title words]`, alone on its line.
    private mutating func readSubgraphOpening() throws(MermaidDiagramReadError) {
        try advance()
        guard case .name(let identifier, _) = current else { throw problem(.expectedNode) }
        try advance()
        if current == .openingBracket {
            let openingLine = currentStart.line
            try advance()
            guard case .name = current else { throw unclosedAlias(openingLine: openingLine) }
            while case .name = current { try advance() }
            guard current == .closingBracket else { throw unclosedAlias(openingLine: openingLine) }
            try advance()
        }
        guard current == .lineBreak || current == .endOfText else { throw unexpectedToken() }
        builder.openSubgraph(identifier: identifier)
    }

    /// `:::first,second` after an entity's name: classes, counted and not applied.
    private mutating func readClassShorthand() throws(MermaidDiagramReadError) {
        guard current == .classSeparator else { return }
        try advance()
        try readClassNames()
        builder.countUnappliedStatement()
    }

    /// Bare names joined by commas, as `class` and `:::` list entities and classes.
    private mutating func readClassNames() throws(MermaidDiagramReadError) {
        while true {
            guard case .name(_, .bare) = current else {
                throw current == .lineBreak || current == .endOfText ? problem(.expectedNode) : unexpectedToken()
            }
            try advance()
            guard current == .comma else { return }
            try advance()
        }
    }

    private mutating func readName() throws(MermaidDiagramReadError) -> EntityRelationshipName {
        guard case .name(let text, let form) = current else { throw unexpectedToken() }
        try advance()
        return EntityRelationshipName(text: text, form: form)
    }

    private func problem(_ problem: MermaidSyntaxProblem) -> MermaidDiagramReadError {
        .invalidSyntax(line: currentStart.line, problem: problem)
    }

    /// The token where none of its kind may stand, by its first characters.
    private func unexpectedToken() -> MermaidDiagramReadError {
        problem(.unexpectedText(currentStart.excerpt()))
    }

    /// An alias or a title whose `[` the text ends without closing, or closes after more than a name.
    private func unclosedAlias(openingLine: Int) -> MermaidDiagramReadError {
        switch current {
        case .lineBreak, .endOfText: .invalidSyntax(line: openingLine, problem: .unclosedShape(closingText: "]"))
        case .name, .quotedText, .cardinality, .identification, .keyword, .accessibilityTitle, .accessibilityDescription, .direction, .openingBrace,
             .openingBracket, .closingBracket, .classSeparator, .colon, .comma, .unexpectedCharacter:
            unexpectedToken()
        }
    }
}
