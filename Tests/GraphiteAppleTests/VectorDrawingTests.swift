import XCTest
import PDFKit
import ImageIO
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

final class VectorDrawingTests: XCTestCase {
    private let black = VectorInkColor(red: 0, green: 0, blue: 0, alpha: 1)

    private func makeDrawing(background: DrawingBackground = .white) -> VectorDrawing {
        let horizontalStroke = (0...100).map { step in VectorStrokeSample(point: CGPoint(x: 20 + Double(step) * 2, y: 50), width: 6) }
        let dot = [VectorStrokeSample(point: CGPoint(x: 300, y: 120), width: 10)]
        let highlighter = VectorInkColor(red: 1, green: 0.8, blue: 0, alpha: 0.4)
        return VectorDrawing(size: CGSize(width: 400, height: 200), background: background, shapes: [
            StrokeOutliner.shape(forSegments: [horizontalStroke], color: black),
            StrokeOutliner.shape(forSegments: [dot], color: highlighter),
        ].compactMap { shape in shape })
    }

    private let payload = DrawingPayload(width: 400, height: 200, background: .white, strokes: Data("pencil strokes".utf8))

    // MARK: Outlines

    func testStraightStrokeOutlineCoversItsInkArea() throws {
        let samples = (0...100).map { step in VectorStrokeSample(point: CGPoint(x: Double(step), y: 0), width: 4) }
        let outline = try XCTUnwrap(StrokeOutliner.subpaths(forSamples: samples).first)
        let expectedArea = 100 * 4 + Double.pi * 2 * 2
        XCTAssertEqual(abs(StrokeOutliner.signedArea(outline)), expectedArea, accuracy: expectedArea * 0.03)
        XCTAssertLessThan(outline.count, 60, "Straight sides should simplify to a few points.")
    }

    func testSinglePointBecomesADot() {
        let subpaths = StrokeOutliner.subpaths(forSamples: [VectorStrokeSample(point: CGPoint(x: 5, y: 5), width: 8)])
        guard subpaths.count == 1 else { return XCTFail("Expected one dot, found \(subpaths.count) subpaths") }
        XCTAssertEqual(abs(StrokeOutliner.signedArea(subpaths[0])), Double.pi * 16, accuracy: 1.5)
    }

    func testHairpinTurnGetsARoundJoinWithTheSameOrientation() throws {
        let outward = (0...20).map { step in VectorStrokeSample(point: CGPoint(x: Double(step), y: 0), width: 6) }
        let back = (0...20).map { step in VectorStrokeSample(point: CGPoint(x: 20 - Double(step), y: 0.5), width: 6) }
        let subpaths = StrokeOutliner.subpaths(forSamples: outward + back)
        XCTAssertGreaterThan(subpaths.count, 1)
        let outlineSign = StrokeOutliner.signedArea(try XCTUnwrap(subpaths.first)).sign
        for join in subpaths.dropFirst() { XCTAssertEqual(StrokeOutliner.signedArea(join).sign, outlineSign) }
    }

    func testNonFiniteSamplesAreIgnored() {
        XCTAssertTrue(StrokeOutliner.subpaths(forSamples: [VectorStrokeSample(point: CGPoint(x: Double.nan, y: 0), width: 2)]).isEmpty)
    }

    // MARK: SVG

    func testSVGIsWellFormedAndRoundTripsItsEditingData() throws {
        let fileData = try SVGDrawingFile.encode(makeDrawing(), payload: payload)
        let parser = XMLParser(data: fileData)
        XCTAssertTrue(parser.parse(), "Foundation's XML parser must accept the SVG: \(String(describing: parser.parserError))")
        let text = try XCTUnwrap(String(data: fileData, encoding: .utf8))
        XCTAssertTrue(text.contains("<svg xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(text.contains("fill-opacity=\"0.4\""))
        let reading = SVGDrawingFile.readMetadata(fileData)
        XCTAssertEqual(reading.payload?.strokes, payload.strokes)
        XCTAssertFalse(reading.metadataWasDiscarded)
        let reread = try SVGDrawingFile.vectorDrawing(from: fileData)
        XCTAssertEqual(reread.background, .white)
        guard reread.shapes.count == 2 else { return XCTFail("Expected 2 shapes, found \(reread.shapes.count)") }
        XCTAssertEqual(reread.shapes[1].color.alpha, 0.4, accuracy: 0.001)
    }

    func testSVGEditedByAnotherAppIsNoLongerEditable() throws {
        let fileData = try SVGDrawingFile.encode(makeDrawing(), payload: payload)
        var text = try XCTUnwrap(String(data: fileData, encoding: .utf8))
        text = text.replacingOccurrences(of: "fill=\"#000000\"", with: "fill=\"#ff0000\"")
        let reading = SVGDrawingFile.readMetadata(Data(text.utf8))
        XCTAssertNil(reading.payload)
        XCTAssertTrue(reading.metadataWasDiscarded)
    }

