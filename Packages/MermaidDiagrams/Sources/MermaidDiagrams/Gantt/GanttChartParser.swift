/// Reads a Gantt chart's statements after its `gantt` keyword, as Mermaid's Gantt grammar does: keywords are read
/// in any case; a setting's value runs to `#`, `;` or the end of the line, and a title or section to the end of the
/// line; any other text up to a colon is a task, whose data runs from the colon to `#`, `;` or the end of the line.
/// `%%`, a lone `%`, or a character then `%` at the start of a statement starts a comment.
struct GanttChartParser {
    private var cursor: MermaidTextCursor
    private var chart = GanttChart()
    private var unnamedTaskCount = 0
    private var currentSection = ""
    private let limits: MermaidDiagramLimits

    private init(cursor: MermaidTextCursor, limits: MermaidDiagramLimits) {
        self.cursor = cursor
        self.limits = limits
    }

    /// Reads the Gantt chart whose `gantt` keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> GanttChart {
        var parser = GanttChartParser(cursor: cursor, limits: limits)
        try parser.readStatements()
        return parser.chart
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while let byte = cursor.peek() {
            if byte == MermaidByte.newline || GanttStatementSyntax.isSpace(byte) {
                cursor.advance()
            } else if try GanttStatementSyntax.skipComment(&cursor) {
                continue
            } else {
                try readStatement()
            }
        }
    }

    private mutating func readStatement() throws(MermaidDiagramReadError) {
        let line = cursor.line
        let statementStart = cursor
        if try readAccessibilityOrClick() { return }
        if let (keyword, value) = GanttStatementSyntax.readKeywordStatement(&cursor) {
            guard keyword != .notAStatement else { throw .invalidSyntax(line: line, problem: .unexpectedText(statementStart.excerpt())) }
            apply(keyword, value: value)
            return
        }
        guard !GanttStatementSyntax.isAtDateOrColon(cursor) else { throw .invalidSyntax(line: line, problem: .unexpectedText(cursor.excerpt())) }
        let (name, data) = try GanttStatementSyntax.readTask(&cursor)
        try addTask(name: name, data: data, line: line)
    }

    /// `accTitle: …`, `accDescr: …`, `accDescr { … }` or `click …`, and whether the statement was one of them.
    private mutating func readAccessibilityOrClick() throws(MermaidDiagramReadError) -> Bool {
        if let title = GanttStatementSyntax.readAccessibilityLine(&cursor, keyword: Self.accessibilityTitle) {
            chart.accessibilityTitle = title
        } else if let description = GanttStatementSyntax.readAccessibilityLine(&cursor, keyword: Self.accessibilityDescription) {
            chart.accessibilityDescription = description
        } else if let description = try GanttStatementSyntax.readAccessibilityBlock(&cursor, keyword: Self.accessibilityDescription) {
            chart.accessibilityDescription = description
        } else if GanttStatementSyntax.isAtClick(cursor) {
            cursor.skipToEndOfLine()
            noteNotDrawn(.click)
        } else {
            return false
        }
        return true
    }

    private mutating func apply(_ keyword: GanttKeyword, value: String) {
        switch keyword {
        case .dateFormat: chart.dateFormat = value
        case .axisFormat: chart.axisFormat = value
        case .inclusiveEndDates: chart.isEndDateInclusive = true
        case .topAxis: chart.showsTopAxis = true
        case .tickInterval: chart.tickInterval = value
        case .excludes: chart.excludedDays = GanttStatementSyntax.merging(value, into: chart.excludedDays)
        case .includes: chart.includedDays = GanttStatementSyntax.merging(value, into: chart.includedDays)
        case .todayMarker: chart.todayMarker = value == "off" ? .hidden : .styled(value)
        case .weekday: chart.weekStart = GanttWeekday(name: value.lowercased()) ?? .sunday
        case .weekendFromFriday: chart.weekendStart = .friday
        case .weekendFromSaturday: chart.weekendStart = .saturday
        case .title: chart.title = value
        case .section:
            currentSection = value
            chart.sections.append(value)
        case .notAStatement: break // Refused before.
        }
    }

    private mutating func addTask(name: String, data: String, line: Int) throws(MermaidDiagramReadError) {
        guard chart.tasks.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        let fields = try GanttTaskFields(name: name, data: data, line: line)
        if fields.isVerticalMarker { noteNotDrawn(.verticalMarker) }
        let identifier = fields.identifier ?? nextUnnamedIdentifier()
        chart.tasks.append(GanttTask(name: name, section: currentSection, identifier: identifier, isDone: fields.isDone, isActive: fields.isActive,
                                     isCritical: fields.isCritical, isMilestone: fields.isMilestone, startText: fields.startText,
                                     endText: fields.endText, previousTaskIdentifier: chart.tasks.last?.identifier))
    }

    private mutating func nextUnnamedIdentifier() -> String {
        unnamedTaskCount += 1
        return "task\(unnamedTaskCount)"
    }

    private mutating func noteNotDrawn(_ statement: GanttStatementNotDrawn) {
        if !chart.statementsNotDrawn.contains(statement) { chart.statementsNotDrawn.append(statement) }
    }

    private static let accessibilityTitle = Array("acctitle".utf8)
    private static let accessibilityDescription = Array("accdescr".utf8)
}
