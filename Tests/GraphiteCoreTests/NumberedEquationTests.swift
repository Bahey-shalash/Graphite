import XCTest
@testable import GraphiteCore

/// Equation numbers as Obsidian's MathJax draws them: only where `\tag` asks, since
/// Obsidian leaves MathJax's `tags` option at `none`.
final class NumberedEquationTests: XCTestCase {
    func testTagNumbersAWholeFormula() throws {
        let equation = try XCTUnwrap(LaTeXCompatibility.numberedEquation("E = mc^2 \\tag{1}"))
        XCTAssertEqual(equation.latex, LaTeXCompatibility.normalized("E = mc^2 "))
        XCTAssertEqual(equation.tags, [NumberedEquation.Tag(rowIndex: nil, content: "1", hasParentheses: true)])
        XCTAssertEqual(equation.rows, [])
        XCTAssertEqual(equation.tags[0].text, "(1)")
        XCTAssertEqual(equation.tags[0].latex, "\\text{(}\\text{1}\\text{)}")
    }

    func testStarredTagHasNoParentheses() throws {
        let equation = try XCTUnwrap(LaTeXCompatibility.numberedEquation("F = ma \\tag*{Newton}"))
        XCTAssertEqual(equation.tags.first?.text, "Newton")
        XCTAssertEqual(equation.tags.first?.latex, "\\text{Newton}")
    }

    func testMathInATagIsTypesetAsMath() throws {
        let equation = try XCTUnwrap(LaTeXCompatibility.numberedEquation("x \\tag{$\\ast$ 2}"))
        XCTAssertEqual(equation.tags.first?.latex, "\\text{(}\\ast\\text{ 2}\\text{)}")
        let nested = try XCTUnwrap(LaTeXCompatibility.numberedEquation("x \\tag{a{b}c}"))
        XCTAssertEqual(nested.tags.first?.content, "a{b}c")
        XCTAssertEqual(nested.latex, "x ")
    }

    func testNothingIsNumberedWithoutATag() {
        // MathJax numbers environments by itself only with `tags: 'ams'`, which Obsidian does not set.
        for latex in ["\\begin{equation} E = mc^2 \\end{equation}", "\\begin{align} a &= b \\\\ c &= d \\end{align}",
                      "\\begin{gather} a \\\\ b \\notag \\end{gather}", "\\begin{align*} a &= b \\nonumber \\end{align*}", "x = 1", "\\tagged{x}"] {
            XCTAssertNil(LaTeXCompatibility.numberedEquation(latex), latex)
        }
    }

    func testEquationEnvironmentNumbersItsWholeFormula() throws {
        let equation = try XCTUnwrap(LaTeXCompatibility.numberedEquation("\\begin{equation}\\begin{split} a &= b \\\\ &= c \\end{split} \\tag{3.1}\\end{equation}"))
        XCTAssertEqual(equation.rows, [], "The number stands beside the whole split formula.")
        XCTAssertEqual(equation.tags.map(\.content), ["3.1"])
        XCTAssertEqual(equation.latex, LaTeXCompatibility.normalized("\\begin{equation}\\begin{split} a &= b \\\\ &= c \\end{split} \\end{equation}"))
    }

    func testEachRowOfAnAlignmentTakesItsOwnNumber() throws {
        let latex = "\\begin{align} a &= b \\tag{1} \\\\ c &= \\frac{d}{e} \\notag \\\\ f &= g \\tag*{A} \\end{align}"
        let equation = try XCTUnwrap(LaTeXCompatibility.numberedEquation(latex))
        XCTAssertEqual(equation.tags, [NumberedEquation.Tag(rowIndex: 0, content: "1", hasParentheses: true),
                                       NumberedEquation.Tag(rowIndex: 2, content: "A", hasParentheses: false)])
        XCTAssertEqual(equation.rows.map(\.latex), [" a  = b  ", " c  = \\frac{d}{e}  ", " f  = g  "])
        // The formula is drawn exactly as without its numbers.
        XCTAssertEqual(equation.latex, LaTeXCompatibility.normalized(latex))
        XCTAssertEqual(equation.latex, "\\begin{aligned} a &= b  \\\\ c &= \\frac{d}{e}  \\\\ f &= g  \\end{aligned}")
    }

    func testStarredAndOtherRowEnvironmentsNumberTheirRows() throws {
        for (latex, rowIndices) in [("\\begin{align*} a &= b \\\\ c &= d \\tag{2} \\end{align*}", [1]),
                                    ("\\begin{gather} a \\tag{1} \\\\ b \\tag{2} \\end{gather}", [0, 1]),
                                    ("\\begin{gather*} a \\\\ b \\tag{2} \\end{gather*}", [1]),
                                    ("\\begin{eqnarray} a &=& b \\tag{1} \\\\ c &=& d \\end{eqnarray}", [0]),
                                    ("\\begin{flalign} a &= b & c &= d \\tag{1} \\end{flalign}", [0]),
                                    ("\\begin{alignat}{2} a &= b &\\quad c &= d \\tag{1} \\end{alignat}", [0])] as [(String, [Int])] {
            let equation = try XCTUnwrap(LaTeXCompatibility.numberedEquation(latex), latex)
            XCTAssertEqual(equation.tags.map(\.rowIndex), rowIndices, latex)
            XCTAssertFalse(equation.rows.isEmpty, latex)
            XCTAssertEqual(equation.latex, LaTeXCompatibility.normalized(latex), latex)
        }
    }

