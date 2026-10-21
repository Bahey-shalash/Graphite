import XCTest
import CoreGraphics
import PDFKit
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

/// Graphite's own writer of ink annotations (`PDFInkAnnotationObjects`, `PDFAnnotationAppending`, BUG-IMPORT-03): the
/// same strokes written through PDFKit's annotation writer and through Graphite's read back as the same annotations,
/// draw the same, keep the page's other annotations in their order, and a file not in PDFKit's form is refused.
final class PDFAnnotationAppendingTests: XCTestCase {
    private static let pageSize = CGSize(width: 400, height: 500)
    private static let group = PDFInkGroups.defaultGroup

    private var strokes: [PortableInkStroke] {
        [
            PortableInkStroke(name: "stroke-1", segments: [[CGPoint(x: 40, y: 60), CGPoint(x: 120, y: 90), CGPoint(x: 200, y: 70)]], width: 3,
                              red: 0.1, green: 0.2, blue: 0.7, alpha: 1,
                              outline: [[CGPoint(x: 38, y: 58), CGPoint(x: 122, y: 87), CGPoint(x: 202, y: 68), CGPoint(x: 200, y: 73),
                                         CGPoint(x: 120, y: 94), CGPoint(x: 39, y: 63)]]),
            PortableInkStroke(name: "stroke-2", segments: [[CGPoint(x: 60, y: 300), CGPoint(x: 300, y: 300)]], width: 18, red: 1, green: 0.85, blue: 0,
                              alpha: 0.5, outline: [[CGPoint(x: 60, y: 291), CGPoint(x: 300, y: 291), CGPoint(x: 300, y: 309), CGPoint(x: 60, y: 309)]]),
            PortableInkStroke(name: "stroke-3", segments: [[CGPoint(x: 250, y: 400)]], width: 2, red: 0, green: 0, blue: 0, alpha: 1, outline: nil),
        ]
    }

    private var update: PDFInkUpdate {
        PDFInkUpdate(pageIndex: 0, group: Self.group, removal: .strokes([]), addedStrokes: strokes,
                     editableRecord: PDFEditableInkRecord(drawingData: Data("drawing".utf8), strokeNames: ["stroke-1", "stroke-2", "stroke-3"]))
    }

