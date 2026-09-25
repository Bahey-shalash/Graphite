import XCTest
import PDFKit
import ImageIO
import CoreGraphics
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import GraphiteCore
@testable import GraphiteApple

final class InteroperabilityTests: XCTestCase {
    func makeImage() throws -> Data {
        let output = NSMutableData()
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testPNGRemainsReadableAndCorruptMetadataFallsBack() throws {
        let ordinary = try makeImage()
        XCTAssertNil(try GraphitePNG.decode(ordinary).drawing)
        let strokes = Data([1, 2, 3, 4])
        let editable = try GraphitePNG.encode(imageData: ordinary, drawing: DrawingPayload(width: 32, height: 24, background: .white, strokes: strokes))
        XCTAssertEqual(try GraphitePNG.decode(editable).drawing?.strokes, strokes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(editable as CFData, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var corrupt = editable
        let marker = try XCTUnwrap(corrupt.range(of: Data("grPK".utf8)))
        corrupt[marker.upperBound + 4] ^= 0xff
        let decoded = try GraphitePNG.decode(corrupt)
        XCTAssertNil(decoded.drawing)
        XCTAssertTrue(decoded.metadataWasDiscarded)
        let fallback = try XCTUnwrap(CGImageSourceCreateWithData(decoded.imageData as CFData, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(fallback, 0, nil))
        let updated = try GraphitePNG.encode(imageData: editable, drawing: DrawingPayload(width: 32, height: 24, background: .white, strokes: Data([9])))
        XCTAssertEqual(try GraphitePNG.decode(updated).drawing?.strokes, Data([9]))
    }

    func testEveryPaperTemplateIsValidAndPageOperationsSurviveReopen() throws {
        for template in PaperTemplate.allCases {
            let data = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: template))
            let document = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertEqual(document.pageCount, 1)
            XCTAssertEqual(try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox).width, 595.28, accuracy: 0.1)
            XCTAssertNotNil(CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init))
        }
        let document = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(), pageCount: 3)))
        try PDFPageManager.apply(.rotate(page: 0, clockwise: true), to: document)
        try PDFPageManager.apply(.move(from: 0, to: 2), to: document)
        try PDFPageManager.apply(.duplicate(page: 1), to: document)
        try PDFPageManager.apply(.insert(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled)), at: 1), to: document)
        try PDFPageManager.apply(.delete(pages: [0]), to: document)
        let reopened = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        XCTAssertEqual(reopened.pageCount, 4)
        XCTAssertEqual(reopened.page(at: 3)?.rotation, 90)
        let exported = try XCTUnwrap(PDFDocument(data: PDFPageManager.export(pages: [1, 3], from: reopened)))
        XCTAssertEqual(exported.pageCount, 2)
        // Only the fourth page is rotated, so exporting a neighbouring page instead shows here.
        XCTAssertEqual(exported.page(at: 0)?.rotation, 0)
        XCTAssertEqual(exported.page(at: 1)?.rotation, 90)
    }

    func testStandardInkPersistsWithoutEditableMetadata() throws {
        let document = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
        let stroke = PortableInkStroke(name: nil, segments: [[CGPoint(x: 20, y: 30), CGPoint(x: 100, y: 140)]], width: 3, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        try PDFPageManager.apply(.updateInk(PDFInkUpdate(pageIndex: 0, group: "test", removal: .entireGroup, addedStrokes: [stroke], editableRecord: nil)), to: document)
        let reopened = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        let annotation = try XCTUnwrap(reopened.page(at: 0)?.annotations.first)
        XCTAssertEqual(annotation.type, "Ink")
        XCTAssertEqual(annotation.paths?.count, 1)
        XCTAssertNil(annotation.value(forAnnotationKey: PDFPageManager.drawingKey))
        XCTAssertTrue(annotation.shouldDisplay)
        XCTAssertTrue(annotation.shouldPrint)
        XCTAssertEqual(annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String, "test")
    }

    /// Ink the pixel eraser split in two must stay two pieces, never bridged by a line.
    func testErasedGapInPortableInkIsNotBridged() throws {
        let document = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))))
        let firstPiece = [CGPoint(x: 20, y: 400), CGPoint(x: 120, y: 400)]
        let secondPiece = [CGPoint(x: 300, y: 400), CGPoint(x: 400, y: 400)]
        let stroke = PortableInkStroke(name: nil, segments: [firstPiece, secondPiece], width: 4, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        try PDFPageManager.apply(.updateInk(PDFInkUpdate(pageIndex: 0, group: "gap", removal: .entireGroup, addedStrokes: [stroke], editableRecord: nil)), to: document)
        let reopened = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        let page = try XCTUnwrap(reopened.page(at: 0))
        let annotation = try XCTUnwrap(page.annotations.first)
        // PDF readers that redraw ink from its /InkList must also see two separate pieces.
        XCTAssertEqual(annotation.paths?.count, 2)
        // Independent check: render the page and look for ink in the erased gap.
        let image = page.thumbnail(of: CGSize(width: 595, height: 842), for: .cropBox)
        XCTAssertFalse(try Self.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 210, y: 400), pageHeight: 842), "The erased gap must stay empty.")
        XCTAssertTrue(try Self.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 70, y: 400), pageHeight: 842))
        XCTAssertTrue(try Self.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 350, y: 400), pageHeight: 842), "The second piece must survive saving.")
    }

    #if canImport(UIKit)
    static func hasDarkPixel(in image: UIImage, pdfPoint: CGPoint, pageHeight: CGFloat) throws -> Bool {
        try hasDarkPixel(in: XCTUnwrap(image.cgImage), pdfPoint: pdfPoint, pageHeight: pageHeight)
    }
    #else
    static func hasDarkPixel(in image: NSImage, pdfPoint: CGPoint, pageHeight: CGFloat) throws -> Bool {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return try hasDarkPixel(in: XCTUnwrap(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)), pdfPoint: pdfPoint, pageHeight: pageHeight)
    }
    #endif

    /// Samples a 5×5 neighbourhood; PDF y grows upward, image rows grow downward.
    static func hasDarkPixel(in image: CGImage, pdfPoint: CGPoint, pageHeight: CGFloat) throws -> Bool {
        let width = image.width, height = image.height
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let scale = CGFloat(height) / pageHeight
        let centerColumn = Int(pdfPoint.x * scale), centerRow = Int((pageHeight - pdfPoint.y) * scale)
        for row in max(0, centerRow - 2)...min(height - 1, centerRow + 2) {
            for column in max(0, centerColumn - 2)...min(width - 1, centerColumn + 2) {
                let offset = row * width * 4 + column * 4
                if pixels[offset] < 100 && pixels[offset + 3] > 200 { return true }
            }
        }
        return false
    }
}
