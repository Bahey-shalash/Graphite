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
    case gitGraph(GitGraphDiagram)
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
        case "flowchart", "graph", "flowchart-elk": return .flowchart(titled(try FlowchartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "stateDiagram", "stateDiagram-v2": return .stateDiagram(titled(try StateDiagramParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "classDiagram", "classDiagram-v2": return .classDiagram(titled(try ClassDiagramParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "sequenceDiagram": return .sequence(titled(try SequenceParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "erDiagram": return .entityRelationship(titled(try EntityRelationshipParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "mindmap": return .mindmap(titled(try MindmapParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "timeline": return .timeline(titled(try TimelineParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "pie": return .pieChart(titled(try PieChartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "gantt": return .ganttChart(titled(try GanttChartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "gitGraph": return .gitGraph(titled(try GitGraphParser.parse(cursor, limits: limits), frontMatterTitle: title))
        default: throw .unsupportedDiagramType(keyword: keyword)
        }
    }

    /// `diagram` with the title its own `title` statement gives, else the front matter's, as in Mermaid.
    private static func titled<Diagram: TitledMermaidDiagram>(_ diagram: Diagram, frontMatterTitle: String?) -> Diagram {
        var titledDiagram = diagram
        if titledDiagram.title == nil { titledDiagram.title = frontMatterTitle }
        return titledDiagram
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
