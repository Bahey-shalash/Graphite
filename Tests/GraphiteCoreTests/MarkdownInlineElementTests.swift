import XCTest
@testable import GraphiteCore

/// The inline elements the style scanner reports: which markup belongs to which element,
/// and emphasis around other elements. Live Preview shows an element's markup as a unit.
final class MarkdownInlineElementTests: XCTestCase {
    private func spans(of text: String) -> [MarkdownStyleSpan] {
        let source = text as NSString
        return MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length))
    }

    /// The text of the element each span of `style` belongs to, or nil for a line's own span.
    private func elements(of style: MarkdownStyle, in text: String) -> [String?] {
        spans(of: text).filter { span in span.style == style }.map { span in
            span.inlineElementRange.map { elementRange in (text as NSString).substring(with: elementRange) }
        }
    }

    private func styledText(_ style: MarkdownStyle, in text: String) -> [String] {
        spans(of: text).filter { span in span.style == style }.map { span in (text as NSString).substring(with: span.range) }
    }

    func testEverySpanOfAnElementCarriesTheWholeElement() throws {
        let line = "Use **bold**, *italic*, `code`, $x^2$, [[Note|alias]], ![[Figure.png]], [site](https://a.b), ==mark==, ~~old~~, [^1], ^[aside] and #tag"
        XCTAssertEqual(elements(of: .strong, in: line), ["**bold**"])
        XCTAssertEqual(elements(of: .emphasis, in: line), ["*italic*"])
        XCTAssertEqual(elements(of: .inlineCode, in: line), ["`code`"])
        XCTAssertEqual(elements(of: .math, in: line), ["$x^2$"])
        XCTAssertEqual(elements(of: .link, in: line), ["[[Note|alias]]", "[site](https://a.b)"])
        XCTAssertEqual(elements(of: .embed, in: line), ["![[Figure.png]]"])
        XCTAssertEqual(elements(of: .highlight, in: line), ["==mark=="])
        XCTAssertEqual(elements(of: .strikethrough, in: line), ["~~old~~"])
        XCTAssertEqual(elements(of: .footnote, in: line), ["[^1]", "^[aside]"])
        XCTAssertEqual(elements(of: .tag, in: line), ["#tag"])
        // Every marker is inside the element it opens or closes.
        let source = line as NSString
        for span in spans(of: line) where span.style == .concealableMarker {
            let elementRange = try XCTUnwrap(span.inlineElementRange, source.substring(with: span.range))
            XCTAssertEqual(NSIntersectionRange(elementRange, span.range), span.range)
        }
    }

    func testSubpathSeparatorBelongsToItsLink() {
        XCTAssertEqual(elements(of: .subpathSeparator, in: "See [[Logic design#Saturation]] here"), ["[[Logic design#Saturation]]"])
        XCTAssertEqual(elements(of: .link, in: "See [[#Heading]]"), ["[[#Heading]]"])
    }

    func testMarkersOfALineBelongToTheLine() {
        let note = "## Heading\n- item\n- [ ] task\n> quote\nA block ^block-id\n[^1]: definition\n"
        for span in spans(of: note) where [.concealableMarker, .listMarker, .taskMarker, .syntaxMarker, .heading(level: 2), .quote].contains(span.style) {
            XCTAssertNil(span.inlineElementRange, (note as NSString).substring(with: span.range))
        }
        XCTAssertEqual(styledText(.concealableMarker, in: note), ["## ", "^block-id"])
    }

    func testEmphasisHoldsOtherElementsWhole() {
        let line = "**bold with _italic_ and [[link]]**"
        XCTAssertEqual(styledText(.strong, in: line), ["bold with _italic_ and [[link]]"])
        XCTAssertEqual(elements(of: .strong, in: line), [line])
        XCTAssertEqual(styledText(.emphasis, in: line), ["italic"])
        XCTAssertEqual(elements(of: .emphasis, in: line), ["_italic_"])
        XCTAssertEqual(styledText(.link, in: line), ["link"])
        XCTAssertEqual(elements(of: .link, in: line), ["[[link]]"])

        XCTAssertEqual(styledText(.emphasis, in: "*see `code` and $x$*"), ["see `code` and $x$"])
        XCTAssertEqual(styledText(.highlight, in: "==a [site](https://a.b) b=="), ["a [site](https://a.b) b"])
        XCTAssertEqual(styledText(.strikethrough, in: "~~old [[Note]]~~"), ["old [[Note]]"])
        XCTAssertEqual(styledText(.strong, in: "**[[Note]]**"), ["[[Note]]"])
    }

    /// A delimiter inside code, a formula or a link is that element's text.
    func testDelimitersInsideOtherElementsAreNotEmphasis() {
        XCTAssertEqual(styledText(.strong, in: "**a `x**y` b**"), ["a `x**y` b"])
        XCTAssertEqual(styledText(.emphasis, in: "[[my_note_name]] and _real_"), ["real"])
        XCTAssertEqual(styledText(.emphasis, in: "$a_1 + b_2$ plain"), [])
        XCTAssertEqual(styledText(.highlight, in: "==a $x==y$ b=="), ["a $x==y$ b"])
        XCTAssertEqual(styledText(.strong, in: "`**not bold**` text"), [])
        XCTAssertEqual(styledText(.emphasis, in: "*open `code*` text"), [])
    }

    func testAdjacentElementsKeepTheirOwnRanges() {
        let line = "**a**`c`[[d]]==e=="
        XCTAssertEqual(elements(of: .strong, in: line), ["**a**"])
        XCTAssertEqual(elements(of: .inlineCode, in: line), ["`c`"])
        XCTAssertEqual(elements(of: .link, in: line), ["[[d]]"])
        XCTAssertEqual(elements(of: .highlight, in: line), ["==e=="])
    }

    /// Ranges count UTF-16 units: an emoji is two or more, and right-to-left text keeps
    /// its stored order.
    func testElementRangesInEmojiAndRightToLeftText() {
        let line = "👍🏽 **غامق 🎉** و [[ملاحظة|اسم]] ثم ==مميز== 👨‍👩‍👧 *مائل*"
        XCTAssertEqual(styledText(.strong, in: line), ["غامق 🎉"])
        XCTAssertEqual(elements(of: .strong, in: line), ["**غامق 🎉**"])
        XCTAssertEqual(styledText(.link, in: line), ["اسم"])
        XCTAssertEqual(elements(of: .link, in: line), ["[[ملاحظة|اسم]]"])
        XCTAssertEqual(elements(of: .highlight, in: line), ["==مميز=="])
        XCTAssertEqual(elements(of: .emphasis, in: line), ["*مائل*"])
        XCTAssertEqual(styledText(.concealableMarker, in: line), ["[[ملاحظة|", "]]", "**", "**", "*", "*", "==", "=="])
    }

    func testElementsInHeadingsListsAndQuotesStartAfterTheLineMarkers() {
        let note = "# A **bold** heading\n- item with [[link]]\n> quote with ==mark==\n1. *first*\n"
        XCTAssertEqual(elements(of: .strong, in: note), ["**bold**"])
        XCTAssertEqual(elements(of: .link, in: note), ["[[link]]"])
        XCTAssertEqual(elements(of: .highlight, in: note), ["==mark=="])
        XCTAssertEqual(elements(of: .emphasis, in: note), ["*first*"])
    }
}