    func testMultlineHasOneNumberOnItsLastRow() throws {
        let equation = try XCTUnwrap(LaTeXCompatibility.numberedEquation("\\begin{multline} a + b \\tag{7} \\\\ + c \\\\ + d \\end{multline}"))
        XCTAssertEqual(equation.tags, [NumberedEquation.Tag(rowIndex: 2, content: "7", hasParentheses: true)])
    }

    func testRowKeepsItsFirstTag() throws {
        // MathJax reports "Multiple \tag" as an error; the formula here keeps the first.
        let equation = try XCTUnwrap(LaTeXCompatibility.numberedEquation("x \\tag{1} \\tag{2}"))
        XCTAssertEqual(equation.tags.map(\.content), ["1"])
        XCTAssertEqual(equation.latex, "x  ")
    }

    func testStackedRowsAreAGatherOfTheRowsDownToOne() throws {
        let equation = try XCTUnwrap(LaTeXCompatibility.numberedEquation("\\begin{align} a &= b \\tag{1} \\\\ c &= d \\\\ e &= f \\end{align}"))
        XCTAssertEqual(equation.stackedRowsLatex(through: 0), "\\begin{gather} a  = b  \\end{gather}")
        XCTAssertEqual(equation.stackedRowsLatex(through: 2), "\\begin{gather} a  = b  \\\\ c  = d \\\\ e  = f \\end{gather}")
    }

    func testNumbersGoAfterTheirRowsWhereTheyCannotStandAtTheRight() throws {
        let single = try XCTUnwrap(LaTeXCompatibility.numberedEquation("x \\tag{1}"))
        XCTAssertEqual(single.latexWithTagsInline, "x  \\qquad \\text{(}\\text{1}\\text{)}")
        let rows = try XCTUnwrap(LaTeXCompatibility.numberedEquation("\\begin{align} a &= b \\tag{1} \\\\ c &= d \\end{align}"))
        XCTAssertEqual(rows.latexWithTagsInline, "\\begin{aligned} a &= b   \\qquad \\text{(}\\text{1}\\text{)}\\\\ c &= d \\end{aligned}")
    }

    // MARK: In text prepared for reading

    func testDisplayFormulaWithANumberKeepsItsSourceBetweenMarkers() throws {
        for markdown in ["$$\nE = mc^2 \\tag{1}\n$$", "$$E = mc^2 \\tag{1}$$", "$$\n\\begin{align}\na &= b \\tag{1} \\\\\nc &= d \\tag{2}\n\\end{align}\n$$"] {
            let prepared = ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: true, paletteHexByName: [:])
            XCTAssertTrue(prepared.hasPrefix(String(ObsidianInlineMarkup.numberedEquationStartMarker)), markdown)
            XCTAssertFalse(prepared.contains("$$"))
            // Soft line breaks add spaces after the line; the formula is still all of the text.
            let equation = try XCTUnwrap(ObsidianInlineMarkup.numberedEquation(aloneIn: ObsidianPreviewText.applyingSoftLineBreaks(to: prepared)), markdown)
            let latex = markdown.replacingOccurrences(of: "$$", with: "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            XCTAssertEqual(equation, LaTeXCompatibility.numberedEquation(latex), markdown)
        }
    }

    func testFormulaWithoutANumberIsPreparedAsBefore() {
        XCTAssertEqual(ObsidianInlineMarkup.preparedForReading("$$\nE = mc ^2\n$$", colorsEnabled: false, paletteHexByName: [:]), "$$ E \\= mc \\^2 $$")
        XCTAssertEqual(ObsidianInlineMarkup.preparedForReading("$$E=mc^2$$", colorsEnabled: false, paletteHexByName: [:]), "$$E\\=mc\\^2$$")
    }

    func testInlineMathAndFormulasInTableCellsHaveNoNumbers() {
        // MathJax gives a number only to display math; a table cell draws its formula inline.
        XCTAssertEqual(ObsidianInlineMarkup.preparedForReading("Inline $x \\tag{1}$ here", colorsEnabled: false, paletteHexByName: [:]), "Inline $x $ here")
        XCTAssertEqual(ObsidianInlineMarkup.preparedForReading("| $$x \\tag{1}$$ | b |", colorsEnabled: false, paletteHexByName: [:]), "| $x $ | b |")
    }

    func testNumberedFormulaAmongOtherTextIsNotAloneAndTakesItsNumberInline() throws {
        let prepared = ObsidianInlineMarkup.preparedForReading("- item\n  $$\n  x^2 \\tag{1}\n  $$", colorsEnabled: false, paletteHexByName: [:])
        XCTAssertNil(ObsidianInlineMarkup.numberedEquation(aloneIn: prepared))
        let inlined = ObsidianInlineMarkup.inliningEquationNumbers(in: prepared)
        XCTAssertFalse(inlined.contains(ObsidianInlineMarkup.numberedEquationStartMarker))
        XCTAssertTrue(inlined.contains("$$ x\\^2  \\\\qquad \\\\text\\{\\(\\}\\\\text\\{1\\}\\\\text\\{\\)\\} $$"), inlined)
    }

    func testCodeIsNotAFormula() {
        let markdown = "```\n$$\nx \\tag{1}\n$$\n```\n`$$x \\tag{1}$$`"
        XCTAssertEqual(ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: false, paletteHexByName: [:]), markdown)
    }

    func testMarkerCharactersWrittenInANoteAreNotReadAsAFormula() {
        let prepared = ObsidianInlineMarkup.preparedForReading("\u{E00A}x \\tag{1}\u{E00B}", colorsEnabled: false, paletteHexByName: [:])
        XCTAssertNil(ObsidianInlineMarkup.numberedEquation(aloneIn: prepared))
        XCTAssertEqual(prepared, "\u{FFFD}x \\tag{1}\u{FFFD}")
    }
}
