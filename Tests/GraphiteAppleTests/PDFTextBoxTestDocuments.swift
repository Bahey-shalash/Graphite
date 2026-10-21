import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple
import GraphiteFixtures

/// Documents and boxes the text box tests share.
enum PDFTextBoxTestDocuments {
    static let pageSize = CGSize(width: 400, height: 600)
    static let samplesFolder = FixtureFolders.repositoryRoot.appendingPathComponent("Tests/Fixtures/PDFTextBoxes", isDirectory: true)

    /// A one-page PDF with no annotations, written by Core Graphics.
    static func blankPageData(pageCount: Int = 1) throws -> Data {
        let pageData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let consumer = try XCTUnwrap(CGDataConsumer(data: pageData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return pageData as Data
    }

    /// A document that will be written, as saving makes it.
    static func writtenDocument(from data: Data) throws -> PDFDocument {
        let document = try XCTUnwrap(PDFDocument(data: data))
        PDFPageManager.prepareForWriting(document)
        return document
    }

    /// A document that is shown, as a PDF pane opens it.
    static func shownDocument(from data: Data) throws -> PDFDocument {
        let document = try XCTUnwrap(PDFDocument(data: data))
        PDFPageManager.prepareForDisplay(document)
        return document
    }

    /// The edits replayed on a blank page as saving replays them, and the bytes written, with
    /// the author PDFKit writes set to a sample name rather than this Mac's user.
    static func writtenData(applying edits: [PDFEdit], to data: Data? = nil) throws -> Data {
        let document = try writtenDocument(from: data ?? blankPageData())
        try PDFPageManager.replay(edits, on: document)
        for pageIndex in 0..<document.pageCount {
            for annotation in document.page(at: pageIndex)?.annotations ?? [] { annotation.userName = "Sample author" }
        }
        return try XCTUnwrap(document.dataRepresentation())
    }

    /// The file as saving leaves it: written, then compacted.
    static func savedData(applying edits: [PDFEdit], to data: Data? = nil) throws -> Data {
        let written = try writtenData(applying: edits, to: data)
        return PDFObjectCompaction.compacted(written)?.data ?? written
    }

    /// A color of whole 8-bit components, as `/RC` and `/DS` write colors.
    static let georgia = PDFTextAttributes(fontFamily: "Georgia", fontSize: 18, color: PDFTextColor(red: 26.0 / 255, green: 51.0 / 255, blue: 179.0 / 255))

    /// A box of two looks over two lines, with a fill and a border.
    static func sampleBox(name: String = "sample-box", rotation: Double = 0, link: URL? = nil) -> PDFTextBox {
        var bold = PDFTextAttributes.plain
        bold.isBold = true
        var linked = georgia
        linked.link = link
        let box = PDFTextBox(name: name, runs: [PDFTextRun(text: "Typed text, ", attributes: .plain), PDFTextRun(text: "bold", attributes: bold),
                                                PDFTextRun(text: "\nand a second line", attributes: linked)],
                             origin: CGPoint(x: 60, y: 500), width: 240, height: 10, rotationRadians: rotation,
                             style: PDFTextBoxStyle(alignment: .left, lineSpacing: 1.1, fillColor: PDFTextColor(red: 1, green: 1, blue: 0.8),
                                                    borderColor: PDFTextColor(red: 0.5, green: 0, blue: 0), borderWidth: 1, padding: 5))
        return PDFTextBoxLayout.fitted(box)
    }
}