    func testSVGWithoutMetadataIsAnOrdinaryImage() throws {
        let fileData = try SVGDrawingFile.encode(makeDrawing(), payload: nil)
        let reading = SVGDrawingFile.readMetadata(fileData)
        XCTAssertNil(reading.payload)
        XCTAssertFalse(reading.metadataWasDiscarded)
        XCTAssertTrue(XMLParser(data: fileData).parse())
    }

    func testSVGNumbersAreLocaleIndependent() {
        XCTAssertEqual(SVGDrawingFile.formatted(12.345), "12.35")
        XCTAssertEqual(SVGDrawingFile.formatted(-0.5), "-0.5")
        XCTAssertEqual(SVGDrawingFile.formatted(3), "3")
        XCTAssertEqual(SVGDrawingFile.formatted(0.4, fractionDigits: 3), "0.4")
    }

    // MARK: PDF

    func testPDFDrawingOpensInPDFKitAndCoreGraphicsAndRoundTrips() throws {
        let fileData = try PDFDrawingFile.encode(makeDrawing(), payload: payload)
        let document = try XCTUnwrap(PDFDocument(data: fileData))
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 400, height: 200))
        XCTAssertNotNil(CGDataProvider(data: fileData as CFData).flatMap(CGPDFDocument.init))
        XCTAssertEqual(PDFDrawingFile.readMetadata(fileData).payload?.strokes, payload.strokes)
        // The ink is real page content, visible without Graphite.
        let rendered = page.thumbnail(of: CGSize(width: 400, height: 200), for: .mediaBox)
        XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: rendered, pdfPoint: CGPoint(x: 120, y: 150), pageHeight: 200))
        XCTAssertFalse(try InteroperabilityTests.hasDarkPixel(in: rendered, pdfPoint: CGPoint(x: 120, y: 20), pageHeight: 200))
    }

    func testPDFAnnotatedElsewhereIsNoLongerEditable() throws {
        let document = try XCTUnwrap(PDFDocument(data: PDFDrawingFile.encode(makeDrawing(), payload: payload)))
        let page = try XCTUnwrap(document.page(at: 0))
        page.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 40, height: 40), forType: .square, withProperties: nil))
        let modifiedData = try XCTUnwrap(document.dataRepresentation())
        let reading = PDFDrawingFile.readMetadata(modifiedData)
        XCTAssertNil(reading.payload, "Editing strokes would silently drop the other app's annotation.")
    }

    func testPDFWithoutMetadataIsAnOrdinaryPDF() throws {
        let fileData = try PDFDrawingFile.encode(makeDrawing(background: .transparent), payload: nil)
        XCTAssertEqual(PDFDocument(data: fileData)?.pageCount, 1)
        let reading = PDFDrawingFile.readMetadata(fileData)
        XCTAssertNil(reading.payload)
        XCTAssertFalse(reading.metadataWasDiscarded)
    }

    func testPreviewRasterDecodesWithImageIO() throws {
        let pngData = try VectorDrawingRenderer.pngData(for: makeDrawing(), maximumPixelDimension: 800)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(pngData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(image.width, 800)
        XCTAssertEqual(image.height, 400)
        try assertStrokeIsNearTheTop(of: image)
    }

    /// The drawing's horizontal stroke is 50 points below its top edge, and nothing is inked
    /// 50 points above its bottom edge, so an upside-down preview fails.
    private func assertStrokeIsNearTheTop(of image: CGImage, file: StaticString = #filePath, line: UInt = #line) throws {
        // `hasDarkPixel` takes a point with y growing upward from the bottom edge.
        XCTAssertTrue(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 120, y: 150), pageHeight: 200), "The stroke is missing near the top.", file: file, line: line)
        XCTAssertFalse(try InteroperabilityTests.hasDarkPixel(in: image, pdfPoint: CGPoint(x: 120, y: 50), pageHeight: 200), "The preview is upside down.", file: file, line: line)
    }

    func testThumbnailServiceRendersVectorDrawings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let svgLocation = directory.appendingPathComponent("Drawing.svg"), pdfLocation = directory.appendingPathComponent("Drawing.pdf")
        try SVGDrawingFile.encode(makeDrawing(), payload: payload).write(to: svgLocation)
        try PDFDrawingFile.encode(makeDrawing(), payload: payload).write(to: pdfLocation)
        let service = ImageFileService()
        for location in [svgLocation, pdfLocation] {
            let thumbnail = try await service.thumbnailData(at: location, maximumDimension: 400)
            let image = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil).flatMap { source in CGImageSourceCreateImageAtIndex(source, 0, nil) })
            XCTAssertEqual(image.width, 400, location.lastPathComponent)
            XCTAssertEqual(image.height, 200, location.lastPathComponent)
            try assertStrokeIsNearTheTop(of: image)
        }
        let isDrawing = await service.isEditableDrawingPDF(at: pdfLocation)
        XCTAssertTrue(isDrawing)
    }
}
