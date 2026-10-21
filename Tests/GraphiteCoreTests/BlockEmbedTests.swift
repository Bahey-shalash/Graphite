import GraphiteTestSupport
import XCTest
@testable import GraphiteCore

final class BlockEmbedTests: XCTestCase {
    func testEmbedsShowTheBlockOrSection() {
        let body = "# One\nintro\n\n## Two\nPara ^abc\n\nother"
        XCTAssertEqual(NoteBlocks.embeddedPart(of: body, subpath: "^abc"), "Para")
        XCTAssertEqual(NoteBlocks.embeddedPart(of: body, subpath: "Two"), "## Two\nPara ^abc\n\nother")
        // A subpath that names nothing is reported, as in Obsidian, not shown as the whole note.
        XCTAssertNil(NoteBlocks.embeddedPart(of: body, subpath: "^missing"))
        XCTAssertNil(NoteBlocks.embeddedPart(of: body, subpath: "Missing heading"))
        XCTAssertEqual(NoteBlocks.embeddedPart(of: body, subpath: nil), body)
    }
}
