import XCTest
import SwiftUI
@testable import Textual

/// Regression tests for the patches Graphite carries in its vendored Textual
/// (Vendor/textual/GRAPHITE-PATCHES.md). Upstream Textual's own tests are not vendored.
@MainActor
final class AppProjectTextualPatchTests: XCTestCase {
    private static let objectReplacementCharacter: Character = "\u{FFFC}"

    private func inlineMathFormulas(in text: String) throws -> [String] {
        try PatternTokenizer(patterns: [.mathBlock, .mathInline]).tokenize(text)
            .filter { token in token.type == .mathInline }
            .compactMap(\.capturedContent)
    }

    private func mathAttachmentCount(inMarkdown markdown: String) throws -> Int {
        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        return String(try parser.attributedString(for: markdown).characters)
            .filter { character in character == Self.objectReplacementCharacter }.count
    }

    // MARK: Patch 4, Obsidian's inline math delimiters

    func testInlineMathNeedsNoSpaceInsideTheDollarsAndNoDigitAfterTheClosingOne() throws {
        XCTAssertEqual(try inlineMathFormulas(in: "$x$"), ["x"])
        XCTAssertEqual(try inlineMathFormulas(in: "$x_1$, $x_2$"), ["x_1", "x_2"])
        XCTAssertEqual(try inlineMathFormulas(in: "It costs $5 and $10"), [])
        XCTAssertEqual(try inlineMathFormulas(in: "$x$2"), [])
        XCTAssertEqual(try inlineMathFormulas(in: "$ x$ and $x $"), [])
        XCTAssertEqual(try inlineMathFormulas(in: "a \\$ sign: $\\$5$"), ["\\$5"])
    }

    func testPricesStayTextWhileFormulasBecomeAttachments() throws {
        XCTAssertEqual(try mathAttachmentCount(inMarkdown: "It costs $5 and $10."), 0)
        XCTAssertEqual(try mathAttachmentCount(inMarkdown: "Energy $E = mc^2$ and $k_n$."), 2)
    }

    // MARK: Patch 5, formulas that cannot be typeset stay as text

    func testUnparseableFormulaStaysAsItsSource() throws {
        XCTAssertTrue(MathAttachment.canTypeset("x^2"))
        XCTAssertFalse(MathAttachment.canTypeset("\\begin{notanenvironment}x\\end{notanenvironment}"))
        let markdown = "See $\\begin{notanenvironment}x\\end{notanenvironment}$ here."
        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        XCTAssertEqual(String(try parser.attributedString(for: markdown).characters), markdown)
    }

    // MARK: Patch 3, inline math for other text views

    func testInlineMathRenderingMeasuresFormulasAndRejectsUnparseableOnes() {
        let metrics = InlineMathRendering.metrics(for: "x^2", fontSize: 17)
        XCTAssertGreaterThan(metrics?.width ?? 0, 0)
        XCTAssertGreaterThan(metrics?.ascent ?? 0, 0)
        XCTAssertNil(InlineMathRendering.metrics(for: "\\begin{notanenvironment}x\\end{notanenvironment}", fontSize: 17))
    }

    // MARK: Patch 1, math keeps its natural width

    func testInlineMathKeepsItsNaturalWidthInANarrowProposal() {
        let attachment = MathAttachment(latex: "k_n", style: .inline)
        let environment = TextEnvironmentValues()
        let naturalSize = attachment.sizeThatFits(.unspecified, in: environment)
        XCTAssertGreaterThan(naturalSize.width, 0)
        let narrowSize = attachment.sizeThatFits(ProposedViewSize(width: naturalSize.width / 2, height: nil), in: environment)
        XCTAssertEqual(narrowSize, naturalSize)
    }

    /// The view draws display math at its natural width when it overhangs the column by
    /// up to a point; the measurement used to refit it (and reserve the wrapped height)
    /// as soon as it overhung at all.
    func testDisplayMathOverhangingByLessThanTheToleranceIsMeasuredAtItsNaturalSize() {
        let attachment = MathAttachment(latex: "a + b + c + d + e + f + g + h + i + j + k + l + m + n", style: .block)
        let environment = TextEnvironmentValues()
        let naturalSize = attachment.sizeThatFits(.unspecified, in: environment)
        XCTAssertGreaterThan(naturalSize.width, 0)
        let slightOverhang = MathAttachment.naturalWidthTolerance / 2
        let almostWideEnough = ProposedViewSize(width: naturalSize.width - slightOverhang, height: nil)
        XCTAssertEqual(attachment.sizeThatFits(almostWideEnough, in: environment), naturalSize)
        let halfWidth = ProposedViewSize(width: naturalSize.width / 2, height: nil)
        let wrappedSize = attachment.sizeThatFits(halfWidth, in: environment)
        XCTAssertNotEqual(wrappedSize, naturalSize, "Display math genuinely wider than the column still wraps.")
    }
}
