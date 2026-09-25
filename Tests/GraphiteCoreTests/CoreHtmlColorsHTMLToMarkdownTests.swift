import XCTest
@testable import GraphiteCore

/// Regression tests for pasted HTML that the converter used to damage.
final class CoreHtmlColorsHTMLToMarkdownTests: XCTestCase {
    private func markdown(_ html: String) -> String {
        HTMLToMarkdown.markdown(from: html)
    }

    func testLiteralDelimiterRunsInTextAndCodeAreKept() {
        XCTAssertEqual(markdown("<p>Card **** 1234 and a==== b ~~~~ c</p>"), "Card **** 1234 and a==== b ~~~~ c")
        XCTAssertEqual(markdown("<pre>// ========\nx ~~~~ y ****</pre>"), "```\n// ========\nx ~~~~ y ****\n```")
        XCTAssertEqual(markdown("<pre><code>let divider = \"====\"</code></pre>"), "```\nlet divider = \"====\"\n```")
    }

    func testEmptyAndNestedEmphasis() {
        XCTAssertEqual(markdown("<p><b></b>empty<i> </i>tags<del></del></p>"), "empty tags")
        XCTAssertEqual(markdown("<p><b><strong>double</strong></b> bold</p>"), "**double** bold")
        XCTAssertEqual(markdown("<p><b>one</b><b>two</b></p>"), "**onetwo**", "Adjacent bold runs continue each other.")
        XCTAssertEqual(markdown("<p><b>bold <i>both</i></b></p>"), "**bold *both***")
    }

    func testBlankLinesInsideCodeAreKept() {
        XCTAssertEqual(markdown("<pre>a\n\n\n\nb</pre>"), "```\na\n\n\n\nb\n```")
    }

    func testParagraphsInsideListItemsStayOnTheMarkerLine() {
        XCTAssertEqual(markdown("<ul><li><p>one</p></li><li><p>two</p></li></ul>"), "- one\n- two")
        XCTAssertEqual(markdown("<ol><li><div>one</div></li><li><div>two</div></li></ol>"), "1. one\n2. two")
        let googleDocsList = "<ul><li dir=\"ltr\"><p dir=\"ltr\"><span>one</span></p></li>\n<li dir=\"ltr\"><p dir=\"ltr\"><span>two</span></p></li></ul>"
        XCTAssertEqual(markdown(googleDocsList), "- one\n- two")
        XCTAssertEqual(markdown("<ul><li><p>first</p><p>second</p></li></ul>"), "- first\n\tsecond", "A later block in the item is indented as the item's content.")
    }

    func testMarkupInsidePreformattedTextIsCode() {
        XCTAssertEqual(markdown("<pre><code>let <a href=\"https://example.org\">String</a> = <b>bold</b> <img src=\"x.png\"></code></pre>"),
                       "```\nlet String = bold \n```")
        XCTAssertEqual(markdown("<pre><div>first</div><div>second</div></pre>"), "```\nfirst\nsecond\n```")
    }

    func testInlineElementsWrappingBlocks() {
        let googleDocs = "<meta charset=\"utf-8\"><b style=\"font-weight:normal;\" id=\"docs-internal-guid-1\"><p dir=\"ltr\"><span>First</span></p><p dir=\"ltr\"><span>Second</span></p></b>"
        XCTAssertEqual(markdown(googleDocs), "First\n\nSecond")
        XCTAssertEqual(markdown("<a href=\"https://example.org\"><h2>Title</h2></a>"), "## [Title](https://example.org)")
        XCTAssertEqual(markdown("<b><p>one</p><p>two</p></b>"), "**one**\n\n**two**")
        XCTAssertEqual(markdown("<p><b>line<br>break</b></p>"), "**line**  \n**break**")
    }

    func testCodeFencesAreLongerThanBackticksInside() {
        XCTAssertEqual(markdown("<p><code>a`b</code></p>"), "``a`b``")
        XCTAssertEqual(markdown("<p><code>`tick</code></p>"), "`` `tick ``")
        XCTAssertEqual(markdown("<pre>```\ncode\n```</pre>"), "````\n```\ncode\n```\n````")
        XCTAssertEqual(markdown("<p>Run <code> ls </code>now</p>"), "Run `ls` now")
    }

    func testBlocksInsideTableCellsKeepTheTable() {
        let html = "<table><tr><th><p>A</p></th><th><p>B</p></th></tr><tr><td><p>1</p><p>x</p></td><td><div>2</div><br>y</td></tr></table>"
        XCTAssertEqual(markdown(html), "| A | B |\n| --- | --- |\n| 1 x | 2 y |")
        XCTAssertEqual(markdown("<table><tr><td><ul><li>one</li><li>two</li></ul></td><td><h3>Head</h3></td></tr></table>"), "| one two | Head |\n| --- | --- |")
        XCTAssertEqual(markdown("<table><tr><td><pre>let x\n= 1</pre></td></tr></table>"), "| `let x = 1` |\n| --- |")
        XCTAssertEqual(markdown("<table><tr><td>a<tr><td>b</table>"), "| a |\n| --- |\n| b |", "Rows may omit </tr>.")
    }

