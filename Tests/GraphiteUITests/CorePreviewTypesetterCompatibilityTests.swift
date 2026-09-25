import XCTest
import GraphiteCore
// The reading view draws math with SwiftUIMath, which GraphiteUI reaches through Textual.
// Its parser is internal, so it is imported for testing: it is the independent reader
// that decides whether a rewritten formula can be drawn.
@testable import SwiftUIMath

final class CorePreviewTypesetterCompatibilityTests: XCTestCase {
    func testRewrittenMathJaxFormulasParse() {
        let formulas = [
            "\\begin{eqnarray} a &=& b \\\\ c &=& d \\end{eqnarray}",
            "\\begin{eqnarray*} a &=& b \\\\ c &=& d \\end{eqnarray*}",
            "\\begin{alignat}{2} a &= b &\\quad c &= d \\end{alignat}",
            "\\begin{align*} x = 1 \\\\ y = 2 \\end{align*}",
            "\\begin{align} a &= b \\tag{1} \\\\ c &= d \\nonumber \\end{align}",
            "\\begin{flalign} a &= b & c &= d \\\\ e &= f & g &= h \\end{flalign}",
            "\\begin{aligned}x\\end{aligned}",
            "\\begin{align} A &= \\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix} \\\\ B &= 0 \\end{align}",
            "\\begin{align} a &= b \\\\[2pt] c &= d & e &= f \\end{align}",
            "x = 1 \\tag{\\ref{a}}",
            "\\begin{equation*} E = mc^2 \\label{eq:{energy}} \\end{equation*}",
        ]
        for formula in formulas {
            let normalized = LaTeXCompatibility.normalized(formula)
            var parserError: Math.ParserError?
            let atoms = Math.Parser.build(fromString: normalized, error: &parserError)
            XCTAssertNotNil(atoms, "\(formula) became \(normalized)")
            XCTAssertNil(parserError?.message, "\(formula) became \(normalized)")
        }
    }
}
