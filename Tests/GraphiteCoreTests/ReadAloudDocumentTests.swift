import XCTest
@testable import GraphiteCore

final class ReadAloudDocumentTests: XCTestCase {
    private func speech(_ source: String, range: NSRange? = nil) throws -> String {
        try ReadAloudDocument.markdown(source, selectedRange: range).passages.map(\.text).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func testMarkdownFormattingAndLinkTargetsAreNotSpoken() throws {
        let source = "## Introduction\n\n**Important** and *clear* ~~steady~~ [a paper](https://example.org/private-url).\n\n- [x] Study [[Course/Topic|this topic]]."
        XCTAssertEqual(try speech(source), "Introduction Important and clear steady a paper. Study this topic.")
    }

    func testMetadataCommentsColorsCalloutsAndEmbeds() throws {
        let source = "---\r\nsecret: private\r\n---\r\n# Title\r\n%% hidden %%~={#ff0000}Red=~ and ==bright==.\r\n> [!note] Remember\r\n> This matters.\r\n\r\n![[private.pdf]]"
        XCTAssertEqual(try speech(source), "Title Red and bright. Remember This matters.")
    }

    func testCodeAndImageContentsAreSkippedButInlineCodeIsLiteral() throws {
        let source = "Say `hello_world` once.\n\n```swift\nsecret()\n```\n\n![image](photo.png)\n\nFinish."
        XCTAssertEqual(try speech(source), "Say hello_world once. Finish.")
        XCTAssertFalse(try ReadAloudDocument.markdown(source).notices.isEmpty)
    }

    func testMathIsInterpretedBeforeSpeechAndUnknownCommandsAreAnnounced() throws {
        XCTAssertEqual(try speech("Energy $x^2$ and $\\frac{a+b}{c}$ then $\\unknown{x}$ end."),
                       "Energy x squared and fraction, numerator a plus b, denominator c, end fraction then Equation not yet supported. end.")
        XCTAssertEqual(try speech("Before.\n\n$$\n\\sqrt{x}+\\alpha\n$$\n\nAfter."), "Before. square root of x, end root plus alpha After.")
    }

    func testSelectionDoesNotReadFollowingTextOrRevealCodeAndMetadata() throws {
        let source = "---\nsecret: private\n---\n\n## Title\n\nRead **just this** then stop.\n\n```\nhidden text\n```"
        XCTAssertEqual(try speech(source, range: (source as NSString).range(of: "just this")), "just this")
        XCTAssertThrowsError(try speech(source, range: (source as NSString).range(of: "private")))
        XCTAssertThrowsError(try speech(source, range: (source as NSString).range(of: "hidden text")))
    }

    func testPartialEquationIsRejected() {
        let source = "Read $\\frac{a}{b}$ carefully."
        XCTAssertThrowsError(try speech(source, range: (source as NSString).range(of: "frac")))
    }

    func testEndpointsExpandCompleteWordsAndRejectBrokenUnicode() throws {
        let source = "Read complete words only."
        XCTAssertEqual(try speech(source, range: NSRange(location: 7, length: 10)), "complete words")
        XCTAssertThrowsError(try speech("🧠 text", range: NSRange(location: 1, length: 3)))
    }

    func testMathScriptGroupingAndMalformedExpressions() {
        XCTAssertEqual(MathSpeech.expression("x^12"), "x to the power 1, end power 2")
        XCTAssertEqual(MathSpeech.expression("x^{12}"), "x to the power 12, end power")
        for expression in ["x^", "x^-2", "^2", "x^^2", "x^2^3", "(a+b", "a+b)"] { XCTAssertNil(MathSpeech.expression(expression), expression) }
    }

    func testAdjacentEquationsRemainSeparateAndFootnotesDoNotInterruptProse() throws {
        XCTAssertEqual(try speech("Read $x$ $y$ and this[^ref].\n\n[^ref]: hidden footnote\n    continued footnote"), "Read x y and this.")
        XCTAssertEqual(try speech("Before.\n\n$$x"), "Before. Equation not yet supported.")
    }

    func testUnicodeAndCRLFSourceRangesMatchSpokenWords() throws {
        let source = "# Café 🧠\r\n\r\n> A naïve **reader** sees café.\r\n> - Follow [this](https://example.org)."
        let document = try ReadAloudDocument.markdown(source)
        for word in ["Café", "naïve", "reader", "café", "Follow", "this"] {
            let passage = try XCTUnwrap(document.passages.first { passage in passage.text.contains(word) })
            let spokenRange = (passage.text as NSString).range(of: word)
            let sourceRange = try XCTUnwrap(passage.sourceRange(for: spokenRange))
            XCTAssertEqual((source as NSString).substring(with: sourceRange), word)
        }
    }

    func testDecodedEntitiesAndMathMapToWholeSourceExpression() throws {
        let source = "Fish &amp; chips and $x^2$."
        let document = try ReadAloudDocument.markdown(source)
        let passage = try XCTUnwrap(document.passages.first)
        XCTAssertTrue(passage.text.contains("Fish & chips"))
        let sourceRange = try XCTUnwrap(passage.sourceRange(for: (passage.text as NSString).range(of: "squared")))
        XCTAssertEqual((source as NSString).substring(with: sourceRange), "$x^2$")
    }

    func testEscapesReferenceLinksAndInlineCodeNormalization() throws {
        XCTAssertEqual(try speech("[paper]: https://example.org\n\nRead [this paper][paper] with \\*literal\\* symbols &amp; entities.\n\nUse ` two  spaces ` and `a\nb`."),
                       "Read this paper with *literal* symbols & entities. Use two spaces and a b.")
    }

    func testLongPassagesAreBoundedAndDoNotLoseWords() throws {
        let source = Array(repeating: "Café 🧠 sentence.", count: 600).joined(separator: " ")
        let document = try ReadAloudDocument.markdown(source)
        XCTAssertGreaterThan(document.passages.count, 1)
        XCTAssertTrue(document.passages.allSatisfy { passage in passage.text.utf16.count <= ReadAloudDocument.maximumPassageUTF16Count })
        XCTAssertEqual(document.passages.map(\.text).joined(separator: " "), source)
    }

    func testUnsafeAndInvalidInputsFailWithoutTrapping() {
        XCTAssertThrowsError(try ReadAloudDocument.markdown("text", selectedRange: NSRange(location: Int.max, length: 2)))
        XCTAssertThrowsError(try ReadAloudDocument.markdown("text", selectedRange: NSRange(location: 1, length: Int.max)))
        XCTAssertThrowsError(try ReadAloudDocument.markdown(String(repeating: "> ", count: 40) + "deep"))
        XCTAssertThrowsError(try ReadAloudDocument.markdown(String(repeating: "a", count: ReadAloudDocument.maximumSourceUTF16Count + 1)))
        XCTAssertNil(MathSpeech.expression(String(repeating: "{", count: 40) + "x" + String(repeating: "}", count: 40)))
        XCTAssertNil(MathSpeech.expression("\\frac{a}"))
        XCTAssertNil(MathSpeech.expression("\\begin{matrix}a\\end{matrix}"))
    }

    func testPlainTextRangeIncludesWholeEndpointsAndRetainsPageCoordinates() throws {
        let source = "Before café alpha beta after."
        let original = source as NSString
        let start = original.range(of: "alpha").location + 2
        let end = original.range(of: "beta").location + 2
        let document = try ReadAloudDocument.plainText(source, selectedRange: NSRange(location: start, length: end - start))
        XCTAssertEqual(document.passages.map(\.text), ["alpha beta"])
        XCTAssertEqual(document.passages.first?.sourceRange(for: NSRange(location: 0, length: 5)), original.range(of: "alpha"))
        XCTAssertEqual(document.passages.first?.sourceRange(for: NSRange(location: 6, length: 4)), original.range(of: "beta"))
        XCTAssertThrowsError(try ReadAloudDocument.plainText("😀 text", selectedRange: NSRange(location: 1, length: 2)))
        XCTAssertThrowsError(try ReadAloudDocument.plainText(source, selectedRange: NSRange(location: Int.max, length: 1)))
    }

    func testSectionRangesIncludeSubsectionsAndKeepRepeatedHeadingOccurrences() throws {
        let source = "---\r\nprivate: true\r\n---\r\n%%\r\n# Hidden\r\n%%\r\n# Café 😀\r\nFirst.\r\n## Detail\r\nInside.\r\n# Café 😀\r\nSecond.\r\n\r\nLast title\r\n----------\r\nFinal.\r\n\r\n```\r\n# Not a heading\r\n```"
        let sections = try ReadAloudSection.sections(in: source)
        XCTAssertEqual(sections.map(\.title), ["Café 😀", "Detail", "Café 😀", "Last title"])
        XCTAssertEqual(sections.map(\.level), [1, 2, 1, 2])
        XCTAssertEqual(Set(sections.map(\.id)).count, 4)
        let first = try XCTUnwrap(sections.first)
        let narration = try ReadAloudDocument.markdown(source, selectedRange: first.range)
        XCTAssertEqual(narration.passages.map(\.text), ["Café 😀", "First.", "Detail", "Inside."])
        let second = sections[2]
        XCTAssertEqual(try ReadAloudDocument.markdown(source, selectedRange: second.range).passages.map(\.text), ["Café 😀", "Second.", "Last title", "Final."])
        XCTAssertTrue(try ReadAloudSection.sections(in: "A note without headings.").isEmpty)
    }

    /// Real notes are full of apostrophes, quotes and double hyphens, which the parser turns
    /// into typographic marks. They used to stop the whole note with "could not safely match".
    func testSmartPunctuationIsReadAndMapsBackToWhatWasWritten() throws {
        let source = "# Shannon's Expansion -- a note\n\nIt's \"simple\"... really --- see 'L01'.\n\n> [!banana]\n> Unknown type: titled \"Banana\"."
        let document = try ReadAloudDocument.markdown(source)
        XCTAssertEqual(try speech(source), "Shannon’s Expansion – a note It’s “simple”… really — see ‘L 01’. Unknown type: titled “Banana”.")
        let passage = try XCTUnwrap(document.passages.first)
        let apostrophe = (passage.text as NSString).range(of: "’")
        XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(passage.sourceRange(for: apostrophe))), "'")
        let word = (passage.text as NSString).range(of: "Expansion")
        XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(passage.sourceRange(for: word))), "Expansion")
        let second = try XCTUnwrap(document.passages.dropFirst().first)
        let dash = (second.text as NSString).range(of: "—")
        XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(second.sourceRange(for: dash))), "---")
    }

    func testDisplayMathInsideACalloutIsReadNotAnnouncedAsUnsupported() throws {
        XCTAssertEqual(try speech("> [!note] PUN\n> $$x^2$$\n>\n> $$\n> y^2\n> $$"), "P U N x squared y squared")
    }

    func testTablesWithEscapedPipesAndBrokenTablesAreRead() throws {
        let escaped = "| Expression | Meaning |\n| --- | --- |\n| a \\| b | logical or |\n| a \\\\| b | edge |"
        XCTAssertFalse(try speech(escaped).isEmpty)
        let broken = "| A | B | C |\n| --- | --- |\n| a | b | c |"
        XCTAssertTrue(try speech(broken).contains("a | b | c"))
    }

    func testTablesAreReadRowByRowWithTheirColumnHeaders() throws {
        let document = try ReadAloudDocument.markdown("| Gate | Delay (ps) |\n| --- | --- |\n| NAND | 35 |\n| NOR | 52 |")
        XCTAssertEqual(document.passages.map(\.text), ["Gate, Delay (ps)", "Gate: nand, Delay (ps): 35", "Gate: nor, Delay (ps): 52"])
        XCTAssertEqual(Set(document.passages.map(\.kind)), [.tableRow])
    }

    func testCalloutTitleIsReadAsItsOwnHeading() throws {
        let document = try ReadAloudDocument.markdown("> [!tip] Rule of thumb\n> Keep the effort low.")
        XCTAssertEqual(document.passages.map(\.text), ["Rule of thumb", "Keep the effort low."])
        XCTAssertEqual(document.passages.first?.kind, .heading)
    }

    /// Web addresses are announced instead of spelled out, and unambiguous abbreviations are
    /// expanded; the highlight still covers what is written, and a rendered note still finds
    /// the written words.
    func testAddressesAndAbbreviationsAreSaidTheWayAPersonWouldSayThem() throws {
        let source = "Visit https://www.example.com/a/b?c=1 now, e.g. in Fig. 3, i.e. pp. 12–14 vs. No. 5."
        let document = try ReadAloudDocument.markdown(source)
        let passage = try XCTUnwrap(document.passages.first)
        XCTAssertEqual(passage.text, "Visit link to example.com now, for example in Figure 3, that is pages 12–14 versus number 5.")
        let spoken = (passage.text as NSString).range(of: "link to example.com")
        XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(passage.sourceRange(for: spoken))), "https://www.example.com/a/b?c=1")
        let tokens = ReadAloudSourceToken.tokens(in: document).map(\.text)
        XCTAssertTrue(tokens.contains("e.g"), "\(tokens)")
        XCTAssertFalse(tokens.contains("example") && !tokens.contains("www.example.com"))
        XCTAssertEqual(try speech("See Fig. on the left, and No. one."), "See Fig. on the left, and No. one.")
    }

    func testSlideLinesBulletsFootersAndBrokenWordsReadNaturally() throws {
        let slide = "Syllabus\n• Basic static logic\n• Noise margins\nThe on-\nresistance must be equal\nfor both networks.\nL05 Static logic v1.0 EE-330 2026 2"
        let document = try ReadAloudDocument.pageText(slide, pageLabels: ["2"])
        XCTAssertEqual(document.passages.map(\.text),
                       ["Syllabus", "Basic static logic", "Noise margins", "The on-resistance must be equal for both networks."])
        XCTAssertEqual(document.passages.map(\.kind), [.line, .line, .line, .paragraph])
        XCTAssertFalse(document.notices.isEmpty)
        let passage = document.passages[3]
        let word = (passage.text as NSString).range(of: "resistance")
        XCTAssertEqual((slide as NSString).substring(with: try XCTUnwrap(passage.sourceRange(for: word))), "resistance")
        XCTAssertEqual(document.runningText, ["L05 Static logic v1.0 EE-330 2026"])
        // A later slide whose layout split the footer into pieces skips the same text.
        let later = try ReadAloudDocument.pageText("Pass-transistor logic\n• nMOS logic\nL05 Static logic v1.0\nEE-330 2026\n21",
                                                   pageLabels: ["21"], knownRunningText: document.runningText)
        XCTAssertEqual(later.passages.map(\.text), ["Pass-transistor logic", "en moss logic"])
        let contents = try ReadAloudDocument.pageText("3.1.4 Thin-Film Removal . . . . . . . . 145")
        XCTAssertEqual(contents.passages.map(\.text), ["3.1.4 Thin-Film Removal 145"])
        let prose = try ReadAloudDocument.pageText("A footer-like last line ends\nwith 7 words and the page 7")
        XCTAssertEqual(prose.passages.map(\.text), ["A footer-like last line ends with 7 words and the page 7"])
    }
}

