import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The link to a note under the pointer in either editor: a Wikilink or a Markdown link,
/// whether Live Preview hides its markup or not, with its whole range in the note.
final class EditorLinkUnderPointerTests: XCTestCase {
    private let note = "# Notes\nSee [[Lab notebook#Result|the result]] and [slides](Slides.md).\nA [site](https://example.com), an ![[Diagram.png]] embed, `[[Code]]` and [[Last]]"

    private func link(atStartOf substring: String) -> EditorLinkUnderPointer? {
        let source = note as NSString
        return EditorLinkUnderPointer.link(at: source.range(of: substring).location, in: source)
    }

    func testAWikilinkIsFoundWithItsTargetAndItsWholeRangeInTheNote() throws {
        let found = try XCTUnwrap(link(atStartOf: "the result"))
        XCTAssertEqual(found.target, "Lab notebook#Result")
        XCTAssertTrue(found.isWiki)
        XCTAssertEqual((note as NSString).substring(with: found.range), "[[Lab notebook#Result|the result]]")
    }

    func testAMarkdownLinkToANoteIsFoundWithItsDestination() throws {
        let found = try XCTUnwrap(link(atStartOf: "slides]"))
        XCTAssertEqual(found.target, "Slides.md")
        XCTAssertFalse(found.isWiki)
    }

    func testWebLinksEmbedsAndLinksWrittenInCodeAreNotNoteLinks() {
        XCTAssertNil(link(atStartOf: "site]"))
        XCTAssertNil(link(atStartOf: "Diagram"))
        XCTAssertNil(link(atStartOf: "Code"))
        XCTAssertNil(link(atStartOf: "Notes"))
    }

    func testALinkAtTheVeryEndOfTheNoteIsFoundAndPastTheEndNothingIs() throws {
        XCTAssertEqual(try XCTUnwrap(link(atStartOf: "Last")).target, "Last")
        XCTAssertNil(EditorLinkUnderPointer.link(at: (note as NSString).length, in: note as NSString))
        XCTAssertNil(EditorLinkUnderPointer.link(at: -1, in: note as NSString))
    }
}
