import XCTest
import NotebookImport
import GraphiteTestSupport
@testable import GraphiteApple

/// A chosen folder of notebooks, as a Goodnotes or Notability library export lays it out, is listed with the folders
/// between it and each notebook, so the import keeps them.
final class NotebookLibraryListingTests: XCTestCase {
    func testNotebooksAtAnyDepthAreListedWithTheirFoldersAndOtherFilesAreCounted() throws {
        let export = try TemporaryVault.make(prefix: "NotebookLibraryListing", for: self)
        for path in ["Physics/Lectures/Lecture 1.goodnotes", "Physics/Lectures/Lecture 10.goodnotes", "Physics/Lecture 2.GOODNOTES",
                     "Chemistry/Week 1.note", "Notes.note", "Physics/Lectures/Slides.pdf", ".goodnotesmeta", "Physics/.hidden.goodnotes"] {
            try export.writeFile(path, data: Data([0]))
        }
        let listing = try NotebookLibraryListing.list(export.root)
        XCTAssertEqual(listing.notebooks.map(\.location.lastPathComponent),
                       ["Week 1.note", "Notes.note", "Lecture 2.GOODNOTES", "Lecture 1.goodnotes", "Lecture 10.goodnotes"],
                       "In Finder's order of the paths: names with numbers by their value, files and folders together.")
        XCTAssertEqual(listing.notebooks.map(\.folderPath), [["Chemistry"], [], ["Physics"], ["Physics", "Lectures"], ["Physics", "Lectures"]])
        XCTAssertEqual(listing.notebooks.map(\.format), [.notability, .notability, .goodnotes, .goodnotes, .goodnotes])
        XCTAssertEqual(listing.otherFileCount, 1, "The PDF; hidden files are not counted.")
    }

    func testAFolderThatCannotBeReadIsAnError() {
        XCTAssertThrowsError(try NotebookLibraryListing.list(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)", isDirectory: true)))
    }
}
