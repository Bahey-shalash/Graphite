import Foundation

/// Follows fenced code line by line, as CommonMark reads fences: a longer fence is not
/// closed by a shorter one, and a fence line indented more than
/// `MarkdownFenceSyntax.maximumIndentation` columns past its container (the content of the
/// list item holding it, or column 0) neither opens nor closes a fence. The tracker follows
/// list items itself, so every reader that walks a note line by line gets the indentation
/// limit by feeding it each line as written.
public struct CodeFenceTracker {
    private var openFence: String?
    /// Past this column, a line inside the open fence is code even when it repeats the fence.
    private var openFenceIndentationLimit = 0
    private var listItems = ListItemContainers()

    public init() {}

    /// Whether the lines so far left a fence open.
    public var isInsideFence: Bool { openFence != nil }

    /// Whether `line`, as written (indentation included, a line ending allowed), belongs to
    /// fenced code, fences included. Call once per line, in order. Long notes are scanned
    /// this way on every render and keystroke, so the line is read as bytes in place and
    /// trimmed into a new string only when its first visible character is a backtick or tilde.
    public mutating func isCodeLine(untrimmedLine line: some StringProtocol) -> Bool {
        // Most lines start with plain text, which is code only inside a fence: `step(past:)`
        // for `LineStart.plainText`, without reading the line further.
        if let firstByte = line.utf8.first, ListItemContainers.LineStart.startsPlainText(firstByte) {
            guard openFence == nil else { return true }
            // It reaches no list item's content and starts none.
            _ = listItems.containerColumn(of: .plainText)
            return false
        }
        switch step(past: ListItemContainers.LineStart(of: line)) {
        case .answered(let isCode): return isCode
        case .fenceCandidate(let lineStart, let containerColumn):
            return finishStep(past: lineStart, containerColumn: containerColumn, trimmedLine: line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// `isCodeLine(untrimmedLine:)` for a line's UTF-8 bytes, for a walk that reads a note as bytes.
    mutating func isCodeLine(utf8Line line: UnsafeBufferPointer<UInt8>) -> Bool {
        switch step(past: ListItemContainers.LineStart(utf8: line)) {
        case .answered(let isCode): isCode
        case .fenceCandidate(let lineStart, let containerColumn):
            finishStep(past: lineStart, containerColumn: containerColumn,
                       trimmedLine: String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private enum LineStep {
        case answered(isCode: Bool)
        /// The line may open or close a fence, which its text decides.
        case fenceCandidate(ListItemContainers.LineStart, containerColumn: Int)
    }

    private mutating func step(past line: ListItemContainers.LineStart) -> LineStep {
        if let openFence {
            // Indented further, or starting with another character, a line is the fence's content.
            guard line.indentation <= openFenceIndentationLimit, line.fenceCharacter == openFence.utf8.first else { return .answered(isCode: true) }
            return .fenceCandidate(line, containerColumn: 0)
        }
        let containerColumn = listItems.containerColumn(of: line)
        guard line.fenceCharacter != nil, line.indentation <= containerColumn + MarkdownFenceSyntax.maximumIndentation else {
            listItems.openListItem(of: line)
            return .answered(isCode: false)
        }
        return .fenceCandidate(line, containerColumn: containerColumn)
    }

    private mutating func finishStep(past line: ListItemContainers.LineStart, containerColumn: Int, trimmedLine: String) -> Bool {
        if let openFence {
            if MarkdownFenceSyntax.closes(openFence, trimmedLine) { self.openFence = nil }
            return true
        }
        guard let (fence, _) = MarkdownFenceSyntax.opening(trimmedLine) else {
            listItems.openListItem(of: line)
            return false
        }
        openFence = fence
        openFenceIndentationLimit = containerColumn + MarkdownFenceSyntax.maximumIndentation
        return true
    }
}