    func testPipesInTableCellsAreEscaped() {
        XCTAssertEqual(markdown("<table><tr><td>a|b</td><td>c</td></tr></table>"), "| a\\|b | c |\n| --- | --- |")
        XCTAssertEqual(markdown("<table><tr><td><code>x || y</code></td></tr></table>"), "| `x \\|\\| y` |\n| --- |")
    }

    func testBlocksInsideQuotesAndListsKeepTheirPrefix() {
        XCTAssertEqual(markdown("<blockquote><pre>a\nb</pre></blockquote>"), "> ```\n> a\n> b\n> ```")
        XCTAssertEqual(markdown("<blockquote><pre>a\n\nb</pre></blockquote>"), "> ```\n> a\n>\n> b\n> ```")
        XCTAssertEqual(markdown("<blockquote><table><tr><td>a</td></tr></table></blockquote>"), "> | a |\n> | --- |")
        XCTAssertEqual(markdown("<blockquote>a<hr>b</blockquote>"), "> a\n>\n> ---\n>\n> b")
        XCTAssertEqual(markdown("<ul><li><h2>Head</h2></li></ul>"), "- ## Head")
        XCTAssertEqual(markdown("<ul><li>one<blockquote>quoted</blockquote></li></ul>"), "- one\n\t> quoted")
        XCTAssertEqual(markdown("<ul><li><blockquote>quoted</blockquote></li></ul>"), "- > quoted")
        XCTAssertEqual(markdown("<ul><li>code:<pre>x\ny</pre></li></ul>"), "- code:\n\t```\n\tx\n\ty\n\t```")
        XCTAssertEqual(markdown("<ul><li><pre>x</pre></li></ul>"), "- \n\t```\n\tx\n\t```")
        XCTAssertEqual(markdown("<ul><li>a<hr>b</li></ul>"), "- a\n\t***\n\tb")
    }

    func testWhitespaceAtEmphasisEdgesGoesOutsideTheDelimiters() {
        XCTAssertEqual(markdown("<p>This is <b>bold </b>text and<strong> strong</strong> here</p>"), "This is **bold** text and **strong** here")
        XCTAssertEqual(markdown("<p>x<em> y</em></p>"), "x *y*")
        XCTAssertEqual(markdown("<p><a href=\"https://example.org\"> link </a>after</p>"), "[link](https://example.org) after")
    }

    func testLargeInputConvertsQuickly() {
        let chunk = "<div class=\"row\" style=\"color: red\"><p>Some <b>bold</b> and <a href=\"https://example.org/x\">link</a> text.</p></div>\n"
        let html = String(repeating: chunk, count: 5_000)
        let start = Date()
        let converted = HTMLToMarkdown.markdown(from: html)
        XCTAssertTrue(converted.hasPrefix("Some **bold** and [link](https://example.org/x) text."))
        // Compiling the attribute pattern for every tag took several seconds here.
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }

    func testMalformedTagsConvertInLinearTime() {
        let unclosedTags = String(repeating: "<a", count: 200_000)
        let start = Date()
        XCTAssertEqual(markdown(unclosedTags), unclosedTags)
        // Every `<` scanned to the end of the input: 80 KB of this took four seconds.
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
        XCTAssertEqual(markdown("<p title=\"unclosed><b>bold</b> <i>still converted</i></p>"), "<p title=\"unclosed>**bold** *still converted*")
    }

    func testScriptTextAndAnUnclosedHeadDoNotHideTheRest() {
        XCTAssertEqual(markdown("<script>for(i=0;i<n;i++){}</script><p>After script</p>"), "After script")
        XCTAssertEqual(markdown("<STYLE>a<b{color:red}</Style ><p>After style</p>"), "After style")
        XCTAssertEqual(markdown("<html><head><meta charset=utf-8><title>A <b> title</title><body><p>Hi</p>"), "Hi")
        XCTAssertEqual(markdown("<p>Before</p><script>never closed <p>hidden</p>"), "Before")
    }

    func testOrderedListStartAndItemValue() {
        XCTAssertEqual(markdown("<ol start=\"5\"><li>five</li><li>six</li></ol>"), "5. five\n6. six")
        XCTAssertEqual(markdown("<ol><li>one</li><li value=\"7\">seven</li><li>eight</li></ol>"), "1. one\n7. seven\n8. eight")
        XCTAssertEqual(markdown("<ol start=\"-3\"><li>zero</li></ol>"), "0. zero", "Markdown list numbers cannot be negative.")
    }

    func testTextAfterANestedListBelongsToItsParentItem() {
        XCTAssertEqual(markdown("<ul><li>a<ul><li>b</li></ul>c</li><li>d</li></ul>"), "- a\n\t- b\n\n\tc\n- d",
                       "Without the blank line, c would continue item b.")
        XCTAssertEqual(markdown("<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>"), "- a\n\t- b\n- c")
    }

