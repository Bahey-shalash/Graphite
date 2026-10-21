import GraphiteTestSupport
import XCTest
@testable import GraphiteCore

final class PDFCitationTests: XCTestCase {
    func testPageLinksNameTheFileAndPage() {
        XCTAssertEqual(PDFCitation.pageLink(linkTarget: "Signals.pdf", displayName: "Signals", pageNumber: 3, usesWikilinks: true),
                       "[[Signals.pdf#page=3|Signals, p.3]]")
        XCTAssertEqual(PDFCitation.pageLink(linkTarget: "Course/Week 1 [draft].pdf", displayName: "Week 1 [draft]", pageNumber: 12, usesWikilinks: false),
                       "[Week 1 \\[draft\\], p.12](Course/Week%201%20%5Bdraft%5D.pdf#page=12)")
    }

    func testQuotesJoinBrokenLinesAndHyphenatedWords() {
        let selected = "The quick brown fox jum-\nps over the lazy dog, then\nrests.\n\nA second para-\ngraph with Hyphen-\nated Names."
        XCTAssertEqual(PDFCitation.quote(selected, link: "[[Book.pdf#page=4|Book, p.4]]"), """
            > The quick brown fox jumps over the lazy dog, then rests.
            >
            > A second paragraph with Hyphenated Names.

            [[Book.pdf#page=4|Book, p.4]]
            """)
    }

    func testQuotesAreSeparatedFromTheTextAround() {
        let quote = "> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]"
        func inserted(into source: String, at location: Int) -> String {
            let insertion = MarkdownBlockInsertion.text(inserting: quote, into: source as NSString, replacing: NSRange(location: location, length: 0),
                                                        separatedByBlankLines: true)
            return (source as NSString).replacingCharacters(in: NSRange(location: location, length: 0), with: insertion)
        }
        XCTAssertEqual(inserted(into: "# Title\nText\n", at: 0), "> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]\n\n# Title\nText\n")
        XCTAssertEqual(inserted(into: "Line one\nLine two", at: 8), "Line one\n\n> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]\n\nLine two",
                       "In the middle, blank lines on both sides.")
        XCTAssertEqual(inserted(into: "# Notes\n\n", at: 9), "# Notes\n\n> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]\n",
                       "At the end, after a blank line already there.")
        XCTAssertEqual(inserted(into: "# Notes", at: 7), "# Notes\n\n> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]\n")
    }

    func testQuotesKeepHyphensBeforeDigitsAndCapitals() {
        XCTAssertEqual(PDFCitation.readableParagraphs(of: "from 1990-\n2000 in the Mid-\nAtlantic\r\nend"), ["from 1990-2000 in the Mid-Atlantic end"])
        XCTAssertEqual(PDFCitation.readableParagraphs(of: "a well-\nknown result"), ["a wellknown result"], "Indistinguishable from hyphenation.")
        XCTAssertEqual(PDFCitation.readableParagraphs(of: "  spaced   out \u{00A0} text  "), ["spaced out text"])
    }
}
