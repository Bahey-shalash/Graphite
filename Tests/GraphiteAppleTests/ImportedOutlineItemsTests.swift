import XCTest
import CoreGraphics
import PDFKit
import GraphiteCore
import NotebookImport
import GraphiteTestSupport
@testable import GraphiteApple

/// An imported notebook's outline written as PDF outline items before its bookmarks, each on its written page; and a
/// page its plan leaves out, which is not written but keeps its report.
final class ImportedOutlineItemsTests: XCTestCase {
    private struct NoFiles: ImportSourceFiles {
        struct MissingFile: Error {}

        func contents(of file: ImportedSourceFile) throws -> Data {
            throw MissingFile()
        }
    }

    private static let pageSize = CGSize(width: 600, height: 900)
    private static let white = NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)

    private static func plan(_ sourcePageNumber: Int, isBookmarked: Bool = false) -> ImportedPagePlan {
        ImportedPagePlan(sourcePageNumber: sourcePageNumber, sizeInPoints: pageSize, background: .plainColor(white), strokes: [],
                         isBookmarked: isBookmarked, report: [])
    }

    private func write(_ outcomes: [ImportedPageOutcome], outline: [ImportedOutlineEntry]) throws -> (document: PDFDocument, writing: NotebookImportWriting) {
        let vault = try TemporaryVault.make(prefix: "ImportedOutlineItems", for: self)
        let destination = vault.location(of: "Outlined.pdf")
        let writing = try NotebookImportWriter(fileWriter: AtomicFileWriter()).write(sourcePageCount: outcomes.count,
                                                                                     outcomeForPage: { pageIndex in outcomes[pageIndex] }, outline: outline,
                                                                                     sourceFiles: NoFiles(), strokeCreationDate: Date(timeIntervalSince1970: 0),
                                                                                     to: destination)
        return (try XCTUnwrap(PDFDocument(url: destination)), writing)
    }

    func testOutlineEntriesComeFirstAtTheirPointsAndTheBookmarksFollow() throws {
        let (document, writing) = try write([.planned(Self.plan(1)), .planned(Self.plan(2, isBookmarked: true)), .planned(Self.plan(3))], outline: [
            ImportedOutlineEntry(title: "Chapter 1", sourcePageNumber: 1, pointInPoints: CGPoint(x: 60, y: 120)),
            ImportedOutlineEntry(title: "Chapter 2", sourcePageNumber: 3, pointInPoints: nil)
        ])
        let outline = try XCTUnwrap(document.outlineRoot)
        let items = (0..<outline.numberOfChildren).compactMap(outline.child(at:))
        XCTAssertEqual(items.map(\.label), ["Chapter 1", "Chapter 2", "Page 2"])
        XCTAssertEqual(items.compactMap(\.destination?.page).map(document.index(for:)), [0, 2, 1])
        XCTAssertEqual(items[0].destination?.point, CGPoint(x: 60, y: 900 - 120), "Top-left page points in the PDF page's own space.")
        XCTAssertEqual(items[1].destination?.point, CGPoint(x: 0, y: 900), "A whole page opens at its top-left corner.")
        XCTAssertEqual(writing.notebookEntries, [])
    }

    func testAPageItsPlanLeavesOutIsNotWrittenAndAnEntryOnItIsCounted() throws {
        let (document, writing) = try write([.planned(Self.plan(1)), .leftOut(sourcePageNumber: 2, report: [.pageWithoutPaper]), .planned(Self.plan(3))],
                                            outline: [ImportedOutlineEntry(title: "On the lost page", sourcePageNumber: 2, pointInPoints: nil),
                                                      ImportedOutlineEntry(title: "Kept", sourcePageNumber: 3, pointInPoints: nil)])
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(writing.pageReports.map(\.sourcePageNumber), [1, 2, 3])
        XCTAssertEqual(writing.pageReports.map { report in report.written != nil }, [true, false, true])
        XCTAssertEqual(writing.pageReports[1].entries, [.pageWithoutPaper])
        let outline = try XCTUnwrap(document.outlineRoot)
        XCTAssertEqual(outline.numberOfChildren, 1)
        XCTAssertEqual(outline.child(at: 0)?.destination?.page.map(document.index(for:)), 1, "Source page 3 is the second page written.")
        XCTAssertEqual(writing.notebookEntries, [.outlineEntriesWithoutPage(count: 1)])
    }

    func testANotebookWhosePagesAreAllLeftOutWritesNothing() throws {
        let vault = try TemporaryVault.make(prefix: "ImportedOutlineItems", for: self)
        let destination = vault.location(of: "Nothing.pdf")
        XCTAssertThrowsError(try NotebookImportWriter(fileWriter: AtomicFileWriter()).write(sourcePageCount: 1, outcomeForPage: { _ in
            .leftOut(sourcePageNumber: 1, report: [.pageWithoutPaper])
        }, outline: [], sourceFiles: NoFiles(), strokeCreationDate: Date(timeIntervalSince1970: 0), to: destination)) { error in
            guard case .noPages? = error as? NotebookImportWriterError else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
