import XCTest
import PDFKit
import GraphiteCore
import NotebookImport
import GraphiteFixtures
import GraphiteTestSupport
@testable import GraphiteApple

/// The synthetic notebooks of `Tests/SyntheticNotebooks` (built by NotebookImport's own test builders, nothing from a real
/// notebook) converted end to end: opened from their files, written as a PDF and recordings, and reported.
final class NotebookConversionTests: XCTestCase {
    private let strokeCreationDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var goodnotesNotebook: URL { FixtureFolders.syntheticNotebooks.appendingPathComponent("Synthetic lecture.goodnotes") }
    private var notabilityNote: URL { FixtureFolders.syntheticNotebooks.appendingPathComponent("Synthetic note.note") }

    private func convert(_ location: URL, format: NotebookFileFormat, into vault: TemporaryVault)
        throws -> (notebook: OpenedNotebook, writing: NotebookImportWriting, document: PDFDocument) {
        let notebook = try OpenedNotebook.open(location, format: format, limits: .standard)
        let destination = vault.location(of: "Imported.pdf")
        var pagesDone: [Int] = []
        let conversion = NotebookConversion(fileWriter: AtomicFileWriter())
        let writing = try conversion.writePDF(of: notebook, to: destination, strokeCreationDate: strokeCreationDate) { count in pagesDone.append(count) }
        XCTAssertEqual(pagesDone, Array(0...notebook.sourcePageCount), "Each page is announced before it is written, and the end once.")
        return (notebook, writing, try XCTUnwrap(PDFDocument(url: destination)))
    }

    func testAGoodnotesNotebookBecomesAPDFWithItsInkPictureOutlineAndBookmark() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookConversion", for: self)
        let sourceBefore = try Data(contentsOf: goodnotesNotebook)
        let (notebook, writing, document) = try convert(goodnotesNotebook, format: .goodnotes, into: vault)
        XCTAssertEqual(notebook.sourcePageCount, 4)
        XCTAssertEqual(document.pageCount, 3, "The fourth page has no paper and is left out.")
        XCTAssertEqual(writing.pageReports.map(\.sourcePageNumber), [1, 2, 3, 4])
        XCTAssertNil(writing.pageReports[3].written)
        XCTAssertEqual(writing.pageReports[3].entries.first { entry in entry == .pageWithoutPaper }, .pageWithoutPaper)
        let firstPage = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(firstPage.bounds(for: .cropBox).size, CGSize(width: 600, height: 900))
        XCTAssertEqual(firstPage.annotations.map(\.type), ["Stamp", "Ink", "Ink"], "The picture under the stroke's two subpaths.")
        let outline = try XCTUnwrap(document.outlineRoot)
        XCTAssertEqual((0..<outline.numberOfChildren).compactMap { childIndex in outline.child(at: childIndex)?.label }, ["Chapter 2", "Page 3"],
                       "The outline entry first, then the bookmark.")
        let entry = try XCTUnwrap(outline.child(at: 0)?.destination)
        XCTAssertEqual(entry.page.flatMap { page in document.index(for: page) }, 1)
        XCTAssertEqual(entry.point.x, 60, accuracy: 0.01, "110 units are 60 points.")
        XCTAssertEqual(entry.point.y, 900 - 120, accuracy: 0.01, "220 units down are 120 points from the top.")
        let recordingLocation = vault.location(of: "Imported - Recording 1.m4a")
        XCTAssertTrue(NotebookConversion(fileWriter: AtomicFileWriter()).writeRecording(at: 0, of: notebook, to: recordingLocation))
        let report = NotebookConversion(fileWriter: AtomicFileWriter()).report(of: notebook, writing: writing, copiedRecordingCount: 1)
        XCTAssertEqual(report.recordingCount, 1)
        XCTAssertTrue(report.notebookEntries.contains(.recordingTimingNotKept(timedElementCount: 1)))
        XCTAssertEqual(report.writtenPageCount, 3)
        XCTAssertEqual(try Data(contentsOf: goodnotesNotebook), sourceBefore, "The notebook is only read.")
        XCTAssertEqual(try Data(contentsOf: recordingLocation).prefix(8).suffix(4), Data("ftyp".utf8))
    }

    func testANotabilityNoteIsCutIntoItsPagesAndItsRecordingCopied() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookConversion", for: self)
        let (notebook, writing, document) = try convert(notabilityNote, format: .notability, into: vault)
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(writing.pageReports.compactMap(\.written).map(\.strokeCount), [1, 1])
        XCTAssertEqual(notebook.recordings.recordings.map(\.name), ["Lecture"])
        XCTAssertTrue(NotebookConversion(fileWriter: AtomicFileWriter()).writeRecording(at: 0, of: notebook, to: vault.location(of: "Note - Lecture.m4a")))
        XCTAssertFalse(NotebookConversion(fileWriter: AtomicFileWriter()).writeRecording(at: 0, of: notebook, to: vault.location(of: "Note - Lecture.m4a")),
                       "A recording never replaces a file.")
        XCTAssertNil(document.outlineRoot, "Notability keeps no outline.")
    }

    func testAFileThatIsNotANotebookFailsWithoutWritingAnything() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookConversion", for: self)
        let notANotebook = try vault.writeFile("Slides.goodnotes", text: "not a notebook")
        XCTAssertThrowsError(try OpenedNotebook.open(notANotebook, format: .goodnotes, limits: .standard)) { error in
            XCTAssertEqual(error as? NotebookImportFailure, .notANotebook(.goodnotes))
        }
        XCTAssertThrowsError(try OpenedNotebook.open(goodnotesNotebook, format: .notability, limits: .standard)) { error in
            XCTAssertEqual(error as? NotebookImportFailure, .notANotebook(.notability), "A Goodnotes archive has no note folder.")
        }
        XCTAssertThrowsError(try OpenedNotebook.open(vault.location(of: "Missing.note"), format: .notability, limits: .standard)) { error in
            XCTAssertEqual(error as? NotebookImportFailure, .sourceUnreadable)
        }
    }

    func testAPDFIsNeverWrittenOverAFile() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookConversion", for: self)
        let notebook = try OpenedNotebook.open(goodnotesNotebook, format: .goodnotes, limits: .standard)
        let destination = try vault.writeFile("Taken.pdf", text: "someone else's")
        XCTAssertThrowsError(try NotebookConversion(fileWriter: AtomicFileWriter()).writePDF(of: notebook, to: destination,
                                                                                             strokeCreationDate: strokeCreationDate) { _ in }) { error in
            XCTAssertEqual(error as? NotebookImportFailure, .notWritten)
        }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "someone else's")
    }

    func testACancelledConversionLeavesNoPDF() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookConversion", for: self)
        let notebook = try OpenedNotebook.open(goodnotesNotebook, format: .goodnotes, limits: .standard)
        let destination = vault.location(of: "Cancelled.pdf")
        let expectation = expectation(description: "converted")
        let task = Task.detached { [strokeCreationDate] in
            withUnsafeCurrentTask { task in task?.cancel() }
            XCTAssertThrowsError(try NotebookConversion(fileWriter: AtomicFileWriter()).writePDF(of: notebook, to: destination,
                                                                                                 strokeCreationDate: strokeCreationDate) { _ in }) { error in
                XCTAssertTrue(error is CancellationError)
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 60)
        _ = task
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
