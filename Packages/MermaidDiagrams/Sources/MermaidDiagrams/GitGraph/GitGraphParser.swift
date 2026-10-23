/// Reads a Git graph's statements after its `gitGraph` keyword as Mermaid's grammar does (Pele's port of it): an
/// optional `LR:`, `TB:` or `BT:` (or a colon alone) on the keyword's line, then one statement per line: `commit`,
/// `branch`, `checkout` or `switch`, `merge`, `cherry-pick`, `title`, `accTitle` and `accDescr`. Every statement is read
/// before any is played (`GitGraphDiagramBuilder`), so that a syntax error anywhere is reported before a statement the
/// history cannot take, as in Mermaid.
struct GitGraphParser {
    private var lexer: GitGraphLexer
    private var current: (token: GitGraphToken, start: MermaidTextCursor)
    private var statements: [(statement: GitGraphStatement, line: Int)] = []
    private var diagram = GitGraphDiagram()

    /// `cursor` is just past the `gitGraph` keyword, as `MermaidDiagramReader` leaves it.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> GitGraphDiagram {
        let setsOptionsBefore = GitGraphOptionsDetection.setsOptions(inTextBefore: cursor.position - keyword.count, of: cursor.bytes)
        var parser = try GitGraphParser(cursor: cursor)
        try parser.readStatements()
        parser.diagram.setsGitGraphOptions = setsOptionsBefore || parser.lexer.hasSkippedOptionsDirective
        try parser.play(limits: limits)
        return parser.diagram
    }

    /// The keyword's line: `:` straight after it (`gitGraph:`), or after a space, a comment or a line break, a
    /// direction and its colon (`gitGraph TB:`) or a colon alone.
    private init(cursor: MermaidTextCursor) throws(MermaidDiagramReadError) {
        lexer = GitGraphLexer(cursor: cursor)
        if lexer.cursor.peek() == MermaidByte.colon {
            lexer.cursor.advance()
            current = try lexer.readToken()
            return
        }
        guard lexer.isAtKeywordEnd else { throw .invalidSyntax(line: lexer.cursor.line, problem: .unexpectedText(lexer.cursor.excerpt())) }
        current = try lexer.readToken()
        if case .direction(let direction) = current.token {
            var lookahead = lexer
            guard try lookahead.readToken().token == .colon else { return }
            diagram.direction = direction
            lexer = lookahead
            try advance()
        } else if current.token == .colon {
            try advance()
        }
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            switch current.token {
            case .endOfText: return
            case .lineBreak: try advance()
            case .title(let title):
                diagram.title = title.isEmpty ? nil : title
                try advance()
                try endStatement()
            case .accessibility(let statement):
                switch statement {
                case .title(let title): diagram.accessibilityTitle = title
                case .description(let description): diagram.accessibilityDescription = description
                }
                try advance()
                try endStatement()
            case .statement(let keyword):
                let line = current.start.line
                try advance()
                statements.append((try readStatement(keyword), line))
                try endStatement()
            case .diagramKeyword, .diagramKeywordWithColon, .attribute, .commitType, .direction, .colon, .integer, .quotedText, .name:
                throw unexpected()
            }
        }
    }

    private mutating func readStatement(_ keyword: GitGraphStatementKeyword) throws(MermaidDiagramReadError) -> GitGraphStatement {
        switch keyword {
        case .commit: return try readCommit()
        case .branch:
            let name = try readBranchName()
            guard current.token == .attribute(.order) else { return .branch(name: name, order: nil) }
            try advance()
            guard case .integer(let order) = current.token else { throw problem(.gitGraph(.expectedOrder)) }
            try advance()
            return .branch(name: name, order: order)
        case .checkout: return .checkout(name: try readBranchName())
        case .merge:
            let name = try readBranchName()
            var values = StatementValues()
            while try readValue(into: &values, accepting: [.identifier, .tag, .type]) {}
            return .merge(name: name, identifier: values.identifier, tags: values.tags, type: values.type)
        case .cherryPick:
            var values = StatementValues()
            while try readValue(into: &values, accepting: [.identifier, .tag, .parent]) {}
            return .cherryPick(identifier: values.identifier, tags: values.tags, parent: values.parent)
        }
    }

    /// `commit` and its values, of which text in quotation marks alone is the message.
    private mutating func readCommit() throws(MermaidDiagramReadError) -> GitGraphStatement {
        var values = StatementValues()
        while true {
            if case .quotedText(let message) = current.token {
                values.message = message
                try advance()
            } else if try !readValue(into: &values, accepting: [.identifier, .message, .tag, .type]) {
                return .commit(identifier: values.identifier, message: values.message, tags: values.tags, type: values.type)
            }
        }
    }

    /// One of `accepted` and its value, kept in `values`; false, with nothing read, when the token is none of them.
    private mutating func readValue(into values: inout StatementValues,
                                    accepting accepted: [GitGraphAttribute]) throws(MermaidDiagramReadError) -> Bool {
        guard case .attribute(let attribute) = current.token, accepted.contains(attribute) else { return false }
        try advance()
        if attribute == .type {
            guard case .commitType(let type) = current.token else { throw problem(.gitGraph(.expectedCommitType)) }
            values.type = type
        } else {
            guard case .quotedText(let text) = current.token else { throw problem(.expectedQuotedText) }
            values.set(attribute, to: text)
        }
        try advance()
        return true
    }

    /// A name, or text in quotation marks.
    private mutating func readBranchName() throws(MermaidDiagramReadError) -> String {
        switch current.token {
        case .name(let name), .quotedText(let name):
            try advance()
            return name
        case .diagramKeyword, .diagramKeywordWithColon, .statement, .attribute, .commitType, .direction, .colon, .title, .accessibility, .integer,
             .lineBreak, .endOfText:
            throw problem(.gitGraph(.expectedBranchName))
        }
    }

    /// The end of a statement: line breaks, or the end of the text.
    private mutating func endStatement() throws(MermaidDiagramReadError) {
        guard current.token != .endOfText else { return }
        guard current.token == .lineBreak else { throw unexpected() }
        while current.token == .lineBreak { try advance() }
    }

    /// Plays the statements read. When the graph sets options of Git graphs, which are not applied, a statement the
    /// history cannot take ends the playing without an error: the options may name the main branch it refers to.
    private mutating func play(limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) {
        var builder = try GitGraphDiagramBuilder(limits: limits)
        defer { (diagram.commits, diagram.branches) = builder.played() }
        for (statement, line) in statements {
            do {
                try builder.play(statement, line: line)
            } catch .invalidSyntax(_, .gitGraph) where diagram.setsGitGraphOptions {
                return
            }
        }
    }

    private mutating func advance() throws(MermaidDiagramReadError) {
        current = try lexer.readToken()
    }

    private func problem(_ problem: MermaidSyntaxProblem) -> MermaidDiagramReadError {
        .invalidSyntax(line: current.start.line, problem: problem)
    }

    /// The text at the current token, which the statement does not take.
    private func unexpected() -> MermaidDiagramReadError {
        problem(.unexpectedText(current.start.excerpt()))
    }

    private static let keyword = Array("gitGraph".utf8)

    /// The values a statement writes after its keyword: later ones replace earlier ones, and tags add up.
    private struct StatementValues {
        var identifier: String?
        var message = ""
        var tags: [String] = []
        var type: GitGraphCommitType?
        var parent: String?

        mutating func set(_ attribute: GitGraphAttribute, to text: String) {
            switch attribute {
            case .identifier: identifier = text
            case .message: message = text
            case .tag: tags.append(text)
            case .parent: parent = text
            case .type, .order: break
            }
        }
    }
}
