import Foundation

/// The start of a note as its library tile shows it: what reading view would show first,
/// never the Markdown source. Made from a bounded prefix of the file, so a long note costs
/// no more than a short one.
public struct NotePreviewSummary: Equatable, Sendable {
    public enum Line: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(String)
        case task(isDone: Bool, text: String)
    }

    /// How much of a note is read for its tile.
    public static let maximumPrefixBytes = 4096
    /// A tile shows no more lines than this.
    public static let maximumLineCount = 14

    public let lines: [Line]
    /// The first picture embedded in the note's start (`![[photo.png]]`, `![](photo.png)`),
    /// as written; the tile resolves it like a link.
    public let firstPictureTarget: String?

    public init(lines: [Line], firstPictureTarget: String?) {
        self.lines = lines
        self.firstPictureTarget = firstPictureTarget
    }

    private static let pictureExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]

    /// The summary of a note's first bytes. `isWholeFile` is false when the text was cut at
    /// `maximumPrefixBytes`; a frontmatter block still open at the cut then hides everything.
    public static func summary(ofPrefix prefix: String, isWholeFile: Bool) -> NotePreviewSummary {
        let text = prefix as NSString
        let frontmatterLength = FrontmatterLocator.length(in: text)
        if frontmatterLength == 0, !isWholeFile, prefix.hasPrefix("---\n") || prefix.hasPrefix("---\r\n") {
            return NotePreviewSummary(lines: [], firstPictureTarget: nil)
        }
        var lines: [Line] = []
        var firstPictureTarget: String?
        var isInFence = false, isInMath = false
        let body = text.substring(from: frontmatterLength)
        var sourceLines = body.components(separatedBy: .newlines)
        // A line cut at the end of the prefix is not shown half.
        if !isWholeFile, sourceLines.count > 1 { sourceLines.removeLast() }
        for sourceLine in sourceLines where lines.count < maximumLineCount {
            let trimmed = sourceLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { isInFence.toggle(); continue }
            if trimmed == "$$" { isInMath.toggle(); continue }
            if isInFence || isInMath || trimmed.isEmpty || trimmed.hasPrefix("%%") { continue }
            if let target = embedTarget(of: trimmed) {
                if firstPictureTarget == nil, pictureExtensions.contains((target as NSString).pathExtension.lowercased()) { firstPictureTarget = target }
                continue
            }
            if let line = line(from: trimmed) { lines.append(line) }
        }
        return NotePreviewSummary(lines: lines, firstPictureTarget: firstPictureTarget)
    }

    private static func line(from trimmed: String) -> Line? {
        var content = Substring(trimmed)
        // Quotes and callouts show their text.
        while content.hasPrefix(">") { content = content.dropFirst().drop { character in character == " " } }
        if content.hasPrefix("[!"), let close = content.firstIndex(of: "]") {
            let title = content[content.index(after: close)...].drop { character in character == "-" || character == "+" || character == " " }
            content = title.isEmpty ? content[content.index(content.startIndex, offsetBy: 2)..<close] : title
        }
        let headingMarks = content.prefix { character in character == "#" }
        if (1...6).contains(headingMarks.count), content.dropFirst(headingMarks.count).first == " " {
            return .heading(level: headingMarks.count, text: plainText(content.dropFirst(headingMarks.count + 1)))
        }
        for (marker, isDone) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [ ] ", false), ("* [x] ", true)] where content.hasPrefix(marker) {
            return .task(isDone: isDone, text: plainText(content.dropFirst(marker.count)))
        }
        if content.hasPrefix("- ") || content.hasPrefix("* ") || content.hasPrefix("+ ") {
            return .listItem(plainText(content.dropFirst(2)))
        }
        if let dot = content.firstIndex(of: "."), content[..<dot].allSatisfy(\.isNumber), !content[..<dot].isEmpty,
           content[content.index(after: dot)...].first == " " {
            return .listItem(plainText(content[content.index(dot, offsetBy: 2)...]))
        }
        if content.allSatisfy({ character in character == "-" || character == "*" || character == "_" || character == " " }) { return nil }
        let text = plainText(content)
        return text.isEmpty ? nil : .paragraph(text)
    }

    /// The target of a line that is only an embed, as written.
    private static func embedTarget(of trimmed: String) -> String? {
        if trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") {
            let inner = trimmed.dropFirst(3).dropLast(2)
            return String(inner.split(separator: "|", maxSplits: 1).first ?? inner).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("!["), trimmed.hasSuffix(")"), let open = trimmed.range(of: "](") {
            let destination = trimmed[open.upperBound..<trimmed.index(before: trimmed.endIndex)]
            let target = destination.split(separator: " ", maxSplits: 1).first.map(String.init) ?? String(destination)
            return target.removingPercentEncoding ?? target
        }
        return nil
    }

    /// Text without inline Markdown: links show their label, emphasis and code marks go.
    static func plainText<Text: StringProtocol>(_ source: Text) -> String {
        var output = ""
        var index = source.startIndex
        while index < source.endIndex {
            let rest = source[index...]
            if rest.hasPrefix("[["), let close = rest.range(of: "]]") {
                let inner = rest[rest.index(index, offsetBy: 2)..<close.lowerBound]
                let parts = inner.split(separator: "|", maxSplits: 1)
                output += String(parts.count == 2 ? parts[1] : (inner.split(separator: "#").first ?? inner))
                index = close.upperBound
                continue
            }
            if rest.hasPrefix("!["), let close = rest.range(of: ")") { index = close.upperBound; continue }
            if rest.hasPrefix("["), let middle = rest.range(of: "]("), let close = rest[middle.upperBound...].firstIndex(of: ")") {
                output += rest[rest.index(after: index)..<middle.lowerBound]
                index = rest.index(after: close)
                continue
            }
            let character = source[index]
            if "*_`=~".contains(character) {
                index = source.index(after: index)
                continue
            }
            output.append(character)
            index = source.index(after: index)
        }
        return output.trimmingCharacters(in: .whitespaces)
    }
}
