import XCTest
@testable import GraphiteCore

/// Inside display math, a line ending in `\$$` holds an escaped dollar and a lone `$`, no
/// closing delimiter, so the block stays open to the next `$$`, as `DisplayMathLines` (the
/// owner of the rule) and Live Preview read it (`LSP-MDCORE-01`).
final class DisplayMathEscapedDollarTests: XCTestCase {
    private let note = "$$\nx = \\$$\nstill math\n$$\nAfter"

    func testEditorStylesTheLineAfterAnEscapedDollarAsMath() {
        let text = note as NSString
        let stillMathLine = text.range(of: "still math")
        let styles = MarkdownStyleScanner.spans(in: text, range: NSRange(location: 0, length: text.length))
            .filter { span in NSIntersectionRange(span.range, stillMathLine).length > 0 }.map(\.style)
        XCTAssertEqual(styles, [.math])
    }

    func testEditorStylesTheTextAfterTheClosingDelimiterAsText() {
        let text = note as NSString
        let afterLine = text.range(of: "After")
        let styles = MarkdownStyleScanner.spans(in: text, range: NSRange(location: 0, length: text.length))
            .filter { span in NSIntersectionRange(span.range, afterLine).length > 0 }.map(\.style)
        XCTAssertFalse(styles.contains(.math))
    }

    func testBlockReferencesReadTheFormulaThroughItsClosingDelimiter() {
        let mathBlocks = NoteBlocks.blocks(in: note).filter { block in block.kind == .math }.map(\.text)
        XCTAssertEqual(mathBlocks, ["$$\nx = \\$$\nstill math\n$$"])
    }

    func testColorMarkersOnTheLineAfterAnEscapedDollarAreFormulaText() {
        let text = "$$\nx = \\$$\n~={#ff0000}still math=~\n$$\nAfter" as NSString
        XCTAssertTrue(TextColorMarkup.sections(in: text).isEmpty)
    }
}
