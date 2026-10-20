import XCTest
@testable import GraphiteCore

/// Return inside a fenced code block written in a quote or callout is a plain line break:
/// `MarkdownEditing.continuingList` must not read the code as list markup.
final class MarkdownEditingQuotedCodeContinuationTests: XCTestCase {
    private func edit(_ text: String) -> MarkdownTextEdit? {
        let source = text as NSString
        return MarkdownEditing.continuingList(in: source, selection: NSRange(location: source.length, length: 0), indentUnit: "\t")
    }

    func testReturnAtTheEndOfAQuotedBulletInsideAQuotedFenceAddsNoListMarkup() {
        XCTAssertNil(edit("> [!example]\n> ```yaml\n> - item"))
    }

    func testReturnOnAnEmptyQuoteLineInsideAQuotedFenceKeepsTheQuote() {
        XCTAssertNil(edit("> [!example]\n> ```yaml\n> key: value\n> "))
    }

    func testReturnInsideATildeFenceInANestedQuoteAddsNoListMarkup() {
        XCTAssertNil(edit("> > ~~~\n> > 1. step"))
    }

    func testReturnAtTheEndOfAQuotedBulletAfterTheQuotedFenceClosedContinuesTheList() throws {
        let text = "> ```yaml\n> a: 1\n> ```\n> - item"
        let continued = try XCTUnwrap(edit(text))
        XCTAssertEqual(continued.replacement, "\n> - ")
    }

    func testAQuotedFenceEndsWhereTheQuoteEnds() throws {
        let text = "> ```\n> code\n- item"
        let continued = try XCTUnwrap(edit(text))
        XCTAssertEqual(continued.replacement, "\n- ")
    }

    func testReturnAtTheEndOfAQuotedBulletOutsideAnyFenceStillContinuesTheList() throws {
        let continued = try XCTUnwrap(edit("> - item"))
        XCTAssertEqual(continued.replacement, "\n> - ")
    }

    func testAnUnquotedFenceStillStopsListContinuation() {
        XCTAssertNil(edit("```\n- item"))
    }
}