    /// A one-page document with a Graphite picture and a text box on its page, as the import makes before its ink.
    private func documentWithPictureAndTextBox() throws -> PDFDocument {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let page = try XCTUnwrap(document.page(at: 0))
        page.setBounds(CGRect(origin: .zero, size: Self.pageSize), for: .mediaBox)
        let stamp = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 30, height: 30), forType: .stamp, withProperties: nil)
        page.addAnnotation(stamp)
        let box = PDFTextBox(runs: [PDFTextRun(text: "Over the ink", attributes: .plain)], origin: CGPoint(x: 50, y: 450), width: 200, height: 30)
        try PDFPageManager.apply(.addTextBox(page: 0, textBox: box), to: document, drawsInkOutlines: true)
        return document
    }

    private func writtenThroughPDFKit(in vault: TemporaryVault) throws -> URL {
        let document = try documentWithPictureAndTextBox()
        try PDFPageManager.apply(.updateInk(update), to: document, drawsInkOutlines: true)
        let location = vault.location(of: "pdfkit.pdf")
        XCTAssertTrue(PDFFileService.write(document, to: location))
        return location
    }

    private func writtenThroughGraphite(in vault: TemporaryVault) throws -> URL {
        let document = try documentWithPictureAndTextBox()
        let pages = vault.location(of: "pages.pdf"), spoolLocation = vault.location(of: "ink.spool"), location = vault.location(of: "graphite.pdf")
        XCTAssertTrue(PDFFileService.write(document, to: pages))
        var spool = try PDFObjectSpool(location: spoolLocation)
        var objects = PDFInkAnnotationObjects()
        let places = try objects.spool(update, into: &spool)
        try spool.finish()
        try PDFAnnotationAppending.write(source: pages, spool: spoolLocation, spooledObjectCount: spool.objectCount,
                                         annotationPlacesByPageIndex: [0: places], to: location)
        return location
    }

    func testTheSameStrokesReadBackAsTheSameAnnotationsAndRecord() throws {
        let vault = try TemporaryVault.make(prefix: "PDFAnnotationAppending", for: self)
        let throughPDFKit = try XCTUnwrap(PDFDocument(url: writtenThroughPDFKit(in: vault))?.page(at: 0))
        let throughGraphite = try XCTUnwrap(PDFDocument(url: writtenThroughGraphite(in: vault))?.page(at: 0))
        XCTAssertEqual(throughGraphite.annotations.map(\.type), throughPDFKit.annotations.map(\.type))
        XCTAssertEqual(throughGraphite.annotations.map(\.type), ["Stamp", "Ink", "Ink", "Ink", "FreeText"], "picture, ink, then the text box (M-15)")
        let pdfKitInk = throughPDFKit.annotations.filter { annotation in annotation.type == "Ink" }
        let graphiteInk = throughGraphite.annotations.filter { annotation in annotation.type == "Ink" }
        for (expected, written) in zip(pdfKitInk, graphiteInk) {
            XCTAssertEqual(written.persistentName, expected.persistentName)
            XCTAssertEqual(written.value(forAnnotationKey: PDFPageManager.groupKey) as? String, Self.group)
            XCTAssertEqual(written.border?.lineWidth ?? 0, expected.border?.lineWidth ?? 0, accuracy: 1e-4)
            XCTAssertEqual(written.shouldPrint, expected.shouldPrint)
            XCTAssertEqual(written.userName, expected.userName)
            Self.assertEqualColors(written.color.cgColor, expected.color.cgColor)
            XCTAssertEqual(written.bounds.minY, expected.bounds.minY, accuracy: 0.01)
            XCTAssertEqual(written.bounds.height, expected.bounds.height, accuracy: 0.01)
            let writtenPoints = (written.paths ?? []).map(Self.points(of:)), expectedPoints = (expected.paths ?? []).map(Self.points(of:))
            XCTAssertEqual(writtenPoints.count, expectedPoints.count)
            for (writtenPath, expectedPath) in zip(writtenPoints, expectedPoints) {
                XCTAssertEqual(writtenPath.count, expectedPath.count)
                for (writtenPoint, expectedPoint) in zip(writtenPath, expectedPath) {
                    XCTAssertEqual(writtenPoint.x + written.bounds.minX, expectedPoint.x + expected.bounds.minX, accuracy: 0.01)
                    XCTAssertEqual(writtenPoint.y + written.bounds.minY, expectedPoint.y + expected.bounds.minY, accuracy: 0.01)
                }
            }
        }
        XCTAssertEqual(PDFInkGroups.editableGroup(on: throughGraphite), PDFInkGroups.editableGroup(on: throughPDFKit),
                       "the same re-editing record on the group's first annotation")
        XCTAssertEqual(PDFPageManager.textBoxes(on: throughGraphite).map(\.plainText), ["Over the ink"])
    }

    func testThePagesDrawTheSame() throws {
        let vault = try TemporaryVault.make(prefix: "PDFAnnotationAppendingDrawing", for: self)
        let throughPDFKit = try XCTUnwrap(PDFDocument(url: writtenThroughPDFKit(in: vault))?.page(at: 0))
        let throughGraphite = try XCTUnwrap(PDFDocument(url: writtenThroughGraphite(in: vault))?.page(at: 0))
        let expected = try Self.rendered(throughPDFKit), written = try Self.rendered(throughGraphite)
        var differing = 0, content = 0
        for index in expected.indices where expected[index] < 250 || written[index] < 250 {
            content += 1
            if abs(Int(expected[index]) - Int(written[index])) > 24 { differing += 1 }
        }
        XCTAssertGreaterThan(content, 1_000)
        XCTAssertLessThanOrEqual(Double(differing) / Double(content), 0.01, "\(differing) of \(content) content pixels differ")
    }

    func testAPageWithoutAnnotationsGetsThemAndAFileNotInPDFKitsFormIsRefused() throws {
        let vault = try TemporaryVault.make(prefix: "PDFAnnotationAppendingForms", for: self)
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let pages = vault.location(of: "pages.pdf"), spoolLocation = vault.location(of: "ink.spool"), location = vault.location(of: "written.pdf")
        XCTAssertTrue(PDFFileService.write(document, to: pages))
        var spool = try PDFObjectSpool(location: spoolLocation)
        var objects = PDFInkAnnotationObjects()
        let places = try objects.spool(update, into: &spool)
        try spool.finish()
        try PDFAnnotationAppending.write(source: pages, spool: spoolLocation, spooledObjectCount: spool.objectCount,
                                         annotationPlacesByPageIndex: [0: places], to: location)
        XCTAssertEqual(PDFDocument(url: location)?.page(at: 0)?.annotations.count, 3)
        // An incremental update appended to the file: not the form PDFKit writes.
        var updated = try Data(contentsOf: pages)
        updated.append(Data("\nxref\n0 1\n0000000000 65535 f\r\ntrailer\n<< /Size 1 /Prev 9 >>\nstartxref\n\(updated.count + 1)\n%%EOF\n".utf8))
        let incremental = vault.location(of: "incremental.pdf")
        try updated.write(to: incremental)
        XCTAssertThrowsError(try PDFAnnotationAppending.write(source: incremental, spool: spoolLocation, spooledObjectCount: spool.objectCount,
                                                              annotationPlacesByPageIndex: [0: places], to: vault.location(of: "refused.pdf"))) { error in
            XCTAssertEqual(error as? PDFAnnotationAppending.AppendingError, .sourceNotUnderstood)
        }
    }

    func testNumbersAndStringsAreWrittenAsPDFKitWritesThem() {
        XCTAssertEqual(PDFObjectText.number(627.68044), "627.6804")
        XCTAssertEqual(PDFObjectText.number(1.5590551), "1.559055")
        XCTAssertEqual(PDFObjectText.number(0.21176471), "0.2117647")
        XCTAssertEqual(PDFObjectText.number(13.0909091), "13.09091")
        XCTAssertEqual(PDFObjectText.number(2), "2")
        XCTAssertEqual(PDFObjectText.number(-0.0000001), "0")
        XCTAssertEqual(PDFObjectText.number(.nan), "0")
        XCTAssertEqual(String(decoding: PDFObjectText.textString("a(b)\\c"), as: UTF8.self), "(a\\(b\\)\\\\c)")
        XCTAssertEqual(String(decoding: PDFObjectText.textString("Zoë"), as: UTF8.self), "<FEFF005A006F00EB>")
        XCTAssertEqual(PDFObjectText.dateText(Date(timeIntervalSince1970: 0)), "D:19700101000000Z00'00'")
    }

    private static func points(of path: Any) -> [CGPoint] {
        #if canImport(UIKit)
        guard let path = path as? UIBezierPath else { return [] }
        var points: [CGPoint] = []
        path.cgPath.applyWithBlock { element in
            if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint { points.append(element.pointee.points[0]) }
        }
        return points
        #else
        guard let path = path as? NSBezierPath else { return [] }
        var points: [CGPoint] = []
        var associated = [CGPoint](repeating: .zero, count: 3)
        for index in 0..<path.elementCount {
            let kind = path.element(at: index, associatedPoints: &associated)
            if kind == .moveTo || kind == .lineTo { points.append(associated[0]) }
        }
        return points
        #endif
    }

    private static func assertEqualColors(_ first: CGColor, _ second: CGColor, file: StaticString = #filePath, line: UInt = #line) {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let firstComponents = first.converted(to: space, intent: .defaultIntent, options: nil)?.components ?? []
        let secondComponents = second.converted(to: space, intent: .defaultIntent, options: nil)?.components ?? []
        XCTAssertEqual(firstComponents.count, secondComponents.count, file: file, line: line)
        for (firstComponent, secondComponent) in zip(firstComponents, secondComponents) {
            XCTAssertEqual(Double(firstComponent), Double(secondComponent), accuracy: 0.002, file: file, line: line)
        }
    }

    /// The page drawn in grey on white at two pixels per point.
    private static func rendered(_ page: PDFPage) throws -> [UInt8] {
        let width = Int(pageSize.width) * 2, height = Int(pageSize.height) * 2
        var pixels = [UInt8](repeating: 255, count: width * height)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: 2, y: 2)
            page.draw(with: .mediaBox, to: context)
        }
        return pixels
    }
}
