import Foundation

/// A diagram read from Mermaid text, by type.
public enum MermaidDiagram: Equatable, Sendable {
    case flowchart(FlowchartDiagram)
    case stateDiagram(StateDiagram)
    case classDiagram(ClassDiagram)
    case sequence(SequenceDiagram)
    case entityRelationship(EntityRelationshipDiagram)
    case mindmap(MindmapDiagram)
    case timeline(TimelineDiagram)
    case pieChart(PieChart)
    case ganttChart(GanttChart)
}

/// Reads Mermaid text: optional front matter (`---` … `---`, whose `title:` is kept), comments and directives
/// (`%%`, `%%{init: …}%%`), the keyword that names the diagram's type, and the diagram itself.
public enum MermaidDiagramReader {
    public static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> MermaidDiagram {
        guard source.utf8.count <= limits.maximumSourceBytes else { throw .sourceTooLarge(limitBytes: limits.maximumSourceBytes) }
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        if cursor.hasPrefix(byteOrderMark) { cursor.advance(by: byteOrderMark.count) }
        cursor.skipWhitespace()
        let title = try readFrontMatterTitle(&cursor)
        skipCommentsAndBlankLines(&cursor)
        guard let keyword = readTypeKeyword(&cursor) else {
            throw cursor.isAtEnd ? .noDiagram : .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
        }
        switch keyword {
        case "flowchart", "graph", "flowchart-elk":
            var diagram = try FlowchartParser.parse(cursor, limits: limits)
            diagram.title = title
            return .flowchart(diagram)
        case "stateDiagram", "stateDiagram-v2":
            var diagram = try StateDiagramParser.parse(cursor, limits: limits)
            diagram.title = title
            return .stateDiagram(diagram)
        case "classDiagram", "classDiagram-v2":
            var diagram = try ClassDiagramParser.parse(cursor, limits: limits)
            diagram.title = title
            return .classDiagram(diagram)
        case "sequenceDiagram":
            var diagram = try SequenceParser.parse(cursor, limits: limits)
            // A `title` statement in the diagram wins over the front matter's, as in Mermaid.
            if diagram.title == nil { diagram.title = title }
            return .sequence(diagram)
        case "erDiagram":
            var diagram = try EntityRelationshipParser.parse(cursor, limits: limits)
            diagram.title = title
            return .entityRelationship(diagram)
        case "mindmap":
            var diagram = try MindmapParser.parse(cursor, limits: limits)
            diagram.title = title
            return .mindmap(diagram)
        case "timeline":
            var diagram = try TimelineParser.parse(cursor, limits: limits)
            // A `title` statement in the diagram wins over the front matter's.
            diagram.title = diagram.title ?? title
            return .timeline(diagram)
        case "pie":
            var chart = try PieChartParser.parse(cursor, limits: limits)
            if chart.title == nil { chart.title = title }
            return .pieChart(chart)
        case "gantt":
            var chart = try GanttChartParser.parse(cursor, limits: limits)
            if chart.title == nil { chart.title = title }
            return .ganttChart(chart)
        default:
            throw .unsupportedDiagramType(keyword: keyword)
        }
    }

    /// Reads `---` … `---` at the cursor, and returns its top-level `title:` (without quotation marks), or nil.
    private static func readFrontMatterTitle(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String? {
        var lookahead = cursor
        guard lookahead.readRestOfLine() == "---" else { return nil }
        let openingLine = cursor.line
        var title: String?
        while true {
            guard !lookahead.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedFrontMatter) }
            lookahead.advance()
            let line = lookahead.readRestOfLine()
            if line == "---" { break }
            if line.hasPrefix("title:") {
                let value = line.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
                title = FlowchartTextSyntax.unquoted(value).text
            }
        }
        cursor = lookahead
        return title
    }

    private static func skipCommentsAndBlankLines(_ cursor: inout MermaidTextCursor) {
        while true {
            cursor.skipWhitespace()
            guard cursor.hasPrefix(commentStart) else { return }
            cursor.skipToEndOfLine()
        }
    }

    /// The keyword that names the type: a letter, then letters, digits and `-` (`stateDiagram-v2`).
    private static func readTypeKeyword(_ cursor: inout MermaidTextCursor) -> String? {
        guard let first = cursor.peek(), MermaidByte.isLetter(first) else { return nil }
        let start = cursor.position
        while let byte = cursor.peek(), MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.hyphen { cursor.advance() }
        return cursor.position > start ? cursor.text(from: start, to: cursor.position) : nil
    }

    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let commentStart = Array("%%".utf8)
}
