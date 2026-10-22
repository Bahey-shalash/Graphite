import XCTest
@testable import MermaidDiagrams

final class MermaidAccessibilityStatementTests: XCTestCase {
    private func read(_ text: String) throws -> (MermaidAccessibilityStatement?, remainder: String) {
        var cursor = MermaidTextCursor(bytes: Array(text.utf8))
        let statement = try MermaidAccessibilityStatement.read(&cursor)
        return (statement, cursor.text(from: cursor.position, to: cursor.bytes.count))
    }

    func testATitleOrADescriptionRunsToTheEndOfItsLine() throws {
        XCTAssertEqual(try read("accTitle: Plans &amp; goals  \nnext").0, .title("Plans & goals"))
        XCTAssertEqual(try read("accTitle: Plans\nnext").remainder, "\nnext")
        XCTAssertEqual(try read("ACCDESCR :Upper case").0, .description("Upper case"))
    }

    func testABracedDescriptionJoinsItsLines() throws {
        let (statement, remainder) = try read("accDescr {\n  First line\n  second line\n} after")
        XCTAssertEqual(statement, .description("First line second line"))
        XCTAssertEqual(remainder, " after")
    }

    func testAKeywordWithoutAColonIsNoStatementAndMovesNothing() throws {
        let (statement, remainder) = try read("accTitle of a node")
        XCTAssertNil(statement)
        XCTAssertEqual(remainder, "accTitle of a node")
        XCTAssertNil(try read("accTitle { braces are for descriptions }").0)
    }

    func testAnUnclosedDescriptionIsReportedOnItsLine() {
        XCTAssertThrowsError(try read("accDescr {\n  never closed")) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .invalidSyntax(line: 1, problem: .unclosedAccessibilityDescription))
        }
    }
}
