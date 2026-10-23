import XCTest
@testable import MermaidDiagrams

/// The tokens of Mermaid's XY chart grammar, as Pele's lexer gives them after the chart's keyword.
final class XYChartLexerTests: XCTestCase {
    private func kinds(_ afterKeyword: String) -> [XYChartTokenKind] {
        XYChartLexer.tokens(after: MermaidTextCursor(bytes: Array(afterKeyword.utf8))).map(\.kind)
    }

    func testNumbersAndTheArrowAreReadOnlyInAnAxisOrBetweenASeriesBrackets() {
        XCTAssertEqual(kinds(" x-axis -1.5 --> .5"), [.xAxis, .number, .arrow, .number, .endOfFile, .end])
        XCTAssertEqual(kinds(" line [+2, 3]"), [.line, .openingBracket, .number, .comma, .number, .closingBracket, .endOfFile, .end])
        XCTAssertEqual(kinds(" title -1.5"), [.title, .minus, .digits, .period, .digits, .endOfFile, .end])
        XCTAssertEqual(kinds(" x-axis [2014]"), [.xAxis, .openingBracket, .digits, .closingBracket, .endOfFile, .end], "A category is text")
    }

    func testALineBreakDirectlyAfterAnAxisEndsItAndOneAfterSpacesDoesNot() {
        XCTAssertEqual(kinds(" y-axis y\n 5"), [.yAxis, .letters, .newline, .digits, .endOfFile, .end])
        XCTAssertEqual(kinds(" y-axis y  \n 5"), [.yAxis, .letters, .number, .endOfFile, .end], "Still in the axis' statement")
        XCTAssertEqual(kinds(" bar [1]\r\n 5"), [.bar, .openingBracket, .number, .closingBracket, .newline, .digits, .endOfFile, .end])
    }

    func testACommentTakesTheCharacterBeforeIt() {
        XCTAssertEqual(kinds("\n%% note\n title a%%b\n"), [.newline, .title, .newline, .endOfFile, .end])
        XCTAssertEqual(kinds(" title é%% note"), [.title, .endOfFile, .end], "A character of two bytes is one unit for JavaScript")
    }

    func testKeywordsReadInAnyCaseAndTheOrientationInsideAWord() {
        XCTAssertEqual(kinds(" TITLE X-AXIS"), [.title, .xAxis, .endOfFile, .end])
        XCTAssertEqual(kinds(" titles"), [.letters, .endOfFile, .end])
        XCTAssertEqual(kinds(" verticals"), [.orientation, .letters, .endOfFile, .end])
    }

    func testStringsAndAccessibilityTextRunAcrossLines() {
        XCTAssertEqual(kinds(" title \"two\nlines\""), [.title, .string, .endOfFile, .end])
        XCTAssertEqual(kinds(" title \"open"), [.title, .string, .string, .end], "The grammar gives an empty string at the end of an open one")
        XCTAssertEqual(kinds(" accTitle\n: spoken\n"), [.accessibilityTitle, .accessibilityTitleValue, .newline, .endOfFile, .end])
        XCTAssertEqual(kinds(" accDescr { a\n b }"), [.accessibilityDescriptionBlockValue, .endOfFile, .end])
    }

    func testUnicodeSpacesAreSpacesAndOtherCharactersEndTheTokens() {
        XCTAssertEqual(kinds("\u{00A0}title\u{2003}a"), [.title, .letters, .endOfFile, .end])
        XCTAssertEqual(kinds(" title {"), [.title, .invalid])
    }
}
