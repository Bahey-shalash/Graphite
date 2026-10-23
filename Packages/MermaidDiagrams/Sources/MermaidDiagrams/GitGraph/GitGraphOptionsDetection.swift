/// Finds whether a diagram's front matter or a directive sets options of Git graphs: the key `gitGraph` followed by a
/// colon, after a closing quotation mark and spaces where they stand, as YAML front matter (`gitGraph:`) and a
/// directive's JSON (`'gitGraph': {`) write it. The options are not read: a graph that has them is refused by its layout.
enum GitGraphOptionsDetection {
    /// Whether `bytes` hold the key.
    static func setsOptions(in bytes: ArraySlice<UInt8>) -> Bool {
        var index = bytes.startIndex
        while index + key.count <= bytes.endIndex {
            if bytes[index..<(index + key.count)].elementsEqual(key), isFollowedByColon(bytes, from: index + key.count) { return true }
            index += 1
        }
        return false
    }

    /// Whether the text before the diagram's keyword, which ends at `keywordStart`, sets options in its front matter
    /// or in a directive: in any of its lines but `%%` comments.
    static func setsOptions(inTextBefore keywordStart: Int, of bytes: [UInt8]) -> Bool {
        var lineStart = 0
        while lineStart < keywordStart {
            var lineEnd = lineStart
            while lineEnd < keywordStart, bytes[lineEnd] != MermaidByte.newline { lineEnd += 1 }
            var textStart = lineStart
            while textStart < lineEnd, MermaidByte.isSpace(bytes[textStart]) { textStart += 1 }
            let line = bytes[textStart..<lineEnd]
            let isComment = line.starts(with: commentStart) && !line.starts(with: directiveStart)
            if !isComment, setsOptions(in: line) { return true }
            lineStart = lineEnd + 1
        }
        return false
    }

    /// A colon after the key, past a closing quotation mark or apostrophe and spaces.
    private static func isFollowedByColon(_ bytes: ArraySlice<UInt8>, from start: Int) -> Bool {
        var index = start
        if index < bytes.endIndex, bytes[index] == MermaidByte.quotationMark || bytes[index] == apostrophe { index += 1 }
        while index < bytes.endIndex, MermaidByte.isSpace(bytes[index]) { index += 1 }
        return index < bytes.endIndex && bytes[index] == MermaidByte.colon
    }

    private static let key = Array("gitGraph".utf8)
    private static let commentStart = Array("%%".utf8)
    private static let directiveStart = Array("%%{".utf8)
    private static let apostrophe = UInt8(ascii: "'")
}
