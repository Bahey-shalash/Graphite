import Foundation

/// Adapts note source for display so the preview matches Obsidian's reading view.
/// Only the preview copy changes; the note on disk is never rewritten.
public enum ObsidianPreviewText {
    /// Obsidian's default ("Strict line breaks" off) shows a single newline as a line
    /// break. Two trailing spaces express that in CommonMark. Code and math blocks,
    /// where spaces matter or have no meaning, are left untouched. CRLF line endings are
    /// kept: `components(separatedBy:)` splits "\r\n", which a Character split would
    /// treat as one indivisible line break.
    public static func applyingSoftLineBreaks(to body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        let mathLines = DisplayMathLines(lines.map { line in line.hasSuffix("\r") ? String(line.dropLast()) : line })
        var outputLines: [String] = []
        outputLines.reserveCapacity(lines.count)
        var fenceTracker = CodeFenceTracker()
        var mathClosingLineIndex: Int?
        for (lineIndex, line) in lines.enumerated() {
            let hasCarriageReturn = line.hasSuffix("\r")
            let content = hasCarriageReturn ? line.dropLast() : Substring(line)
            let unquoted = content.drop { character in character == ">" || character == " " || character == "\t" }
            let isBlockLine: Bool
            if let closingLineIndex = mathClosingLineIndex {
                isBlockLine = true
                if lineIndex >= closingLineIndex { mathClosingLineIndex = nil }
            } else if fenceTracker.isCodeLine(untrimmedLine: unquoted) {
                // Fences and everything between them are left exactly as written.
                isBlockLine = true
            } else if let opening = mathLines.opening(at: lineIndex) {
                isBlockLine = true
                mathClosingLineIndex = opening.closingLineIndex ?? lines.count
            } else {
                // A formula alone on its line, `$$x$$`.
                isBlockLine = unquoted.hasPrefix("$$") && unquoted.trimmingCharacters(in: .whitespaces).hasSuffix("$$")
            }
            let needsHardBreak = !isBlockLine && !unquoted.trimmingCharacters(in: .whitespaces).isEmpty
                && !content.hasSuffix("  ") && !content.hasSuffix("\\")
            outputLines.append(content + (needsHardBreak ? "  " : "") + (hasCarriageReturn ? "\r" : ""))
        }
        return outputLines.joined(separator: "\n")
    }
}
