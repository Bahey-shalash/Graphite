import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

/// Where text boxes sit among a page's annotations: over Graphite's ink and pictures, which
/// stay under them as ink is added and pictures are placed; never touched by erasing ink; and
/// kept, drawn by Graphite, when a save rewrites the page tree.
final class PDFTextBoxPageOrderTests: XCTestCase {
    private typealias Documents = PDFTextBoxTestDocuments

    private func stroke(named name: String) -> PortableInkStroke {
        PortableInkStroke(name: name, segments: [[CGPoint(x: 20, y: 100), CGPoint(x: 120, y: 100)]], width: 2, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
    }

    private func addingStroke(_ name: String) -> PDFEdit {
        .updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [stroke(named: name)],
                                editableRecord: nil, defersEditableRecord: true))
    }

    private func names(onFirstPageOf data: Data) throws -> [String] {
        let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        return page.annotations.map { annotation in annotation.persistentName ?? "(\(annotation.type ?? "?"))" }
    }

    private func pictureData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    func testInkDrawnAfterABoxGoesUnderItAndThePicturesUnderTheInk() throws {
        let box = Documents.sampleBox(name: "box-1", link: URL(string: "https://example.com"))
        let picture = PDFPicture(name: "picture-1", imageData: try pictureData(), bounds: CGRect(x: 20, y: 150, width: 100, height: 50), quarterTurns: 0)
        let saved = try Documents.savedData(applying: [addingStroke("ink-A"), .addTextBox(page: 0, textBox: box), addingStroke("ink-B"),
                                                       .addPicture(page: 0, picture: picture), addingStroke("ink-C")])
        XCTAssertEqual(try names(onFirstPageOf: saved), ["picture-1", "ink-A", "ink-B", "ink-C", "box-1", "box-1-link-1"])
    }

    func testErasingInkNeverRemovesABox() throws {
        let box = Documents.sampleBox(name: "box-1")
        let erasingEverything = PDFEdit.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .entireGroup,
                                                               addedStrokes: [], editableRecord: nil))
        let saved = try Documents.savedData(applying: [addingStroke("ink-A"), .addTextBox(page: 0, textBox: box), erasingEverything])
        XCTAssertEqual(try names(onFirstPageOf: saved), ["box-1"])
    }

    func testABoxIsKeptAndDrawnByGraphiteWhenASaveRewritesThePageTree() throws {
        let box = Documents.sampleBox(name: "box-1", rotation: 0.3)
        let withBox = try Documents.savedData(applying: [.addTextBox(page: 0, textBox: box)])
        let insertedPage = try Documents.blankPageData()
        let rewritten = try Documents.savedData(applying: [.insert(data: insertedPage, at: 0)], to: withBox)
        let reopened = try Documents.shownDocument(from: rewritten)
        XCTAssertEqual(reopened.pageCount, 2)
        XCTAssertEqual(PDFPageManager.textBoxes(on: try XCTUnwrap(reopened.page(at: 1))), [box])
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: rewritten, pageNumber: 2) { dictionaries in
            let freeText = try XCTUnwrap(dictionaries.first)
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("DS", in: freeText), PDFTextStyleDeclarations.defaultStyleText(of: box))
            XCTAssertNotNil(PDFAnnotationDictionaryReading.string("RC", in: freeText))
            // Graphite's appearance turns the text by the box's angle; PDFKit's own would not.
            let appearance = try XCTUnwrap(PDFAnnotationDictionaryReading.normalAppearanceContent(of: freeText))
            XCTAssertTrue(appearance.contains(" cm"), appearance)
        }
    }

    func testADuplicatedPageKeepsItsBoxes() throws {
        let box = Documents.sampleBox(name: "box-1")
        let withBox = try Documents.savedData(applying: [.addTextBox(page: 0, textBox: box)])
        let duplicated = try Documents.savedData(applying: [.duplicate(page: 0)], to: withBox)
        let reopened = try Documents.shownDocument(from: duplicated)
        for pageIndex in 0..<2 {
            XCTAssertEqual(PDFPageManager.textBoxes(on: try XCTUnwrap(reopened.page(at: pageIndex))).map(\.plainText), [box.plainText])
        }
    }
}
