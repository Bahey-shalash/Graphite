import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class DroppedFileImportersTests: XCTestCase {
    private func importer(_ extensions: Set<String>) -> FileTypeImporter {
        FileTypeImporter(fileExtensions: extensions, importFiles: { _, _ in })
    }

    func testFilesGoToTheFirstImporterThatTakesTheirType() {
        let notebookImporter = importer(["goodnotes", "note"])
        let otherImporter = importer(["note"])
        let routing = DroppedFileImporters.route([URL(fileURLWithPath: "/a/Week.GoodNotes"), URL(fileURLWithPath: "/a/Quick.note"),
                                                  URL(fileURLWithPath: "/a/Slides.pdf")], through: [notebookImporter, otherImporter])
        XCTAssertEqual(routing.routed.count, 1)
        XCTAssertEqual(routing.routed[0].files.map(\.lastPathComponent), ["Week.GoodNotes", "Quick.note"])
        XCTAssertEqual(routing.remaining.map(\.lastPathComponent), ["Slides.pdf"])
    }

    func testWithNoImporterEveryFileIsCopiedPlainly() {
        let routing = DroppedFileImporters.route([URL(fileURLWithPath: "/a/Slides.pdf")], through: [])
        XCTAssertTrue(routing.routed.isEmpty)
        XCTAssertEqual(routing.remaining.count, 1)
    }

    func testTextFilesBecomeNotesAndOtherFilesKeepTheirType() {
        XCTAssertEqual(ImportedFileName.fileExtension(forSourceExtension: "txt"), "md")
        XCTAssertEqual(ImportedFileName.fileExtension(forSourceExtension: "TXT"), "md")
        XCTAssertEqual(ImportedFileName.fileExtension(forSourceExtension: "markdown"), "md")
        XCTAssertEqual(ImportedFileName.fileExtension(forSourceExtension: "md"), "md")
        XCTAssertEqual(ImportedFileName.fileExtension(forSourceExtension: "pdf"), "pdf")
        XCTAssertEqual(ImportedFileName.fileExtension(forSourceExtension: "jpeg"), "jpeg")
    }
}
