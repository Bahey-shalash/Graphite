import XCTest
@testable import GraphiteCore

/// The fold key of a heading is the editor's, found by where the heading's line starts, so
/// the reading view needs nothing of the heading's rendered text to share a fold with it.
final class NoteFoldingHeadingKeyTests: XCTestCase {
    func testKeysAreFoundByTheStartOfTheHeadingLine() {
        let text = "---\ntitle: x\n---\n## Title ##\nBody\n\nSub\n---\nMore\n#  Spaced  \nEnd"
        let source = text as NSString
        let keys = NoteFolding.headingKeysByLineStart(in: text)
        XCTAssertEqual(keys[source.range(of: "## Title ##").location], "h2|## Title ##|0")
        XCTAssertEqual(keys[source.range(of: "Sub").location], "h2|Sub|0")
        XCTAssertEqual(keys[source.range(of: "#  Spaced  ").location], "h1|#  Spaced|0")
        XCTAssertEqual(keys.count, 3)
    }

    func testRepeatedHeadingsAreNumberedInTheOrderTheyAreWritten() {
        let text = "## Notes\na\n## Notes\nb\n"
        let keys = NoteFolding.headingKeysByLineStart(in: text)
        XCTAssertEqual(keys[0], "h2|## Notes|0")
        XCTAssertEqual(keys[(text as NSString).range(of: "## Notes", options: .backwards).location], "h2|## Notes|1")
    }

    func testListItemsAndHeadingsInCommentsAreNumberedAsTheEditorNumbersThem() {
        let text = "%%\n## Hidden\nx\n%%\n## Hidden\ny\n- item\n  child\n"
        let keys = NoteFolding.headingKeysByLineStart(in: text)
        XCTAssertEqual(keys[(text as NSString).range(of: "## Hidden", options: .backwards).location], "h2|## Hidden|1",
                       "The editor counts a heading inside a comment, so the second one is occurrence 1 in every view.")
        XCTAssertEqual(keys.count, 2, "List items have no heading key.")
    }
}
