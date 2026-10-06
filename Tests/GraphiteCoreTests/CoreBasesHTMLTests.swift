import XCTest
@testable import GraphiteCore

/// `html()` in Bases formulas: the value, and the text and formatting Graphite shows for
/// its markup. Markup often carries text from notes, so what must not be shown or
/// followed is tested as closely as what is.
final class CoreBasesHTMLTests: XCTestCase {
    private let note = BaseTestRecords.record("Library/Dune.md", yaml: """
        status: reading
        title: "Dune <script>alert(1)</script>"
        pages: 412
        author: "[[Frank Herbert]]"
        """)

    private func evaluate(_ sourceText: String) throws -> BaseValue {
        let evaluator = BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil, knownRecords: [note])
        return try evaluator.evaluate(sourceText: sourceText, for: note)
    }

    private func runs(_ source: String) -> [BaseHTMLText.Run] { BaseHTMLText(source: source).runs }
    private func plainText(_ source: String) -> String { BaseHTMLText(source: source).plainText }

    private func style(_ change: (inout BaseHTMLText.Style) -> Void) -> BaseHTMLText.Style {
        var style = BaseHTMLText.Style()
        change(&style)
        return style
    }

    // MARK: The value

    func testHTMLMarksTextAsMarkup() throws {
        XCTAssertEqual(try evaluate("html(\"<b>Done</b>\")"), .html("<b>Done</b>"))
        XCTAssertEqual(try evaluate("html(\"<b>\" + status + \"</b>\")"), .html("<b>reading</b>"))
        XCTAssertEqual(try evaluate("html(html(\"<i>x</i>\"))"), .html("<i>x</i>"))
        XCTAssertEqual(try evaluate("html(missing)"), .null)
        XCTAssertEqual(try evaluate("html(\"\")"), .html(""))
        XCTAssertEqual(try evaluate("html(author)"), .html("Frank Herbert"), "A link is text underneath, as in Obsidian.")
    }

    func testHTMLOfAValueThatIsNotTextIsAnError() {
        for sourceText in ["html(5)", "html(true)", "html([\"<b>\"])", "html(now())", "html()", "html(\"a\", \"b\")", "html(file)"] {
            XCTAssertThrowsError(try evaluate(sourceText), sourceText)
        }
        XCTAssertThrowsError(try evaluate("html(pages)")) { error in
            XCTAssertEqual(error.localizedDescription, "html() needs text, not a number.")
        }
    }

    func testMarkupIsTextInEveryOtherRespect() throws {
        XCTAssertEqual(try evaluate("html(\"<b>x</b>\").isType(\"html\")"), .boolean(true))
        XCTAssertEqual(try evaluate("html(\"<b>x</b>\").isType(\"string\")"), .boolean(true), "Obsidian's HTML value is a kind of string.")
        XCTAssertEqual(try evaluate("html(\"<b>x</b>\").isType(\"number\")"), .boolean(false))
        XCTAssertEqual(try evaluate("html(\"<b>x</b>\").toString()"), .string("<b>x</b>"))
        XCTAssertEqual(try evaluate("html(\"<b>x</b>\").length"), .number(8))
        XCTAssertEqual(try evaluate("html(\"<b>x</b>\").contains(\"<b>\")"), .boolean(true))
        XCTAssertEqual(try evaluate("html(\"<B>x</B>\").lower()"), .string("<b>x</b>"))
        XCTAssertEqual(try evaluate("html(\"<b>x</b>\") == \"<b>x</b>\""), .boolean(true))
        XCTAssertEqual(try evaluate("html(\"a\") == html(\"a\")"), .boolean(true))
        XCTAssertEqual(try evaluate("html(\"a\") < html(\"b\")"), .boolean(true))
        XCTAssertEqual(try evaluate("html(\"\").isEmpty()"), .boolean(true))
        XCTAssertEqual(try evaluate("html(\"\").isTruthy()"), .boolean(false))
        XCTAssertEqual(try evaluate("if(html(\"<b>x</b>\"), 1, 2)"), .number(1))
    }

    func testJoiningMarkupGivesTextUntilItIsMarkedAgain() throws {
        XCTAssertEqual(try evaluate("html(\"<b>a</b>\") + \" b\""), .string("<b>a</b> b"))
        XCTAssertEqual(try evaluate("\"a \" + html(\"<b>b</b>\")"), .string("a <b>b</b>"))
        XCTAssertEqual(try evaluate("html(\"<b>a</b>\") + html(\"<i>b</i>\")"), .string("<b>a</b><i>b</i>"))
        XCTAssertEqual(try evaluate("html(html(\"<b>a</b>\") + html(\"<i>b</i>\"))"), .html("<b>a</b><i>b</i>"))
    }

    func testEscapeHTMLKeepsNoteTextFromBecomingMarkup() throws {
        let value = try evaluate("html(\"<b>\" + escapeHTML(title) + \"</b>\")")
        XCTAssertEqual(value, .html("<b>Dune &lt;script&gt;alert(1)&lt;/script&gt;</b>"))
        XCTAssertEqual(plainText(value.displayText), "Dune <script>alert(1)</script>", "The escaped text is shown as the text it is.")
    }

    func testRowsSortAndGroupByMarkupAsText() throws {
        let records = ["b", "a", "c"].map { status in BaseTestRecords.record("Notes/\(status).md", yaml: "status: \(status)") }
        let definition = try BaseDefinition.parse("""
            formulas:
              badge: html("<b>" + status + "</b>")
            views:
              - type: table
                name: T
                order: [file.name, formula.badge]
                sort:
                  - property: formula.badge
                    direction: DESC
            """)
        let result = BaseQueryEngine(definition: definition, environment: BaseTestRecords.environment(), thisRecord: nil).run(viewIndex: 0, records: records)
        XCTAssertEqual(result.rows.map(\.path.stem), ["c", "b", "a"])
        XCTAssertEqual(result.rows.first?.cells.last, .value(.html("<b>c</b>")))
    }

    // MARK: Formatting that is shown

    func testInlineFormattingBecomesStyledRuns() {
        XCTAssertEqual(runs("plain <b>bold</b> <i>italic</i>"), [
            .init(text: "plain "), .init(text: "bold", style: style { style in style.isBold = true }), .init(text: " "),
            .init(text: "italic", style: style { style in style.isItalic = true }),
        ], "A space keeps the formatting of the text it was written in.")
        XCTAssertEqual(runs("<u>a</u> <u>b</u>").map(\.text), ["a", " ", "b"])
        XCTAssertEqual(runs("<strong><em>both</em></strong>"), [.init(text: "both", style: style { style in style.isBold = true; style.isItalic = true })])
        XCTAssertEqual(runs("<u>u</u>").first?.style.isUnderlined, true)
        XCTAssertEqual(runs("<s>s</s>").first?.style.isStruckThrough, true)
        XCTAssertEqual(runs("<del>s</del>").first?.style.isStruckThrough, true)
        XCTAssertEqual(runs("<code>x = 1</code>").first?.style.isMonospaced, true)
        XCTAssertEqual(runs("<mark>m</mark>").first?.style.isHighlighted, true)
        XCTAssertEqual(runs("<small>s</small>").first?.style.isSmall, true)
        XCTAssertEqual(runs("x<sup>2</sup>").last?.style.baseline, .raised)
        XCTAssertEqual(runs("H<sub>2</sub>").last?.style.baseline, .lowered)
        XCTAssertEqual(plainText("She said <q>hello</q>"), "She said “hello”")
    }

    func testTagAndAttributeNamesIgnoreCase() {
        XCTAssertEqual(runs("<B>bold</B>").first?.style.isBold, true)
        XCTAssertEqual(runs("<SPAN STYLE=\"COLOR: RED\">r</SPAN>").first?.style.foregroundColor, .rgba(red: 1, green: 0, blue: 0, alpha: 1))
    }

    func testStyleAttributesGiveColorsAndTextFormatting() {
        let red = BaseColorSpecification.rgba(red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(runs("<span style=\"color: red\">late</span>"), [.init(text: "late", style: style { style in style.foregroundColor = red })])
        XCTAssertEqual(runs("<span style='color:#f00;background-color:rgb(0, 0, 255)'>x</span>").first?.style.backgroundColor, .rgba(red: 0, green: 0, blue: 1, alpha: 1))
        XCTAssertEqual(runs("<span style=\"color: var(--color-red)\">x</span>").first?.style.foregroundColor, .theme("red"))
        XCTAssertEqual(runs("<span style=\"font-weight: bold; font-style: italic; text-decoration: underline line-through\">x</span>").first?.style,
                       style { style in style.isBold = true; style.isItalic = true; style.isUnderlined = true; style.isStruckThrough = true })
        XCTAssertEqual(runs("<span style=\"font-weight: 700\">x</span>").first?.style.isBold, true)
        XCTAssertEqual(runs("<b><span style=\"font-weight: normal\">x</span></b>").first?.style.isBold, false)
        XCTAssertEqual(runs("<font color=\"blue\">x</font>").first?.style.foregroundColor, .rgba(red: 0, green: 0, blue: 1, alpha: 1))
        XCTAssertEqual(runs("<span style=\"color: not-a-color; width: 900px; position: fixed\">x</span>"), [.init(text: "x")], "Anything that is not text formatting is ignored.")
    }

    func testFormattingEndsWithItsElement() {
        let parsedRuns = runs("<b>bold <i>both</i> bold</b> plain")
        XCTAssertEqual(parsedRuns.map(\.text), ["bold ", "both", " bold", " plain"])
        XCTAssertEqual(parsedRuns.map(\.style.isBold), [true, true, true, false])
        XCTAssertEqual(parsedRuns.map(\.style.isItalic), [false, true, false, false])
    }

    func testCharacterReferencesAreDecoded() {
        XCTAssertEqual(plainText("a &lt; b &amp;&amp; c &gt; d"), "a < b && c > d")
        XCTAssertEqual(plainText("&quot;x&quot; &apos;y&apos; &copy; &hellip; &mdash;"), "\"x\" 'y' © … —")
        XCTAssertEqual(plainText("&#65;&#x42;&#x1F4DA;"), "AB📚")
        XCTAssertEqual(plainText("a&nbsp;&nbsp;b"), "a\u{A0}\u{A0}b", "No-break spaces are not collapsed.")
        XCTAssertEqual(plainText("&unknown; &amp &#; &#xZZ; AT&T"), "&unknown; &amp &#; &#xZZ; AT&T", "What is not a reference stays as written.")
        XCTAssertEqual(plainText("&#0;&#xD800;&#x110000;"), "\u{FFFD}\u{FFFD}\u{FFFD}")
    }

    func testWhitespaceCollapsesAndBlocksStartLines() {
        XCTAssertEqual(plainText("  a \n\t b  "), "a b")
        XCTAssertEqual(plainText("<p>one</p><p>two</p>"), "one\ntwo")
        XCTAssertEqual(plainText("<div>one</div>two<div>three</div>"), "one\ntwo\nthree")
        XCTAssertEqual(plainText("one<br>two<br/>three"), "one\ntwo\nthree")
        XCTAssertEqual(plainText("one<br><br>two"), "one\n\ntwo")
        XCTAssertEqual(plainText("one<br><br>"), "one", "Line breaks after the last text show nothing.")
        XCTAssertEqual(plainText("<ul><li>a</li><li>b</li></ul>"), "•\u{A0}a\n•\u{A0}b")
        XCTAssertEqual(plainText("<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>"), "a b\nc")
        XCTAssertEqual(plainText("<h2>Title</h2>text"), "Title\ntext")
        XCTAssertEqual(runs("<h2>Title</h2>text").first?.style.isBold, true)
        XCTAssertEqual(plainText("<pre>a\n  b</pre>"), "a\n  b", "Preformatted text keeps its spaces and lines.")
    }

    // MARK: What is never shown, loaded or followed

    func testScriptsStylesAndFramesAreLeftOutWithTheirContent() {
        XCTAssertEqual(plainText("a<script>alert('x')</script>b"), "ab")
        XCTAssertEqual(plainText("a<SCRIPT type=\"text/javascript\">if (a < b) { document.write('<b>x</b>') }</SCRIPT>b"), "ab")
        XCTAssertEqual(plainText("a<style>b { color: red }</style>b"), "ab")
        XCTAssertEqual(plainText("a<iframe src=\"https://example.com\">fallback</iframe>b"), "ab")
        XCTAssertEqual(plainText("a<object data=\"x.swf\">inner <b>text</b></object>b"), "ab")
        XCTAssertEqual(plainText("a<embed src=\"https://example.com/x\">b"), "ab")
        XCTAssertEqual(plainText("a<svg><text>drawn</text></svg>b"), "ab")
        XCTAssertEqual(plainText("a<video src=\"https://example.com/v.mp4\">no video</video>b"), "ab")
        XCTAssertEqual(plainText("a<textarea>typed</textarea><select><option>pick</option></select><button>press</button><input value=\"v\">b"), "ab")
        XCTAssertEqual(plainText("a<noscript>no script</noscript><template>t</template><title>t</title>b"), "ab")
        XCTAssertEqual(plainText("before<script>never closed"), "before", "An unclosed script takes the rest with it.")
        XCTAssertEqual(plainText("a<!-- comment <b>x</b> -->b<!doctype html><?xml version=\"1.0\"?>c"), "abc")
    }

    func testImagesAreNotFetchedAndShowTheirAlternativeText() {
        XCTAssertEqual(runs("<img src=\"https://tracker.example/pixel.gif\" alt=\"A cat\">"), [.init(text: "A cat")])
        XCTAssertEqual(runs("<img src=\"https://tracker.example/pixel.gif\">"), [], "No run holds the image's address.")
        XCTAssertEqual(plainText("x <img src=file:///etc/passwd onerror=\"alert(1)\" alt=''> y"), "x y")
    }

    func testOnlyWebAndMailLinksAreLinks() {
        XCTAssertEqual(runs("<a href=\"https://obsidian.md/help\">Help</a>"),
                       [.init(text: "Help", style: style { style in style.linkDestination = URL(string: "https://obsidian.md/help") })])
        XCTAssertEqual(runs("<a href='HTTP://example.com'>x</a>").first?.style.linkDestination, URL(string: "HTTP://example.com"))
        XCTAssertEqual(runs("<a href=\"mailto:someone@example.com\">Mail</a>").first?.style.linkDestination, URL(string: "mailto:someone@example.com"))
        for destination in ["javascript:alert(1)", "JaVaScRiPt:alert(1)", " javascript:alert(1)", "data:text/html,<script>alert(1)</script>", "file:///etc/passwd",
                            "obsidian://open?vault=x", "graphite://open?file=x", "vbscript:x", "tel:+123", "//example.com/x", "Note", "#heading", ""] {
            XCTAssertEqual(runs("<a href=\"\(destination)\">text</a>"), [.init(text: "text")], "“\(destination)” must not become a link.")
        }
        XCTAssertEqual(runs("<a href=\"java&#115;cript:alert(1)\">x</a>"), [.init(text: "x")], "A destination is judged after its character references are decoded.")
        XCTAssertEqual(runs("<a onclick=\"alert(1)\" href=\"https://example.com\" href=\"javascript:alert(2)\">x</a>").first?.style.linkDestination, URL(string: "https://example.com"))
    }

    func testEventHandlersAndUnknownElementsLeaveOnlyTheirText() {
        XCTAssertEqual(runs("<b onclick=\"alert(1)\" onmouseover=alert(2)>x</b>"), [.init(text: "x", style: style { style in style.isBold = true })])
        XCTAssertEqual(plainText("<custom-element data-x=\"1\">inside</custom-element>"), "inside")
        XCTAssertEqual(plainText("<marquee>moving</marquee><blink>blinking</blink>"), "movingblinking")
    }

    func testHiddenContentIsNotShown() {
        XCTAssertEqual(plainText("a<span style=\"display:none\">hidden</span>b"), "ab")
        XCTAssertEqual(plainText("a<span style=\"visibility: hidden\">hidden <b>too</b></span>b"), "ab")
        XCTAssertEqual(plainText("a<span hidden>hidden</span>b"), "ab")
    }

    // MARK: Damaged markup

    func testDamagedMarkupStillShowsItsText() {
        XCTAssertEqual(plainText("a < b and c > d"), "a < b and c > d")
        XCTAssertEqual(plainText("5 <3 and <"), "5 <3 and <")
        XCTAssertEqual(plainText("<b>never closed"), "never closed")
        XCTAssertEqual(runs("<b>never closed").first?.style.isBold, true)
        XCTAssertEqual(plainText("closed twice</b></b></i>"), "closed twice")
        XCTAssertEqual(runs("<b><i>x</b>y</i>z").map(\.style.isBold), [true, false], "A tag closed out of order closes what was opened inside it.")
        XCTAssertEqual(plainText("text <b"), "text", "A tag the text ends in is left out.")
        XCTAssertEqual(plainText("<a href=\"unterminated>text"), "")
        XCTAssertEqual(plainText("<>x</>"), "<>x</>")
        XCTAssertEqual(plainText("<b style=\"color:red;;:;color\" =x = y>z</b>"), "z")
        XCTAssertEqual(plainText(""), "")
        XCTAssertEqual(runs("<p></p><br>"), [])
    }

    func testDeepNestingAndLongMarkupAreBounded() {
        let depth = 5_000
        let nested = String(repeating: "<b><span>", count: depth) + "deep" + String(repeating: "</span></b>", count: depth)
        XCTAssertEqual(plainText(nested), "", "Markup past the length limit is not read.")
        let nestedWithinLimit = String(repeating: "<i>", count: 500) + "deep" + String(repeating: "</i>", count: 500)
        XCTAssertEqual(plainText(nestedWithinLimit), "deep")
        let long = String(repeating: "word ", count: 10_000)
        XCTAssertLessThanOrEqual(plainText(long).count, BaseHTMLText.maximumSourceCharacters)
        XCTAssertTrue(plainText(long).hasPrefix("word word"))
    }

    func testRandomMarkupNeverTrapsOrYieldsALinkThatIsNotWebOrMail() {
        let fragments = ["<", ">", "</", "/>", "<b", "<i>", "</i>", "<a href=", "\"", "'", "javascript:", "https://a.b", "&", "&#", ";", "x", " ", "\n", "<script>", "</script>",
                         "<!--", "-->", "style=", "display:none", "<br>", "<img alt=", "&amp;", "<pre>", "</pre>", "=", "<li>", "📚", "<q>", "</q>", "\u{0}"]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2_000 {
            let source = (0..<Int.random(in: 0...40, using: &generator)).map { _ in fragments.randomElement(using: &generator) ?? "" }.joined()
            let text = BaseHTMLText(source: source)
            for run in text.runs {
                XCTAssertFalse(run.text.isEmpty, source)
                if let destination = run.style.linkDestination {
                    XCTAssertTrue(["http", "https", "mailto"].contains(destination.scheme?.lowercased() ?? ""), source)
                }
            }
        }
    }
}