    func testScriptLinksAreDroppedWhateverTheirSpelling() {
        XCTAssertEqual(markdown("<a href=\"JavaScript:alert(1)\">x</a>"), "x")
        XCTAssertEqual(markdown("<a href=\" javascript:alert(1)\">y</a>"), "y")
        XCTAssertEqual(markdown("<a href=\"java&#9;script:alert(1)\">z</a>"), "z")
        XCTAssertEqual(markdown("<a href=\" https://example.org \">site</a>"), "[site](https://example.org)")
    }

    func testImageAltTextAndDestinationsAreEscaped() {
        XCTAssertEqual(markdown("<img src=\"x.png\" alt=\"a]b [c\">"), "![a\\]b \\[c](x.png)")
        XCTAssertEqual(markdown("<img src=\"x.png\" alt=\"multi\nline\">"), "![multi line](x.png)")
        XCTAssertEqual(markdown("<a href=\"https://x/a b>c\">x</a>"), "[x](<https://x/a b\\>c>)")
        XCTAssertEqual(markdown("<a href=\"https://x/a(b\">x</a>"), "[x](<https://x/a(b>)")
        XCTAssertEqual(markdown("<table><tr><td><img src=\"x.png\" alt=\"a|b\"></td></tr></table>"), "| ![a\\|b](x.png) |\n| --- |")
    }

    func testEntitiesByteOrderMarkRulesAndTheFirstLineOfPreformattedText() {
        XCTAssertEqual(markdown("<p>a&nbsp;&nbsp;&nbsp;b &eacute; &#0; x</p>"), "a\u{A0}\u{A0}\u{A0}b \u{E9} \u{FFFD} x")
        XCTAssertEqual(markdown("<p>10&nbsp;km and <b>&nbsp;bold&nbsp;</b></p>"), "10\u{A0}km and **bold**")
        XCTAssertEqual(markdown("<p>&nbsp;</p><p>next</p>"), "next")
        XCTAssertEqual(markdown("&Omega; &alpha; &sigmaf; &yuml; &iexcl; &divide; &euro; &#xD800;"), "\u{3A9} \u{3B1} \u{3C2} \u{FF} \u{A1} \u{F7} \u{20AC} \u{FFFD}")
        XCTAssertEqual(markdown("\u{FEFF}<p>bom</p>"), "bom")
        XCTAssertEqual(markdown("<pre>\ncode</pre>"), "```\ncode\n```")
        XCTAssertEqual(markdown("<pre>\n\ncode</pre>"), "```\n\ncode\n```", "Only the first line break is dropped.")
        XCTAssertEqual(markdown("<pre>a&nbsp;b</pre>"), "```\na b\n```")
        XCTAssertEqual(markdown("<hr></hr>"), "---")
    }

    func testDestinationsReadBackAsTheCheckedURL() {
        XCTAssertEqual(markdown("<a href=\"javascript&amp;colon;alert(1)\">x</a>"), "[x](<javascript\\&colon;alert(1)>)",
                       "Unescaped, a Markdown renderer would decode &colon; into a script URL.")
        XCTAssertEqual(markdown("<a href=\"javascript\\:alert(1)\">x</a>"), "[x](<javascript\\\\:alert(1)>)")
        XCTAssertEqual(markdown("<a href=\"https://x/?a=1&amp;b=2\">q</a>"), "[q](https://x/?a=1&b=2)")
        XCTAssertEqual(markdown("<table><tr><td><a href=\"https://x/a|b\">l</a></td></tr></table>"), "| [l](https://x/a\\|b) |\n| --- |")
    }

    func testSignedCharacterReferencesStayText() {
        XCTAssertEqual(markdown("<p>&#+65; &#x+41; &#65;</p>"), "&#+65; &#x+41; A")
    }

    func testDeepNestingIsBounded() {
        let deepQuote = String(repeating: "<blockquote>", count: 100) + "deep" + String(repeating: "</blockquote>", count: 100) + "<p>after</p>"
        let lines = markdown(deepQuote).components(separatedBy: "\n")
        XCTAssertEqual(lines.first, String(repeating: "> ", count: 64) + "deep")
        XCTAssertEqual(lines.last, "after", "End tags past the limit close nothing, so the outer quotes still end.")
        let unclosedLists = String(repeating: "<ul><li>item", count: 20_000)
        let start = Date()
        let converted = markdown(unclosedLists)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
        XCTAssertLessThan(converted.utf8.count, 20_000 * 80, "Every line's prefix is bounded by the nesting limit.")
    }

    func testCodeAfterANestedListNeedsNoBlankLineAfterIt() {
        XCTAssertEqual(markdown("<ul><li>a<ul><li>b</li></ul><pre>c</pre>d</li></ul>"), "- a\n\t- b\n\t```\n\tc\n\t```\n\td")
    }
}
