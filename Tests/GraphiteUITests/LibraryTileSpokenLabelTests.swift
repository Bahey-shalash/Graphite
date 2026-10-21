import XCTest
@testable import GraphiteUI

final class LibraryTileSpokenLabelTests: XCTestCase {
    func testAFileIsReadAsNameKindAndDate() {
        XCTAssertEqual(LibraryTileSpokenLabel.file(name: "Week 1", kind: "PDF", modifiedText: "21 Oct 2026 at 18:12"), "Week 1, PDF, 21 Oct 2026 at 18:12")
    }

    func testAFolderIsReadAsNameLookAndItemCount() {
        XCTAssertEqual(LibraryTileSpokenLabel.folder(name: "Courses", lookDescription: "green, flask", itemCount: 12), "Courses, Folder, green, flask, 12 items")
        XCTAssertEqual(LibraryTileSpokenLabel.folder(name: "Courses", lookDescription: nil, itemCount: 1), "Courses, Folder, 1 item")
        XCTAssertEqual(LibraryTileSpokenLabel.folder(name: "Courses", lookDescription: nil, itemCount: 0), "Courses, Folder, 0 items")
    }

    func testAFolderStillBeingCountedIsReadWithoutACount() {
        XCTAssertEqual(LibraryTileSpokenLabel.folder(name: "Courses", lookDescription: "", itemCount: nil), "Courses, Folder")
    }

    func testTheFavoriteStateIsNotInTheLabel() {
        XCTAssertFalse(LibraryTileSpokenLabel.file(name: "A", kind: "Note", modifiedText: "today").contains("ookmark"))
        XCTAssertFalse(LibraryTileSpokenLabel.folder(name: "A", lookDescription: nil, itemCount: 2).contains("ookmark"))
    }
}
