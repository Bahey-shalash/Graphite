import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple
import GraphiteTestSupport

/// A save that moves or deletes pages makes PDFKit rewrite the page tree. The written file
/// must still hold every Graphite key (read here with CoreGraphics, not PDFKit), a backup of
/// each standard `/NM` name, and outline and link destinations on the pages they named.
final class PDFPageTreeRewriteKeepsGraphiteKeysTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "PDFPageTreeRewrite", for: self).root
    }

    // MARK: Fixture

    private func handWrittenPDF(objects: [String]) -> Data {
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
        return Data(text.utf8)
    }

    /// Three pages. Page 1 has a link to page 3. Page 2 has a stroke carrying the ink keys, a picture carrying the
    /// picture keys, and another application's highlight named only by `/NM`. The outline has "Part" (page 1) with
    /// the child "Section" (page 2), and "Chapter" (page 3).
    private func notebookData() -> Data {
        let drawingRecord = Data([1, 2, 3, 4]).base64EncodedString()
        let picture = "base64:" + Data("picture bytes".utf8).base64EncodedString()
        return handWrittenPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R /Outlines 6 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Annots [9 0 R] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Annots [10 0 R 11 0 R 12 0 R] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] >>",
            "<< /Type /Outlines /First 7 0 R /Last 13 0 R /Count 3 >>",
            "<< /Title (Part) /Parent 6 0 R /Next 13 0 R /First 8 0 R /Last 8 0 R /Count 1 /Dest [3 0 R /Fit] >>",
            "<< /Title (Section) /Parent 7 0 R /Dest [4 0 R /Fit] >>",
            "<< /Type /Annot /Subtype /Link /Rect [10 10 100 40] /Border [0 0 0] /Dest [5 0 R /Fit] >>",
            "<< /Type /Annot /Subtype /Ink /Rect [10 10 110 60] /InkList [[1 1 99 1]] /C [0 0 0] /F 4 /NM (stroke-a) "
                + "/GraphiteAnnotationName (stroke-a) /GraphiteInkGroup (GraphitePageInkV1) /GraphitePencilDrawingV1 (\(drawingRecord)) "
                + "/GraphiteInkStrokeNamesV1 (1:stroke-a) >>",
            "<< /Type /Annot /Subtype /Stamp /Rect [145 275 195 375] /F 4 /NM (picture-a) /GraphiteAnnotationName (picture-a) "
                + "/GraphitePictureV1 (\(picture)) /GraphitePictureV2 (\(picture)) /GraphitePictureTurns 1 /GraphitePictureRotation 1.5 "
                + "/GraphitePictureWidth 100 /GraphitePictureHeight 50 >>",
            "<< /Type /Annot /Subtype /Highlight /Rect [50 100 150 120] /NM (foreign-1) /C [1 0.5 0] /QuadPoints [50 120 150 120 50 100 150 100] >>",
            "<< /Title (Chapter) /Parent 6 0 R /Prev 7 0 R /Dest [5 0 R /Fit] >>",
        ])
    }

    private func save(_ edits: [PDFEdit]) async throws -> Data {
        let location = directory.appendingPathComponent("Notebook-\(UUID().uuidString).pdf")
        try notebookData().write(to: location)
        let baseline = directory.appendingPathComponent("baseline-\(UUID().uuidString).pdf")
        try FileManager.default.copyItem(at: location, to: baseline)
        _ = try await PDFFileService().save(url: location, revision: FileRevision.read(location), edits: edits, baselineURL: baseline)
        return try Data(contentsOf: location)
    }

    private func outlineSummary(_ document: PDFDocument) -> [String] {
        guard let root = document.outlineRoot else { return [] }
        var summary: [String] = []
        func visit(_ item: PDFOutline, depth: Int) {
            let pageIndex = item.destination?.page.map(document.index(for:))
            summary.append("\(String(repeating: ">", count: depth))\(item.label ?? "")->\(pageIndex.map(String.init) ?? "none")")
            for childIndex in 0..<item.numberOfChildren { if let child = item.child(at: childIndex) { visit(child, depth: depth + 1) } }
        }
        for childIndex in 0..<root.numberOfChildren { if let child = root.child(at: childIndex) { visit(child, depth: 0) } }
        return summary
    }

    // MARK: Keys

    /// The keys of page 2's annotations read as another reader reads them.
    private func assertGraphiteKeys(onPageNumber pageNumber: Int, in fileData: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: fileData, pageNumber: pageNumber) { dictionaries in
            func dictionary(subtype: String) -> CGPDFDictionaryRef? {
                dictionaries.first { PDFAnnotationDictionaryReading.name("Subtype", in: $0) == subtype }
            }
            guard let ink = dictionary(subtype: "Ink"), let picture = dictionary(subtype: "Stamp"), let highlight = dictionary(subtype: "Highlight") else {
                return XCTFail("The page lost an annotation.", file: file, line: line)
            }
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphiteInkGroup", in: ink), "GraphitePageInkV1", file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphiteInkStrokeNamesV1", in: ink), "1:stroke-a", file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphitePencilDrawingV1", in: ink), Data([1, 2, 3, 4]).base64EncodedString(), file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphiteAnnotationName", in: ink), "stroke-a", file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphiteAnnotationName", in: picture), "picture-a", file: file, line: line)
            let pictureText = "base64:" + Data("picture bytes".utf8).base64EncodedString()
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphitePictureV1", in: picture), pictureText, file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphitePictureV2", in: picture), pictureText, file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.number("GraphitePictureTurns", in: picture), 1, file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.number("GraphitePictureRotation", in: picture) ?? 0, 1.5, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.number("GraphitePictureWidth", in: picture), 100, file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.number("GraphitePictureHeight", in: picture), 50, file: file, line: line)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphiteAnnotationName", in: highlight), "foreign-1",
                           "Another application's markup gets its `/NM` name backed up, so edits that name it find it.", file: file, line: line)
        }
    }

    func testMovingAPageKeepsEveryGraphiteKeyAndBacksUpTheStandardName() async throws {
        let written = try await save([.move(from: 0, to: 2)])
        // The page with the annotations was page 2; it is the first page now.
        try assertGraphiteKeys(onPageNumber: 1, in: written)
    }

    func testDeletingAPageKeepsEveryGraphiteKeyOnTheRemainingPages() async throws {
        let written = try await save([.delete(pages: [2])])
        try assertGraphiteKeys(onPageNumber: 2, in: written)
    }

    func testInsertingAPageKeepsEveryGraphiteKeyOnThePagesAfterIt() async throws {
        let blankPage = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))
        let written = try await save([.insert(data: blankPage, at: 0)])
        try assertGraphiteKeys(onPageNumber: 3, in: written)
    }

    // MARK: Destinations

    func testMovingAPageKeepsOutlineEntriesAndLinksOnTheirPages() async throws {
        let written = try await save([.move(from: 0, to: 2)])
        let document = try XCTUnwrap(PDFDocument(data: written))
        // Old pages 1, 2, 3 are now 2, 0, 1.
        XCTAssertEqual(outlineSummary(document), ["Part->2", ">Section->0", "Chapter->1"])
        let link = try XCTUnwrap(document.page(at: 2)?.annotations.first { $0.type == "Link" })
        XCTAssertEqual((link.destination ?? (link.action as? PDFActionGoTo)?.destination)?.page.map(document.index(for:)), 1,
                       "The link moved with its page and still opens the old page 3.")
    }

    func testDeletingAPageRemovesItsEntriesButAnEntryWithChildrenKeepsThemAndLosesOnlyItsDestination() async throws {
        let written = try await save([.delete(pages: [0])])
        let document = try XCTUnwrap(PDFDocument(data: written))
        XCTAssertEqual(outlineSummary(document), ["Part->none", ">Section->0", "Chapter->1"])
        XCTAssertEqual(document.pageCount, 2)

        let writtenAfterDeletingASectionPage = try await save([.delete(pages: [1])])
        let sectionless = try XCTUnwrap(PDFDocument(data: writtenAfterDeletingASectionPage))
        XCTAssertEqual(outlineSummary(sectionless), ["Part->0", "Chapter->1"], "A childless entry of a deleted page is removed.")
    }

    func testDeletingTheLinkedPageLeavesTheLinkOpeningNothing() async throws {
        let written = try await save([.delete(pages: [2])])
        let document = try XCTUnwrap(PDFDocument(data: written))
        let link = try XCTUnwrap(document.page(at: 0)?.annotations.first { $0.type == "Link" })
        XCTAssertNil((link.destination ?? (link.action as? PDFActionGoTo)?.destination)?.page, "A link to a deleted page opens nothing, not page 1.")
        XCTAssertEqual(outlineSummary(document), ["Part->0", ">Section->1"], "Chapter went with its page.")
    }
}
