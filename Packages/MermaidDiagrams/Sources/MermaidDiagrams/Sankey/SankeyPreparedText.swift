/// The text after a Sankey diagram's keyword as Mermaid prepares it for its CSV grammar: comment lines removed with
/// the blank lines just before them (Mermaid's comment pattern, `^\s*%%(?!{)[^\n]+\n?` over lines, takes them), the
/// whitespace at the end dropped, and each run of line breaks made one. The keyword's own line stays first, so the
/// rows start after a line break. Each line keeps the line of the diagram it comes from, for errors.
struct SankeyPreparedText {
    let bytes: [UInt8]
    /// Each prepared line's first byte and its line in the diagram's text, in order.
    private let lineStarts: [(offset: Int, line: Int)]

    /// A line of the diagram's text, between two line breaks: a carriage return breaks a line as a line feed does.
    private struct WrittenLine {
        let start: Int
        let end: Int
        let line: Int
    }

    init(after cursor: MermaidTextCursor) {
        let source = cursor.bytes
        var written = Self.lines(of: source, from: cursor.position, firstLine: cursor.line)
        written = [written[0]] + Self.withoutComments(Array(written.dropFirst()), in: source)
        while written.count > 1, let last = written.last, JavaScriptWhitespace.isBlank(source[last.start..<last.end]) { written.removeLast() }
        var bytes: [UInt8] = []
        var lineStarts: [(offset: Int, line: Int)] = []
        for (index, line) in written.enumerated() where index == 0 || line.end > line.start {
            if index > 0 { bytes.append(MermaidByte.newline) }
            lineStarts.append((bytes.count, line.line))
            bytes.append(contentsOf: source[line.start..<line.end])
        }
        while case let length = JavaScriptWhitespace.lengthOfLast(in: bytes), length > 0 { bytes.removeLast(length) }
        self.bytes = bytes
        self.lineStarts = lineStarts
    }

    /// The line of the diagram's text the prepared byte at `offset` comes from; a line break belongs to the line it ends.
    func line(at offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle].offset <= offset { low = middle } else { high = middle - 1 }
        }
        return lineStarts[low].line
    }

    private static func lines(of source: [UInt8], from start: Int, firstLine: Int) -> [WrittenLine] {
        var lines: [WrittenLine] = []
        var lineStart = start
        var line = firstLine
        for position in start..<source.count where source[position] == MermaidByte.newline || source[position] == MermaidByte.carriageReturn {
            lines.append(WrittenLine(start: lineStart, end: position, line: line))
            if source[position] == MermaidByte.newline { line += 1 }
            lineStart = position + 1
        }
        lines.append(WrittenLine(start: lineStart, end: source.count, line: line))
        return lines
    }

    /// The lines without each comment line and the blank lines right before it.
    private static func withoutComments(_ lines: [WrittenLine], in source: [UInt8]) -> [WrittenLine] {
        var kept: [WrittenLine] = []
        var index = 0
        while index < lines.count {
            var runEnd = index
            while runEnd < lines.count, JavaScriptWhitespace.isBlank(source[lines[runEnd].start..<lines[runEnd].end]) { runEnd += 1 }
            if runEnd < lines.count, isComment(source[lines[runEnd].start..<lines[runEnd].end]) {
                index = runEnd + 1
                continue
            }
            kept.append(contentsOf: lines[index..<min(runEnd + 1, lines.count)])
            index = runEnd + 1
        }
        return kept
    }

    /// `%%` after blanks, followed by something other than `{`.
    private static func isComment(_ line: ArraySlice<UInt8>) -> Bool {
        let content = line[JavaScriptWhitespace.endOfRun(in: line, from: line.startIndex)...]
        guard content.count > 2, content.first == MermaidByte.percent, content.dropFirst().first == MermaidByte.percent else { return false }
        return content.dropFirst(2).first != MermaidByte.openingBrace
    }
}
