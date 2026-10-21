import XCTest
import CoreGraphics
import PDFKit
import GraphiteCore
import NotebookImport
import GraphiteTestSupport
@testable import GraphiteApple

/// Ruled and grid paper drawn by Graphite's paper system with an imported notebook's ruling, and bookmarked pages
/// written as Graphite's bookmarks.
final class NotebookImportPaperAndBookmarkWriterTests: XCTestCase {
    private struct NoFiles: ImportSourceFiles {
        struct MissingFile: Error {}

        func contents(of file: ImportedSourceFile) throws -> Data {
            throw MissingFile()
        }
    }

    /// The rendering scale: a 0.4-point line covers whole pixels at four pixels per point.
    private static let pixelsPerPoint = 4.0
    private static let letterSize = CGSize(width: 612, height: 803.25)
    private static let cream = NotebookImportColor(red: 1, green: 248 / 255.0, blue: 231 / 255.0, alpha: 1)
    private static let rulingColor = NotebookImportColor(red: 0xA3 / 255.0, green: 0xB7 / 255.0, blue: 0xD3 / 255.0, alpha: 1)
    private static let creamComponents = [255, 248, 231]
    private static let rulingComponents = [163, 183, 211]

    func testRuledPaperIsDrawnWithTheNotebooksRowsColourAndPaper() throws {
        let ruledPaper = ImportedRuledPaper(paperColor: Self.cream, lineColor: Self.rulingColor, lineWidth: 0.5, spacing: 36, firstRowFromTop: 36,
                                            leftEdge: 15.9375, rightEdge: 612 - 15.9375, gridColumnAnchor: nil)
        let page = try XCTUnwrap(writtenDocument([Self.plan(background: .ruledPaper(ruledPaper))]).page(at: 0))
        XCTAssertEqual(page.bounds(for: .cropBox).size, Self.letterSize)
        assertColor(try drawnColor(of: page, at: CGPoint(x: 100, y: 36)), Self.rulingComponents, "The first row")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 100, y: 36 * 22)), Self.rulingComponents, "The last row")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 100, y: 54)), Self.creamComponents, "Paper between rows")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 8, y: 36)), Self.creamComponents, "Paper left of the rows")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 604, y: 36)), Self.creamComponents, "Paper right of the rows")
    }

    func testGridPaperHasItsColumnsAtTheAnchor() throws {
        let gridPaper = ImportedRuledPaper(paperColor: Self.cream, lineColor: Self.rulingColor, lineWidth: 0.4, spacing: 36, firstRowFromTop: 36,
                                           leftEdge: 15.9375, rightEdge: 612, gridColumnAnchor: 321.9375)
        let page = try XCTUnwrap(writtenDocument([Self.plan(background: .ruledPaper(gridPaper))]).page(at: 0))
        assertColor(try drawnColor(of: page, at: CGPoint(x: 321.9375, y: 10)), Self.rulingComponents, "The anchored column")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 321.9375 - 36, y: 800)), Self.rulingComponents, "A column a spacing left of it")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 340, y: 10)), Self.creamComponents, "Paper between columns")
        // A 0.4-point row centred on a pixel edge covers no pixel whole: the pixel is part ruling, part paper.
        let rowAtTheRightEdge = try drawnColor(of: page, at: CGPoint(x: 610, y: 36))
        XCTAssertLessThan(rowAtTheRightEdge[0], 200, "A row reaching the right edge: \(rowAtTheRightEdge)")
    }

    func testBookmarkedPagesBecomeGraphitesBookmarksInPageOrder() throws {
        let plans = [Self.plan(isBookmarked: true), Self.plan(isBookmarked: false), Self.plan(isBookmarked: true)]
        let document = try writtenDocument(plans)
        let outline = try XCTUnwrap(document.outlineRoot)
        let items = (0..<outline.numberOfChildren).compactMap(outline.child(at:))
        XCTAssertEqual(items.map(\.label), ["Page 1", "Page 3"])
        XCTAssertEqual(items.compactMap(\.destination?.page).map(document.index(for:)), [0, 2])
        XCTAssertTrue(items.allSatisfy { item in item.numberOfChildren == 0 })
    }

    func testANotebookWithoutBookmarksHasNoOutline() throws {
        XCTAssertNil(try writtenDocument([Self.plan(isBookmarked: false)]).outlineRoot)
    }

    private static func plan(background: ImportedPageBackground = .plainColor(cream), isBookmarked: Bool = false) -> ImportedPagePlan {
        ImportedPagePlan(sourcePageNumber: 1, sizeInPoints: letterSize, background: background, strokes: [], isBookmarked: isBookmarked, report: [])
    }

    private func writtenDocument(_ plans: [ImportedPagePlan]) throws -> PDFDocument {
        let vault = try TemporaryVault.make(prefix: "NotebookImportPaperAndBookmarkWriter", for: self)
        let destination = vault.location(of: "Imported notebook.pdf")
        _ = try NotebookImportWriter(fileWriter: AtomicFileWriter()).write(sourcePageCount: plans.count,
                                                                           outcomeForPage: { pageIndex in .planned(plans[pageIndex]) }, outline: [],
                                                                           sourceFiles: NoFiles(), strokeCreationDate: Date(timeIntervalSince1970: 0),
                                                                           to: destination)
        return try XCTUnwrap(PDFDocument(url: destination))
    }

    /// The color of the page as drawn at `pixelsPerPoint`, at a point in top-left page coordinates, as 0 to 255 sRGB
    /// components.
    private func drawnColor(of page: PDFPage, at point: CGPoint) throws -> [Int] {
        let size = page.bounds(for: .mediaBox).size
        let pixelWidth = Int(size.width * Self.pixelsPerPoint), pixelHeight = Int(size.height * Self.pixelsPerPoint)
        var pixelBytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        try pixelBytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                                  bytesPerRow: pixelWidth * 4, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: Self.pixelsPerPoint, y: Self.pixelsPerPoint)
            page.draw(with: .mediaBox, to: context)
        }
        let row = Int(point.y * Self.pixelsPerPoint), column = Int(point.x * Self.pixelsPerPoint)
        let offset = (row * pixelWidth + column) * 4
        return (0..<3).map { component in Int(pixelBytes[offset + component]) }
    }

    private func assertColor(_ drawnColor: [Int], _ expected: [Int], _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (drawnComponent, expectedComponent) in zip(drawnColor, expected) {
            XCTAssertEqual(drawnComponent, expectedComponent, accuracy: 6, "\(message): \(drawnColor)", file: file, line: line)
        }
    }
}
