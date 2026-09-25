import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Heading jumps find the heading the outline lists (F511).
final class UiEditorHeadingJumpTests: XCTestCase {
    private let note = """
    ---
    # Summary
    title: A note
    ---
    ```
    # Summary
    ```
    ## Summary
    Text
    ## Notes
    First
    ## Notes
    Second
    """ as NSString

    func testFrontmatterCommentsAndCodeAreNotHeadings() {
        XCTAssertEqual(HeadingLocator.lineLocation(ofHeadingWithAnchor: "summary", in: note), note.range(of: "## Summary").location)
    }

    func testOccurrencePicksAmongHeadingsThatReadTheSame() {
        let firstNotes = note.range(of: "## Notes").location
        let secondNotes = note.range(of: "## Notes", range: NSRange(location: firstNotes + 1, length: note.length - firstNotes - 1)).location
        XCTAssertEqual(HeadingLocator.lineLocation(ofHeadingWithAnchor: "notes", in: note), firstNotes)
        XCTAssertEqual(HeadingLocator.lineLocation(ofHeadingWithAnchor: "notes", occurrence: 1, in: note), secondNotes)
        XCTAssertNil(HeadingLocator.lineLocation(ofHeadingWithAnchor: "notes", occurrence: 2, in: note))
    }
}
