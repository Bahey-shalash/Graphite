import XCTest
@testable import NotebookImport

/// The name of the PDF an imported notebook becomes: the notebook's file name without its extension, and without the
/// ".pdf" an app keeps in the name of a notebook made from a PDF, safe as one file name.
final class NotebookImportNameTests: XCTestCase {
    func testTheExtensionAndAKeptPDFExtensionAreDropped() {
        XCTAssertEqual(NotebookImportName.pdfStem(forNotebookFileName: "Lecture 3.goodnotes", fallback: "Notebook"), "Lecture 3")
        XCTAssertEqual(NotebookImportName.pdfStem(forNotebookFileName: "Past exam.pdf.goodnotes", fallback: "Notebook"), "Past exam")
        XCTAssertEqual(NotebookImportName.pdfStem(forNotebookFileName: "Slides.PDF.note", fallback: "Notebook"), "Slides")
        XCTAssertEqual(NotebookImportName.pdfStem(forNotebookFileName: "Série 1.2.note", fallback: "Notebook"), "Série 1.2")
    }

    func testANameThatLeavesNothingUsableTakesTheFallback() {
        XCTAssertEqual(NotebookImportName.pdfStem(forNotebookFileName: ".goodnotes", fallback: "Notebook"), "Notebook")
        XCTAssertEqual(NotebookImportName.pdfStem(forNotebookFileName: "  .pdf.note", fallback: "Notebook"), "Notebook")
    }

    func testSeparatorsAndControlCharactersBecomeHyphens() {
        XCTAssertEqual(NotebookImportName.pdfStem(forNotebookFileName: "A:B\nC.goodnotes", fallback: "Notebook"), "A-B-C")
    }
}
