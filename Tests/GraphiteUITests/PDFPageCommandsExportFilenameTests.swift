import XCTest
@testable import GraphiteUI

/// The name a page export is offered under: `<stem> page N`, `<stem> pages 1-3, 7`, or
/// `<stem> N pages` once the ranges would take more than 40 characters.
@MainActor
final class PDFPageCommandsExportFilenameTests: XCTestCase {
    func testASinglePageIsNamedByItsNumberCountedFromOne() {
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [0]), "Notes page 1")
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [11]), "Notes page 12")
    }

    func testRunsAreWrittenAsRangesAndGapsAsSeparateEntries() {
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [0, 1]), "Notes pages 1-2")
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [0, 1, 2, 6]), "Notes pages 1-3, 7")
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [1, 3]), "Notes pages 2, 4")
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Slides 2026", pageIndices: [8, 9, 10, 11]), "Slides 2026 pages 9-12")
    }

    func testTheRangesStayInTheNameUpToFortyCharactersAndTheCountReplacesThemBeyond() {
        let exactlyForty = "1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21-23"
        let fortyOne = "1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23"
        XCTAssertEqual(exactlyForty.count, 40)
        XCTAssertEqual(fortyOne.count, 41)
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 21, 22]), "Notes pages \(exactlyForty)")
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Notes", pageIndices: [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22]), "Notes 12 pages")
    }

    func testALongRunIsStillNamedByItsRange() {
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Book", pageIndices: Array(0..<500)), "Book pages 1-500")
    }

    func testTheStemIsKeptAsGiven() {
        XCTAssertEqual(PDFPageCommands.exportFilename(stem: "Lecture 3 – Fourier", pageIndices: [4]), "Lecture 3 – Fourier page 5")
    }
}
