import XCTest
@testable import NotebookImport

/// A notebook's format is named by its file extension, whatever its case; any other extension is no notebook.
final class NotebookFileFormatTests: XCTestCase {
    func testEachAppsExtensionNamesItsFormatInAnyCase() {
        XCTAssertEqual(NotebookFileFormat(fileExtension: "goodnotes"), .goodnotes)
        XCTAssertEqual(NotebookFileFormat(fileExtension: "GoodNotes"), .goodnotes)
        XCTAssertEqual(NotebookFileFormat(fileExtension: "note"), .notability)
        XCTAssertEqual(NotebookFileFormat(fileExtension: "NOTE"), .notability)
        XCTAssertEqual(NotebookFileFormat.allCases.map(\.fileExtension), ["goodnotes", "note"])
    }

    func testOtherExtensionsAreNoNotebook() {
        for fileExtension in ["", "pdf", "notes", "goodnote", "note.zip", "nbn"] {
            XCTAssertNil(NotebookFileFormat(fileExtension: fileExtension), fileExtension)
        }
    }
}
