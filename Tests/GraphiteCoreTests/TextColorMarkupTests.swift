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

    // MARK: Removing color

    /// The note after the removal, and the selection it leaves; nil when nothing is removed.
    private func removingColor(from source: String, selection: NSRange, palette: [String: String] = [:]) -> (text: String, selection: NSRange)? {
        guard let edit = TextColorMarkup.removingColor(in: source as NSString, selection: selection, paletteHexByName: palette) else { return nil }
        return ((source as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selectionAfter)
    }

    func testRemovingColorAtTheCursorKeepsTheText() {
        let removal = removingColor(from: "A ~={#e93147}red word=~ end", selection: NSRange(location: 19, length: 0))
        XCTAssertEqual(removal?.text, "A red word end")
        XCTAssertEqual(removal?.selection, NSRange(location: 8, length: 0), "The cursor stays between the same letters.")
    }

    func testRemovingColorFromASelectionInsideTheColoredText() {
        let removal = removingColor(from: "A ~={#e93147}red word=~ end", selection: NSRange(location: 13, length: 3))
        XCTAssertEqual(removal?.text, "A red word end")
        XCTAssertEqual(removal?.selection, NSRange(location: 2, length: 3))
    }

    func testRemovingColorNeedsTheCursorInsideColoredText() {
        XCTAssertNil(removingColor(from: "plain text", selection: NSRange(location: 3, length: 0)))
        XCTAssertNil(removingColor(from: "~={#e93147}x=~", selection: NSRange(location: 0, length: 0)), "Before the opening marker is outside.")
        XCTAssertNil(removingColor(from: "~={#e93147}x=~", selection: NSRange(location: 14, length: 0)), "After the closing marker is outside.")
        XCTAssertNotNil(removingColor(from: "~={#e93147}x=~", selection: NSRange(location: 12, length: 0)), "After the colored text is inside.")
    }

    func testRemovingColorAtTheCursorTakesTheInnermostColor() {
        let source = "~={#086ddd}blue ~={#e0ac00}yellow=~ blue=~"
        XCTAssertEqual(removingColor(from: source, selection: NSRange(location: 30, length: 0))?.text, "~={#086ddd}blue yellow blue=~")
        XCTAssertEqual(removingColor(from: source, selection: NSRange(location: 30, length: 0))?.selection, NSRange(location: 19, length: 0))
        XCTAssertEqual(removingColor(from: source, selection: NSRange(location: 12, length: 0))?.text, "blue ~={#e0ac00}yellow=~ blue")
    }

    func testRemovingColorFromASelectionOfSeveralColoredRuns() {
        let removal = removingColor(from: "a ~={#e93147}b=~ c ~={#086ddd}d=~ e", selection: NSRange(location: 2, length: 31))
        XCTAssertEqual(removal?.text, "a b c d e")
        XCTAssertEqual(removal?.selection, NSRange(location: 2, length: 5), "The selection still covers the same words.")
    }

    func testSelectingAWholeInnerColorLeavesTheOuterColor() {
        let removal = removingColor(from: "~={#086ddd}blue ~={#e0ac00}yellow=~ blue=~", selection: NSRange(location: 16, length: 19))
        XCTAssertEqual(removal?.text, "~={#086ddd}blue yellow blue=~")
        XCTAssertEqual(removal?.selection, NSRange(location: 16, length: 6))
    }

    func testSelectionCuttingThroughAClosingMarkerRemovesThatColor() {
        XCTAssertEqual(removingColor(from: "a ~={#e93147}bc=~ d", selection: NSRange(location: 14, length: 5))?.text, "a bc d")
    }

    func testRemovingAnUnclosedColorRemovesItsOpeningMarkerOnly() {
        let removal = removingColor(from: "~={#ff0000}open line\nstill red\n\nplain", selection: NSRange(location: 15, length: 0))
        XCTAssertEqual(removal?.text, "open line\nstill red\n\nplain")
        XCTAssertEqual(removal?.selection, NSRange(location: 4, length: 0))
    }

    func testRemovingColorKnowsPaletteNamesAndSkipsCode() {
        XCTAssertEqual(removingColor(from: "~={red}named=~", selection: NSRange(location: 9, length: 0), palette: ["red": "#e93147"])?.text, "named")
        XCTAssertNil(removingColor(from: "~={red}named=~", selection: NSRange(location: 9, length: 0)), "An unknown name is plain text.")
        XCTAssertNil(removingColor(from: "`~={#ff0000}x=~`", selection: NSRange(location: 5, length: 0)), "Markers in code are text.")
    }

    func testRemovingColorEditsOnlyFromTheFirstMarkerToTheLast() {
        let edit = TextColorMarkup.removingColor(in: "intro\n\n~={#ff0000}x=~\n\noutro" as NSString, selection: NSRange(location: 18, length: 0))
        XCTAssertEqual(edit?.range, NSRange(location: 7, length: 14))
        XCTAssertEqual(edit?.replacement, "x")
        XCTAssertEqual(edit?.selectionAfter, NSRange(location: 7, length: 0), "A cursor before the letter stays before it.")
    }
}
