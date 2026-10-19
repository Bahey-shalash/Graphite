import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A bookmark is a top-level outline item labelled "Page " plus the page's label (or its
/// number), with its destination at the top-left corner of the page as it is shown.
@MainActor
final class PDFSessionBookmarkTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "PDFSessionBookmark", for: self).root
    }

    /// Four pages of 600 × 800 points turned 0°, 90°, 180° and 270°, with or without roman page labels.
    private func makePDF(named filename: String, hasRomanPageLabels: Bool) throws -> URL {
        let labels = hasRomanPageLabels ? " /PageLabels << /Nums [0 << /S /r >>] >>" : ""
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R\(labels) >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R 6 0 R] /Count 4 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Rotate 0 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Rotate 90 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Rotate 180 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Rotate 270 >>",
        ]
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        let location = directory.appendingPathComponent(filename)
        try Data(text.utf8).write(to: location)
        return location
    }

    private func savedBookmarks(at location: URL) throws -> [(label: String, pageIndex: Int, point: CGPoint)] {
        let document = try XCTUnwrap(PDFDocument(url: location))
        let root = try XCTUnwrap(document.outlineRoot)
        return try (0..<root.numberOfChildren).map { childIndex in
            let item = try XCTUnwrap(root.child(at: childIndex))
            let destination = try XCTUnwrap(item.destination)
            return (item.label ?? "", document.index(for: try XCTUnwrap(destination.page)), destination.point)
        }
    }

    func testBookmarksCarryThePageNumberWhenThePDFHasNoPageLabels() async throws {
        let location = try makePDF(named: "Plain.pdf", hasRomanPageLabels: false)
        let session = try await PDFSession.open(location)
        XCTAssertEqual(PDFOutlineEntry.bookmarkLabelPrefix, "Page ")
        try session.addBookmark(pageIndex: 2)
        try session.addBookmark(pageIndex: 0)
        try await session.save()
        XCTAssertEqual(try savedBookmarks(at: location).map(\.label), ["Page 3", "Page 1"])
        XCTAssertEqual(session.bookmarkedPageIndices, [0, 2])
        XCTAssertEqual(session.outlineEntries.map(\.isBookmark), [true, true])
    }

    func testBookmarksCarryThePageLabelWhenThePDFHasPageLabels() async throws {
        let location = try makePDF(named: "Roman.pdf", hasRomanPageLabels: true)
        let session = try await PDFSession.open(location)
        XCTAssertEqual(session.document.page(at: 2)?.label, "iii")
        try session.addBookmark(pageIndex: 2)
        try session.addBookmark(pageIndex: 3)
        try await session.save()
        XCTAssertEqual(try savedBookmarks(at: location).map(\.label), ["Page iii", "Page iv"])
        XCTAssertEqual(session.bookmarkedPageIndices, [2, 3])
    }

    func testTheWrittenDestinationIsTheTopLeftCornerOfThePageAsShown() async throws {
        let location = try makePDF(named: "Turned.pdf", hasRomanPageLabels: false)
        let session = try await PDFSession.open(location)
        for pageIndex in 0..<4 { try session.addBookmark(pageIndex: pageIndex) }
        try await session.save()

        let bookmarks = try savedBookmarks(at: location)
        XCTAssertEqual(bookmarks.map(\.pageIndex), [0, 1, 2, 3])
        // In the page's own space, where the corner shown at the top left is for each turn.
        let expectedPoints = [CGPoint(x: 0, y: 800), CGPoint(x: 0, y: 0), CGPoint(x: 600, y: 0), CGPoint(x: 600, y: 800)]
        for (bookmark, expectedPoint) in zip(bookmarks, expectedPoints) {
            XCTAssertEqual(bookmark.point.x, expectedPoint.x, accuracy: 0.01, bookmark.label)
            XCTAssertEqual(bookmark.point.y, expectedPoint.y, accuracy: 0.01, bookmark.label)
        }
    }

    func testABookmarkOfAnUnknownPageIsIgnored() async throws {
        let session = try await PDFSession.open(makePDF(named: "Plain.pdf", hasRomanPageLabels: false))
        try session.addBookmark(pageIndex: 9)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertTrue(session.outlineEntries.isEmpty)
    }
}
