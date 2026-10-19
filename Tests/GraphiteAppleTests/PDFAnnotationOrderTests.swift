import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

/// The stacking order of a page's annotations in the saved file: Graphite's ink stays over
/// its pictures, and nothing of another application moves.
final class PDFAnnotationOrderTests: XCTestCase {
    private func pictureData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    private func stroke(named name: String, atHeight height: Double) -> PortableInkStroke {
        PortableInkStroke(name: name, segments: [[CGPoint(x: 20, y: height), CGPoint(x: 120, y: height)]], width: 2, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
    }

    /// A page with, in this order: Graphite's ink A and B, another application's stamp, and
    /// another application's link.
    private func pageWithInkAndForeignAnnotations() throws -> PDFDocument {
        let document = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
        let update = PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]),
                                  addedStrokes: [stroke(named: "ink-A", atHeight: 100), stroke(named: "ink-B", atHeight: 200)], editableRecord: nil)
        try PDFPageManager.apply(.updateInk(update), to: document)
        let page = try XCTUnwrap(document.page(at: 0))
        let foreignStamp = PDFAnnotation(bounds: CGRect(x: 300, y: 300, width: 40, height: 40), forType: .stamp, withProperties: nil)
        foreignStamp.setValue("foreign-stamp", forAnnotationKey: .name)
        page.addAnnotation(foreignStamp)
        let foreignLink = PDFAnnotation(bounds: CGRect(x: 300, y: 400, width: 40, height: 40), forType: .link, withProperties: nil)
        foreignLink.setValue("foreign-link", forAnnotationKey: .name)
        page.addAnnotation(foreignLink)
        return document
    }

    private func savedOrder(of document: PDFDocument, edits: [PDFEdit]) throws -> [String] {
        try PDFPageManager.replay(edits, on: document)
        let page = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation()))?.page(at: 0))
        return page.annotations.map { annotation in annotation.persistentName ?? "(\(annotation.type ?? "?"))" }
    }

    func testAPictureIsPlacedBelowTheInkAndBesideTheForeignAnnotationsInTheSavedFile() throws {
        let picture = PDFPicture(name: "picture-1", imageData: try pictureData(), bounds: CGRect(x: 20, y: 150, width: 100, height: 50), quarterTurns: 0)
        let order = try savedOrder(of: pageWithInkAndForeignAnnotations(), edits: [.addPicture(page: 0, picture: picture)])
        XCTAssertEqual(order, ["foreign-stamp", "foreign-link", "picture-1", "ink-A", "ink-B"])
    }

    func testReorderingPicturesMovesOnlyGraphitesPicturesAndInk() throws {
        let first = PDFPicture(name: "picture-1", imageData: try pictureData(), bounds: CGRect(x: 20, y: 150, width: 100, height: 50), quarterTurns: 0)
        let second = PDFPicture(name: "picture-2", imageData: try pictureData(), bounds: CGRect(x: 60, y: 160, width: 100, height: 50), quarterTurns: 0)
        let document = try pageWithInkAndForeignAnnotations()
        let edits: [PDFEdit] = [
            .addPicture(page: 0, picture: first),
            .addPicture(page: 0, picture: second),
            .replacePicture(first.reference(onPageAt: 0), with: first, order: .front),
        ]
        XCTAssertEqual(try savedOrder(of: document, edits: edits), ["foreign-stamp", "foreign-link", "picture-2", "picture-1", "ink-A", "ink-B"])
        let backEdit: [PDFEdit] = [.replacePicture(first.reference(onPageAt: 0), with: first, order: .back)]
        let reopened = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        XCTAssertEqual(try savedOrder(of: reopened, edits: backEdit), ["foreign-stamp", "foreign-link", "picture-1", "picture-2", "ink-A", "ink-B"])
    }
}
