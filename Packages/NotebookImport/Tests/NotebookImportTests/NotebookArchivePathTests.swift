import XCTest
@testable import NotebookImport

/// CC-IMPORT-10: paths read from a notebook left the readers as plain strings, `../../x` and `/etc/x` included.
final class NotebookArchivePathTests: XCTestCase {
    func testOnlyRelativePathsThatCannotClimbOutAreAccepted() {
        for safePath in ["Images/Image 1.png", "PDFs/Lecture.pdf", "attachments/1B2DC67A", "Recordings/Sub folder/Recording 1.m4a", "a..b/c"] {
            XCTAssertEqual(NotebookArchivePath(validating: safePath)?.text, safePath)
        }
        for unsafePath in ["", "/etc/x", "../../x", "Images/../../x", "Images/./x", "Images//x", "Images/", "a\\b", "Images/\u{0}x", "Images/\nx"] {
            XCTAssertNil(NotebookArchivePath(validating: unsafePath), unsafePath)
        }
    }

    func testAFileInAFolderMustBeOneSafeName() {
        XCTAssertEqual(NotebookArchivePath.file(named: "Lecture.pdf", inFolder: "PDFs")?.text, "PDFs/Lecture.pdf")
        XCTAssertEqual(NotebookArchivePath.file(named: "Lecture.pdf", inFolder: "PDFs")?.fileName, "Lecture.pdf")
        for unsafeName in ["", "..", "../x", "a/b", "/x"] { XCTAssertNil(NotebookArchivePath.file(named: unsafeName, inFolder: "PDFs"), unsafeName) }
    }
}
