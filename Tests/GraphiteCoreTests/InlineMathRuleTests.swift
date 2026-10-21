import XCTest
@testable import GraphiteCore

/// The editor, the reading view and text colors find inline math with one rule, so a
/// formula holding an escaped dollar is one formula for all three (`LSP-MDCORE-01`).
final class InlineMathRuleTests: XCTestCase {
    func testEditorStylesAFormulaWithAnEscapedDollarAsOneFormula() {
        let text = "Pay $a\\$b$ now" as NSString
        let mathRanges = MarkdownStyleScanner.spans(in: text, range: NSRange(location: 0, length: text.length))
            .filter { span in span.style == .math }.map(\.range)
        XCTAssertEqual(mathRanges, [NSRange(location: 4, length: 6)])
    }

    func testReadingViewProtectsAFormulaWithAnEscapedDollarAsOneFormula() {
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "Pay $a\\$b$ now"), "Pay $a\\\\\\$b$ now")
    }

    func testColorMarkersInsideAFormulaWithAnEscapedDollarAreFormulaText() {
        XCTAssertTrue(TextColorMarkup.sections(in: "Pay $a\\$b ~={#ff0000}x=~ c$ now" as NSString).isEmpty)
    }

    func testInlineMathFollowsObsidiansDelimiterRules() {
        func latex(_ line: String) -> [String] {
            MarkdownInlineMathSyntax.formulas(in: line, range: NSRange(location: 0, length: (line as NSString).length)).map { formula in
                (line as NSString).substring(with: formula.latexRange)
            }
        }
        XCTAssertEqual(latex("$x$ and $y^2$"), ["x", "y^2"])
        XCTAssertEqual(latex("Costs $5 and $10 today"), [], "A digit after the closing `$` makes both prices.")
        XCTAssertEqual(latex("$ x$ and $x $"), [], "No whitespace just inside either `$`.")
        XCTAssertEqual(latex("\\$x$"), [], "An escaped `$` opens nothing.")
        XCTAssertEqual(latex("$$x$$"), [], "`$$` is display math.")
        XCTAssertEqual(latex("$a\\$b$"), ["a\\$b"], "An escaped `$` is part of the formula.")
        XCTAssertEqual(latex("$a\\\\$"), ["a\\\\"], "An escaped backslash before the closing `$` does not escape it.")
        XCTAssertEqual(latex("$a\nb$"), [], "A formula stays on one line.")
    }

    /// The reading view finds `$$…$$` and `$…$` in one pass for speed; its inline half is
    /// the owner's rule, written out.
    func testReadingViewMathPatternEndsWithTheInlineMathRule() {
        XCTAssertTrue(ObsidianInlineMarkupPattern.mathSpanPattern.rawValue.hasSuffix("|" + MarkdownInlineMathPattern.formula.rawValue))
    }

    func testReadingViewProtectsAFormulaEndingInAnEscapedBackslash() {
        XCTAssertEqual(ObsidianInlineMarkup.protectingMath(in: "Set $a\\\\$ here"), "Set $a\\\\\\\\$ here")
    }
}
