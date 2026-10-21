import Foundation

/// Follows fenced code line by line, so a longer fence is not closed by a shorter one.
public struct CodeFenceTracker {
    private var openFence: String?

    public init() {}

    /// Whether the lines so far left a fence open.
    public var isInsideFence: Bool { openFence != nil }

    /// Whether this line belongs to fenced code, fences included. Call once per line, in order.
    public mutating func isCodeLine(_ trimmedLine: String) -> Bool {
        if let fence = openFence {
            if MarkdownFenceSyntax.closes(fence, trimmedLine) { openFence = nil }
            return true
        }
        guard let (fence, _) = MarkdownFenceSyntax.opening(trimmedLine) else { return false }
        openFence = fence
        return true
    }
}

extension CodeFenceTracker {
    /// `isCodeLine` for a line as written. Only a line whose first character after
    /// indentation is a backtick or tilde can open or close a fence, so other lines are
    /// answered without trimming them: long notes are scanned this way on every render.
    mutating func isCodeLine(untrimmedLine line: some StringProtocol) -> Bool {
        guard let firstCharacter = line.first(where: { character in !character.isWhitespace }),
              firstCharacter == "`" || firstCharacter == "~" else { return isInsideFence }
        return isCodeLine(line.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
