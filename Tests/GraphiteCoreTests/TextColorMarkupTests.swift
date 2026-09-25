import XCTest
@testable import GraphiteCore

final class TextColorMarkupTests: XCTestCase {
    private func colored(_ source: String, palette: [String: String] = [:]) -> [(String, String)] {
        let text = source as NSString
        return TextColorMarkup.sections(in: text, paletteHexByName: palette).map { section in (text.substring(with: section.contentRange), section.hexColor) }
    }

    func testHexFormsAreCanonical() {
        XCTAssertEqual(TextColorMarkup.canonicalHex("#FF8800"), "#ff8800")
        XCTAssertEqual(TextColorMarkup.canonicalHex("#0f8"), "#00ff88")
        XCTAssertEqual(TextColorMarkup.canonicalHex("#ff880080"), "#ff880080")
        XCTAssertNil(TextColorMarkup.canonicalHex("red"))
        XCTAssertNil(TextColorMarkup.canonicalHex("#12345"))
    }

    func testBasicAndPaletteColors() {
        XCTAssertEqual(colored("A ~={#ff8800}warm=~ word").map(\.0), ["warm"])
        XCTAssertEqual(colored("~={red}named=~", palette: ["red": "#e93147"]).map(\.1), ["#e93147"])
        XCTAssertTrue(colored("~={unknown}text=~").isEmpty, "Unknown names stay plain text.")
    }

    func testNestingInnermostWins() {
        let sections = TextColorMarkup.sections(in: "~={#086ddd}blue ~={#e0ac00}yellow=~ blue=~" as NSString)
        guard sections.count == 2 else { return XCTFail("Expected 2 sections, got \(sections.count)") }
        XCTAssertEqual(sections[0].hexColor, "#086ddd")
        XCTAssertEqual(sections[0].depth, 0)
        XCTAssertEqual(sections[1].hexColor, "#e0ac00")
        XCTAssertEqual(sections[1].depth, 1)
    }

    func testUnclosedSectionEndsAtBlankLine() {
        let source = "~={#ff0000}open line\nstill red\n\nnot red =~"
        let sections = colored(source)
        XCTAssertEqual(sections.map(\.0), ["open line\nstill red"])
    }

    func testHighlightAroundColorDoesNotStealTheMarker() {
        XCTAssertEqual(colored("==~={#e0ac00}highlighted and colored=~==").map(\.0), ["highlighted and colored"])
        XCTAssertEqual(colored("~={#08b94e}~~struck and colored~~=~").map(\.0), ["~~struck and colored~~"])
    }

    func testCodeAndMathAreNotMarkup() {
        XCTAssertTrue(colored("`~={#ff0000}code=~`").isEmpty)
        XCTAssertTrue(colored("```\n~={#ff0000}code=~\n```").isEmpty)
        XCTAssertTrue(colored("$$\n~={#ff0000}x=~\n$$").isEmpty)
        XCTAssertEqual(colored("~={#00bfbc}$\\int_0^1 x^2\\,dx$=~").map(\.0), ["$\\int_0^1 x^2\\,dx$"], "Inline math can be colored.")
    }

    func testStrayCloserIsPlainText() {
        XCTAssertTrue(colored("a =~ b").isEmpty)
    }

    func testLongerFenceIsClosedOnlyByAnEqualOrLongerFence() {
        let source = "````\n```\n~={#ff0000}inside=~\n```\n~={#ff0000}still inside=~\n````\n~={#ff0000}after=~"
        XCTAssertEqual(colored(source).map(\.0), ["after"])
        XCTAssertTrue(colored("~~~\n```\n~={#ff0000}x=~").isEmpty, "A backtick line does not close a tilde fence.")
    }

    func testCodeSpansOfSeveralBackticksAreNotMarkup() {
        XCTAssertTrue(colored("`` a ` ~={#ff0000}x=~ ``").isEmpty)
        XCTAssertEqual(colored("``code`` ~={#ff0000}prose=~").map(\.0), ["prose"])
    }

    func testMarkersInsideInlineMathAreNotMarkup() {
        XCTAssertTrue(colored("$~={#ff0000}x=~$").isEmpty)
        XCTAssertEqual(colored("~={#ff0000}$5=~ and ~={#0000ff}$10=~").map(\.0), ["$5", "$10"], "Dollar amounts are not math.")
    }

    func testColorEndsWithItsListItemHeadingOrTableRow() {
        XCTAssertEqual(colored("- ~={#ff0000}first item\n- second item").map(\.0), ["first item"])
        XCTAssertEqual(colored("1. ~={#ff0000}first\n   continued\n2. second").map(\.0), ["first\n   continued"])
        XCTAssertEqual(colored("## ~={#ff0000}Heading\nBody text").map(\.0), ["Heading"])
        XCTAssertEqual(colored("| ~={#ff0000}a | b |\n| c | d |").map(\.0), ["a"], "A table cell is its own block.")
        XCTAssertEqual(colored("| ~={#ff0000}a \\| still a=~ | b |").map(\.0), ["a \\| still a"], "An escaped pipe is not a cell border.")
    }
}
