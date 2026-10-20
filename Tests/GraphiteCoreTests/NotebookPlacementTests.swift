import XCTest
@testable import GraphiteCore

final class NotebookPlacementTests: XCTestCase {
    func testEmbeddedNotebookIsEmbedded() {
        XCTAssertEqual(NotebookPlacement.embeddedInNote.insertedText(fromEmbed: "![[Week 1.pdf]]"), "![[Week 1.pdf]]")
    }

    func testNotebookInAFolderIsLinkedByDefault() throws {
        let placement = NotebookPlacement.inFolder(try VaultPath("Courses"), insertsEmbed: false)
        XCTAssertEqual(placement.insertedText(fromEmbed: "![[Week 1.pdf]]"), "[[Week 1.pdf]]")
        XCTAssertEqual(placement.insertedText(fromEmbed: "![Week 1](Courses/Week%201.pdf)"), "[Week 1](Courses/Week%201.pdf)")
    }

    func testNotebookInAFolderCanBeEmbedded() throws {
        let placement = NotebookPlacement.inFolder(try VaultPath("Courses"), insertsEmbed: true)
        XCTAssertEqual(placement.insertedText(fromEmbed: "![[Week 1.pdf]]"), "![[Week 1.pdf]]")
    }
}
