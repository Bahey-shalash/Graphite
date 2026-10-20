import XCTest
import PDFKit
import CoreGraphics
import CoreText
import GraphiteCore
@testable import GraphiteApple

/// Text markup as it is written into a PDF: standard `/Highlight`, `/Underline` and
/// `/StrikeOut` annotations with one quadrilateral per line, corners in the order every
/// reader expects, named in `/NM` and in Graphite's own key.
final class PDFMarkupQuadPointsTests: XCTestCase {
    private func blankDocument() throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
    }

    private func writtenData(_ document: PDFDocument) throws -> Data {
        try XCTUnwrap(document.dataRepresentation())
    }

    func testEachKindIsItsStandardSubtypeWithOneQuadrilateralPerLineInReadingOrder() throws {
        let lines = [CGRect(x: 60, y: 700, width: 300, height: 24), CGRect(x: 60, y: 660, width: 180, height: 24)]
        let kindsBySubtype: [(PDFMarkupKind, String)] = [(.highlight, "Highlight"), (.underline, "Underline"), (.strikeOut, "StrikeOut")]
        for (kind, subtype) in kindsBySubtype {
            let document = try blankDocument()
            try PDFPageManager.apply(.addMarkup(page: 0, markup: PDFMarkup(name: "markup-\(subtype)", kind: kind, color: .yellow, lineBounds: lines)), to: document)
            try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try writtenData(document)) { dictionaries in
                let annotation = try XCTUnwrap(dictionaries.first)
                XCTAssertEqual(PDFAnnotationDictionaryReading.name("Subtype", in: annotation), subtype)
                let quadPoints = try XCTUnwrap(PDFAnnotationDictionaryReading.numbers("QuadPoints", in: annotation))
                // Per line: upper left, upper right, lower left, lower right, as x y pairs.
                XCTAssertEqual(quadPoints.count, 16, subtype)
                let expected: [Double] = [60, 724, 360, 724, 60, 700, 360, 700,
                                          60, 684, 240, 684, 60, 660, 240, 660]
                for (written, wanted) in zip(quadPoints, expected) { XCTAssertEqual(written, wanted, accuracy: 0.01, subtype) }
            }
        }
    }

    func testTheNameIsTheStandardNameAndRepeatedInGraphitesOwnKey() throws {
        let document = try blankDocument()
        let markup = PDFMarkup(name: "markup-name-1", kind: .highlight, color: .green, lineBounds: [CGRect(x: 60, y: 700, width: 300, height: 24)])
        try PDFPageManager.apply(.addMarkup(page: 0, markup: markup), to: document)
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try writtenData(document)) { dictionaries in
            let annotation = try XCTUnwrap(dictionaries.first)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("NM", in: annotation), "markup-name-1")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("GraphiteAnnotationName", in: annotation), "markup-name-1")
            XCTAssertEqual(PDFAnnotationDictionaryReading.integer("F", in: annotation).map { $0 & 4 }, 4, "Printable.")
        }
    }

    func testCornersFollowTheDirectionTheTextRuns() {
        let line = CGRect(x: 10, y: 20, width: 30, height: 40)
        func pairs(_ direction: PDFMarkupLineDirection) -> [[Double]] {
            PDFMarkup.quadrilateralCorners(of: line, direction: direction).map { corner in [Double(corner.x), Double(corner.y)] }
        }
        XCTAssertEqual(pairs(.leftToRight), [[10, 60], [40, 60], [10, 20], [40, 20]])
        XCTAssertEqual(pairs(.bottomToTop), [[10, 20], [10, 60], [40, 20], [40, 60]])
        XCTAssertEqual(pairs(.topToBottom), [[40, 60], [40, 20], [10, 60], [10, 20]])
    }

    /// One line of text drawn turned by `angle` about (300, 400).
    private func turnedTextDocument(angle: CGFloat) throws -> PDFDocument {
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = try XCTUnwrap(CGDataConsumer(data: output))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let attributedText = NSAttributedString(string: "Rotated lecture text", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        context.translateBy(x: 300, y: 400)
        context.rotate(by: angle)
        context.textPosition = .zero
        CTLineDraw(CTLineCreateWithAttributedString(attributedText), context)
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: output as Data))
    }

    func testVerticalTextIsMarkedWithCornersInTheOrderTheTextReads() throws {
        let cases: [(angle: CGFloat, direction: PDFMarkupLineDirection)] = [(0, .leftToRight), (.pi / 2, .bottomToTop), (-.pi / 2, .topToBottom)]
        for (angle, direction) in cases {
            let document = try turnedTextDocument(angle: angle)
            let lineRectangle = try XCTUnwrap(document.findString("lecture", withOptions: []).first?.markupLinesByPage(in: document).first?.lineBounds.first)
            let expectedCorners = PDFMarkup.quadrilateralCorners(of: lineRectangle, direction: direction).flatMap { corner in [Double(corner.x), Double(corner.y)] }
            try PDFPageManager.apply(.addMarkup(page: 0, markup: PDFMarkup(name: "turned", kind: .highlight, color: .yellow, lineBounds: [lineRectangle])), to: document)
            try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: try writtenData(document)) { dictionaries in
                let quadPoints = try XCTUnwrap(PDFAnnotationDictionaryReading.numbers("QuadPoints", in: XCTUnwrap(dictionaries.first)))
                XCTAssertEqual(quadPoints.count, 8)
                for (written, wanted) in zip(quadPoints, expectedCorners) { XCTAssertEqual(written, wanted, accuracy: 0.01, "Text turned by \(angle)") }
            }
        }
    }
}
