import XCTest
@testable import MermaidDiagrams

/// How the quadrant chart's text is cut into tokens, as Mermaid's quadrant lexer cuts it.
final class QuadrantChartLexerTests: XCTestCase {
    private func kinds(_ statements: String) throws -> [QuadrantChartTokenKind] {
        try tokens(statements).map(\.kind)
    }

    private func tokens(_ statements: String) throws -> [QuadrantChartToken] {
        var cursor = MermaidTextCursor(bytes: Array(("quadrantChart" + statements).utf8))
        cursor.advance(by: "quadrantChart".utf8.count)
        return try QuadrantChartLexer.tokens(after: cursor)
    }

    func testKeywordsAndTheArrowTakeTheSpacesAroundThem() throws {
        let tokens = try tokens("\n  x-axis  Low   --->  High")
        XCTAssertEqual(tokens.map(\.kind), [.lineBreak, .xAxis, .letters, .axisArrow, .letters])
        XCTAssertEqual(tokens[1].start, "quadrantChart\n".utf8.count, "From the first space")
        XCTAssertEqual(tokens[3].end, tokens[4].start, "To the next text")
    }

    func testTextIsCutIntoRunsAndSingleCharacters() throws {
        XCTAssertEqual(try kinds("\nquadrant-1 Été 2-b, a_c&*#!"),
                       [.lineBreak, .quadrant1, .otherCharacters, .letters, .otherCharacters, .space, .digits, .hyphen, .letters, .comma, .space,
                        .letters, .otherPunctuation, .letters, .ampersand, .asterisk, .numberSign, .otherPunctuation])
    }

    func testAQuadrantNeedsItsDigitAndAWordItsEnd() throws {
        XCTAssertEqual(try kinds("\nquadrant-5"), [.lineBreak, .letters, .hyphen, .digits])
        XCTAssertEqual(try kinds("\ntitles"), [.lineBreak, .letters])
        XCTAssertEqual(try tokens("\ntitle  Hi").last?.content, .text("  Hi"))
    }

    func testAPointHoldsItsCoordinatesAsWritten() throws {
        let tokens = try tokens(" A \n : \n [ 0.25 ,1 ]  radius")
        XCTAssertEqual(tokens.map(\.kind), [.space, .letters, .point, .letters])
        XCTAssertEqual(tokens[2].content, .coordinates(xCoordinate: "0.25", yCoordinate: "1"))
    }

    func testCommentsTakeTheRestOfTheirLineAndTheCharacterBeforeThem() throws {
        XCTAssertEqual(try kinds("\n%% all of it\nA %% the rest"), [.lineBreak, .letters], "The line break before a comment goes with it")
        XCTAssertEqual(try kinds("\nA%% the rest"), [.lineBreak], "A character that starts a token just before %% goes with the comment, as in Mermaid")
    }

    func testACharacterNoRuleTakesIsAnError() {
        XCTAssertThrowsError(try kinds("\n  [x]")) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .invalidSyntax(line: 2, problem: .unexpectedText("[x]")))
        }
    }
}
