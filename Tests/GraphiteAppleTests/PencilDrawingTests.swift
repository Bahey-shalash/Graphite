#if canImport(UIKit)
import XCTest
import PencilKit
import PDFKit
import ImageIO
import GraphiteCore
@testable import GraphiteApple

final class PencilDrawingTests: XCTestCase {
    private func stroke(from start: CGPoint, to end: CGPoint, ink: PKInk = PKInk(.pen, color: .black), width: CGFloat = 4) -> PKStroke {
        let controlPoints = (0...20).map { step in
            let fraction = CGFloat(step) / 20
            return PKStrokePoint(location: CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction),
                                 timeOffset: TimeInterval(fraction), size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 1)))
    }

    private func makeDrawing() -> PKDrawing {
        PKDrawing(strokes: [stroke(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 600, y: 420)),
                            stroke(from: CGPoint(x: 120, y: 500), to: CGPoint(x: 700, y: 500), ink: PKInk(.marker, color: .systemYellow), width: 20)])
    }

    private func temporaryLocation(_ fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Graphite-Drawing-\(UUID().uuidString).\(fileExtension)")
    }

    func testEveryFormatRoundTripsStrokesAndCropsToInk() async throws {
        let service = DrawingFileService()
        let content = DrawingContent(strokeData: makeDrawing().dataRepresentation(), canvasWidth: 1024, background: .white)
        for format in DrawingFormat.allCases {
            let location = temporaryLocation(format.fileExtension)
            defer { try? FileManager.default.removeItem(at: location) }
            let revision = try await service.save(content, format: format, to: location, expecting: .absent)
            let editable = try await service.openForEditing(location)
            XCTAssertEqual(editable.format, format)
            XCTAssertEqual(editable.revision, revision)
            XCTAssertEqual(editable.payload.width, 1024, "The saved region keeps the canvas width.")
            XCTAssertLessThan(editable.payload.height, 400, "The saved region is cropped to the ink, not the whole canvas.")
            let reopened = try PKDrawing(data: editable.payload.strokes)
            XCTAssertEqual(reopened.strokes.count, 2)
            XCTAssertEqual(reopened.bounds.minY, DrawingLimits.exportMargin, accuracy: 2, "Strokes are stored relative to the saved region.")
        }
    }

    func testFilesOpenInStandardDecoders() async throws {
        let service = DrawingFileService()
        let content = DrawingContent(strokeData: makeDrawing().dataRepresentation(), canvasWidth: 1024, background: .white)
        let pngData = try await service.fileData(for: content, format: .png)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(pngData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(image.width, 2048, "PNG drawings are saved at 2× for sharp handwriting.")
        let pdfData = try await service.fileData(for: content, format: .pdf)
        XCTAssertEqual(PDFDocument(data: pdfData)?.pageCount, 1)
        let svgData = try await service.fileData(for: content, format: .svg)
        XCTAssertTrue(XMLParser(data: svgData).parse())
    }

    /// Vector output must look like the PencilKit ink: compare how much of the page each covers.
    func testVectorInkCoverageMatchesPencilKitRendering() async throws {
        let drawing = PKDrawing(strokes: [stroke(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 460, y: 140), width: 6)])
        let size = CGSize(width: 500, height: 200)
        var pencilImage = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { pencilImage = drawing.image(from: CGRect(origin: .zero, size: size), scale: 1) }
        let vector = PencilVectorConverter.vectorDrawing(from: drawing, size: size, background: .transparent)
        let vectorPNG = try VectorDrawingRenderer.pngData(for: vector, maximumPixelDimension: 500)
        let vectorImage = try XCTUnwrap(CGImageSourceCreateWithData(vectorPNG as CFData, nil).flatMap { source in CGImageSourceCreateImageAtIndex(source, 0, nil) })
        let pencilCoverage = try inkCoverage(of: XCTUnwrap(pencilImage.cgImage))
        let vectorCoverage = try inkCoverage(of: vectorImage)
        XCTAssertGreaterThan(pencilCoverage, 0)
        XCTAssertEqual(vectorCoverage / pencilCoverage, 1, accuracy: 0.35, "Vector ink covers \(vectorCoverage) versus PencilKit \(pencilCoverage).")
    }

    func testOversizedCanvasIsRejectedAndOriginalKept() async throws {
        let location = temporaryLocation("png")
        defer { try? FileManager.default.removeItem(at: location) }
        let service = DrawingFileService()
        let content = DrawingContent(strokeData: makeDrawing().dataRepresentation(), canvasWidth: 1024, background: .white)
        let revision = try await service.save(content, format: .png, to: location, expecting: .absent)
        let tooWide = DrawingContent(strokeData: makeDrawing().dataRepresentation(), canvasWidth: 100_000, background: .white)
        do {
            _ = try await service.save(tooWide, format: .png, to: location, expecting: .revision(revision))
            XCTFail("An oversized canvas must be rejected before allocation.")
        } catch {
            XCTAssertEqual(try FileRevision.read(location), revision)
        }
    }

    func testOrdinaryImageExplainsWhyItCannotBeEdited() async throws {
        let location = temporaryLocation("png")
        defer { try? FileManager.default.removeItem(at: location) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20)) }
        try image.write(to: location)
        do {
            _ = try await DrawingFileService().openForEditing(location)
            XCTFail("An ordinary PNG has no strokes to edit.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no editable Pencil strokes"))
        }
    }

    func testUnerasedStrokeIsOneSegment() {
        let segments = PencilStrokeSampler.visibleSegments(of: stroke(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0), width: 4))
        XCTAssertEqual(segments.count, 1)
        XCTAssertGreaterThan(segments[0].count, 100)
    }

    /// The pixel eraser masks the middle of a stroke; the gap must not be bridged.
    func testErasedMiddleProducesTwoSegments() {
        let original = stroke(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0), width: 4)
        let visibleArea = UIBezierPath(rect: CGRect(x: -10, y: -10, width: 90, height: 20))
        visibleArea.append(UIBezierPath(rect: CGRect(x: 120, y: -10, width: 90, height: 20)))
        let erased = PKStroke(ink: original.ink, path: original.path, transform: .identity, mask: visibleArea)
        let segments = PencilStrokeSampler.visibleSegments(of: erased)
        XCTAssertEqual(segments.count, 2)
        let allPoints = segments.flatMap { segment in segment.map(\.point.x) }
        XCTAssertFalse(allPoints.contains { horizontalPosition in horizontalPosition > 85 && horizontalPosition < 115 }, "No samples inside the erased gap.")
    }

    private func inkCoverage(of image: CGImage) throws -> Double {
        let width = image.width, height = image.height
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var alphaSum = 0.0
        for pixelIndex in 0..<(width * height) { alphaSum += Double(pixels[pixelIndex * 4 + 3]) / 255 }
        return alphaSum
    }
}
#endif
