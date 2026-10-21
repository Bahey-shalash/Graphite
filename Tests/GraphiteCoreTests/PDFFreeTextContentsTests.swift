import XCTest
import CoreGraphics
@testable import GraphiteCore

/// The text of a PDF's text boxes, as Search reads it: every `/FreeText`'s `/Contents`, and
/// nothing else of the file.
final class PDFFreeTextContentsTests: XCTestCase {
    /// A PDF of one page per list of annotation dictionaries, written by hand so the test
    /// depends on no PDF writer.
    private func pdfData(pages: [[String]]) throws -> Data {
        var objects = ["<< /Type /Catalog /Pages 2 0 R >>", ""]
        var pageNumbers: [Int] = []
        for annotations in pages {
            let firstAnnotationNumber = objects.count + 2
            let references = annotations.indices.map { annotationIndex in "\(firstAnnotationNumber + annotationIndex) 0 R" }.joined(separator: " ")
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Annots [\(references)] >>")
            pageNumbers.append(objects.count)
            objects.append(contentsOf: annotations)
        }
        objects[1] = "<< /Type /Pages /Kids [\(pageNumbers.map { number in "\(number) 0 R" }.joined(separator: " "))] /Count \(pages.count) >>"
        var file = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(file.utf8.count)
            file += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = file.utf8.count
        file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { file += String(format: "%010d 00000 n \n", offset) }
        file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        return Data(file.utf8)
    }

    private func document(_ data: Data) throws -> CGPDFDocument {
        try XCTUnwrap(CGPDFDocument(XCTUnwrap(CGDataProvider(data: data as CFData))))
    }

    func testTheTextOfEveryTextBoxIsReadInPageOrderAndNothingElse() throws {
        let data = try pdfData(pages: [
            ["<< /Type /Annot /Subtype /FreeText /Rect [0 0 50 20] /Contents (First box) >>",
             "<< /Type /Annot /Subtype /Text /Rect [0 0 10 10] /Contents (A sticky note) >>",
             "<< /Type /Annot /Subtype /Highlight /Rect [0 0 10 10] /Contents (A comment) >>"],
            ["<< /Type /Annot /Subtype /FreeText /Rect [0 0 50 20] /Contents (Second\\rline) >>",
             "<< /Type /Annot /Subtype /FreeText /Rect [0 0 50 20] /Contents (   ) >>",
             "<< /Type /Annot /Subtype /FreeText /Rect [0 0 50 20] /Contents <FEFF00C9006C00E8007600650020> >>"],
        ])
        XCTAssertEqual(PDFFreeTextContents.searchableText(of: try document(data)), "First box\nSecond\nline\nÉlève\n")
    }

    func testAPDFWithoutTextBoxesHasNoText() throws {
        let data = try pdfData(pages: [["<< /Type /Annot /Subtype /Ink /Rect [0 0 10 10] /InkList [[0 0 5 5]] >>"], []])
        XCTAssertEqual(PDFFreeTextContents.searchableText(of: try document(data)), "")
    }

    func testTextPastTheLimitIsNotRead() throws {
        let long = String(repeating: "a", count: PDFFreeTextContents.maximumUTF16Count / 2)
        let box = "<< /Type /Annot /Subtype /FreeText /Rect [0 0 50 20] /Contents (\(long)) >>"
        let text = PDFFreeTextContents.searchableText(of: try document(try pdfData(pages: [[box, box, box]])))
        XCTAssertLessThanOrEqual(text.utf16.count, PDFFreeTextContents.maximumUTF16Count)
        XCTAssertEqual(text.utf16.count, long.utf16.count + 1)
    }
}
