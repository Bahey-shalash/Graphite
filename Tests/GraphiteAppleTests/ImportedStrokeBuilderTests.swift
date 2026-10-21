import XCTest
import CoreGraphics
import PencilKit
import PDFKit
import GraphiteCore
import NotebookImport
@testable import GraphiteApple
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// An imported stroke as a PencilKit stroke: PencilKit draws each sample's planned width in every ink, and the samples
/// are the control points as planned.
final class ImportedStrokeBuilderTests: XCTestCase {
    private let creationDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let renderScale = 4.0
    private let renderArea = CGRect(x: 0, y: 0, width: 240, height: 240)
    private let black = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1)

    private func built(_ importedStroke: ImportedStroke) throws -> PKStroke {
        try XCTUnwrap(ImportedStrokeBuilder.stroke(for: importedStroke, creationDate: creationDate))
    }

    private func straightStroke(_ ink: ImportedStroke.Ink, width: Double, from start: CGPoint, to end: CGPoint) -> ImportedStroke {
        let sampleCount = 41
        let samples = (0..<sampleCount).map { sampleIndex in
            let progress = Double(sampleIndex) / Double(sampleCount - 1)
            return ImportedStrokeSample(location: CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress),
                                        width: width, force: nil, azimuthRadians: nil, altitudeRadians: nil)
        }
        return ImportedStroke(ink: ink, color: black, samples: samples, outline: nil)
    }

    /// The alpha of each pixel of PencilKit's drawing of the stroke, top row first.
    private func renderedAlpha(of stroke: PKStroke) throws -> (alpha: [UInt8], pixelWidth: Int, pixelHeight: Int) {
        let image = PKDrawing(strokes: [stroke]).image(from: renderArea, scale: renderScale)
        #if canImport(UIKit)
        let renderedImage = try XCTUnwrap(image.cgImage)
        #else
        var proposedRectangle = CGRect(origin: .zero, size: image.size)
        let renderedImage = try XCTUnwrap(image.cgImage(forProposedRect: &proposedRectangle, context: nil, hints: nil))
        #endif
        let pixelWidth = renderedImage.width, pixelHeight = renderedImage.height
        var pixelBytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        try pixelBytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                                  bytesPerRow: pixelWidth * 4, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(renderedImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        return (stride(from: 3, to: pixelBytes.count, by: 4).map { byteIndex in pixelBytes[byteIndex] }, pixelWidth, pixelHeight)
    }

    /// The stroke's drawn height in points through columns away from its ends: the rows at least half as opaque as
    /// the column's most opaque row, from the first to the last, averaged over the columns.
    private func renderedHeight(of stroke: PKStroke) throws -> Double {
        let rendering = try renderedAlpha(of: stroke)
        let columns = Array(stride(from: Int(75 * renderScale), through: Int(165 * renderScale), by: 7))
        let heights = columns.map { column in
            let columnAlpha = (0..<rendering.pixelHeight).map { row in Int(rendering.alpha[row * rendering.pixelWidth + column]) }
            let peak = columnAlpha.max() ?? 0
            let inkedRows = columnAlpha.indices.filter { row in peak > 0 && columnAlpha[row] * 2 >= peak }
            guard let firstRow = inkedRows.first, let lastRow = inkedRows.last else { return 0.0 }
            return Double(lastRow - firstRow + 1) / renderScale
        }
        return heights.reduce(0, +) / Double(heights.count)
    }

    private func horizontalStrokeWidth(_ ink: ImportedStroke.Ink, plannedWidth: Double) throws -> Double {
        let importedStroke = straightStroke(ink, width: plannedWidth, from: CGPoint(x: 20, y: 120), to: CGPoint(x: 220, y: 120))
        return try renderedHeight(of: built(importedStroke))
    }

    // MARK: The drawn width

    /// Solid inks draw to a quarter pixel at 4x; the pencil's grain and the marker's chisel ends allow 6% and 0.3 point.
    func testEveryInkDrawsThePlannedWidth() throws {
        let plannedWidthsByInk: [(ink: ImportedStroke.Ink, widths: [Double], tolerance: (Double) -> Double)] = [
            (.monoline, [0.5, 1, 2, 4], { _ in 0.3 }),
            (.pen, [0.8, 1.5, 3, 6, 12], { _ in 0.3 }),
            (.fountainPen, [1, 2.5, 5, 10], { _ in 0.3 }),
            (.pencil, [1, 2, 4, 8, 16], { width in 0.06 * width + 0.3 }),
            (.highlighter, [4, 10, 20, 30], { width in 0.06 * width + 0.3 })
        ]
        for (ink, widths, tolerance) in plannedWidthsByInk {
            for plannedWidth in widths {
                let drawnWidth = try horizontalStrokeWidth(ink, plannedWidth: plannedWidth)
                XCTAssertEqual(drawnWidth, plannedWidth, accuracy: tolerance(plannedWidth), "\(ink) planned \(plannedWidth) points")
            }
        }
    }

    /// The fountain pen's nib and the marker's tip are turned across the stroke whatever its direction; with the
    /// source's azimuth they would draw a quarter or a third of the width along some directions.
    func testTheFountainPenAndTheHighlighterDrawThePlannedWidthAcrossDiagonalStrokes() throws {
        for (start, end) in [(CGPoint(x: 0, y: 0), CGPoint(x: 240, y: 240)), (CGPoint(x: 0, y: 240), CGPoint(x: 240, y: 0))] {
            for (ink, plannedWidth) in [(ImportedStroke.Ink.fountainPen, 8.0), (.highlighter, 16.0)] {
                let importedStroke = straightStroke(ink, width: plannedWidth, from: start, to: end)
                let verticalCut = try renderedHeight(of: built(importedStroke))
                // A band crossed at 45 degrees is √2 times its width tall.
                XCTAssertEqual(verticalCut / 2.0.squareRoot(), plannedWidth, accuracy: 0.1 * plannedWidth, "\(ink) from \(start) to \(end)")
            }
        }
    }

    // MARK: The control points

    func testEachSampleIsOneControlPointWithItsLocationSizeAndPencilState() throws {
        let samples = [
            ImportedStrokeSample(location: CGPoint(x: 10, y: 20), width: 2, force: 0.5, azimuthRadians: 0.3, altitudeRadians: 0.9),
            ImportedStrokeSample(location: CGPoint(x: 14, y: 21), width: 3, force: 2, azimuthRadians: 0.4, altitudeRadians: 1.1),
            ImportedStrokeSample(location: CGPoint(x: 19, y: 25), width: 4, force: nil, azimuthRadians: nil, altitudeRadians: nil)
        ]
        let stroke = try built(ImportedStroke(ink: .pencil, color: black, samples: samples, outline: nil))
        let controlPoints = Array(stroke.path)
        XCTAssertEqual(controlPoints.count, samples.count, "Not resampled.")
        XCTAssertEqual(stroke.path.creationDate, creationDate)
        XCTAssertEqual(stroke.transform, .identity)
        for (controlPoint, sample) in zip(controlPoints, samples) {
            XCTAssertEqual(controlPoint.location.x, sample.location.x, accuracy: 0.001)
            XCTAssertEqual(controlPoint.location.y, sample.location.y, accuracy: 0.001)
            let expectedSize = PencilInkRenderedWidth.pointSize(forRenderedWidth: sample.width, ink: .pencil)
            XCTAssertEqual(controlPoint.size.width, expectedSize, accuracy: 0.001)
            XCTAssertEqual(controlPoint.size.height, expectedSize, accuracy: 0.001)
            XCTAssertEqual(controlPoint.opacity, 1, accuracy: 0.001)
            XCTAssertEqual(controlPoint.force, sample.force ?? ImportedStrokeBuilder.neutralForce, accuracy: 0.001)
            XCTAssertEqual(controlPoint.azimuth, sample.azimuthRadians ?? ImportedStrokeBuilder.neutralAzimuthRadians, accuracy: 0.001)
            XCTAssertEqual(controlPoint.altitude, sample.altitudeRadians ?? ImportedStrokeBuilder.neutralAltitudeRadians, accuracy: 0.001)
        }
        let timeOffsets = controlPoints.map(\.timeOffset)
        XCTAssertEqual(timeOffsets, timeOffsets.sorted())
        XCTAssertEqual(Set(timeOffsets).count, timeOffsets.count, "Strictly increasing.")
    }

    /// Graphite's PDF ink and vector drawings sample a stroke back with `PencilStrokeSampler`: the monoline, the pen
    /// and the pencil at the width PencilKit draws, so an imported stroke edited later is written as wide as planned;
    /// the fountain pen and the highlighter, whose drawn width turns with the nib, at the point size.
    func testPencilStrokeSamplerReadsTheDrawnWidthWhereItDoesNotTurnWithTheNib() throws {
        for (ink, plannedWidth) in [(ImportedStroke.Ink.monoline, 1.0), (.pen, 3), (.pencil, 4)] {
            let stroke = try built(straightStroke(ink, width: plannedWidth, from: CGPoint(x: 20, y: 50), to: CGPoint(x: 120, y: 50)))
            let sampledWidths = PencilStrokeSampler.centerLineSamples(of: stroke).map(\.width)
            XCTAssertFalse(sampledWidths.isEmpty)
            for sampledWidth in sampledWidths { XCTAssertEqual(sampledWidth, plannedWidth, accuracy: 0.01, "\(ink)") }
        }
        for (ink, plannedWidth) in [(ImportedStroke.Ink.fountainPen, 5.0), (.highlighter, 20)] {
            let stroke = try built(straightStroke(ink, width: plannedWidth, from: CGPoint(x: 20, y: 50), to: CGPoint(x: 120, y: 50)))
            let pointSize = PencilInkRenderedWidth.pointSize(forRenderedWidth: plannedWidth, ink: ink)
            for sampledWidth in PencilStrokeSampler.centerLineSamples(of: stroke).map(\.width) {
                XCTAssertEqual(sampledWidth, pointSize, accuracy: 0.001, "\(ink)")
            }
        }
    }

    /// A pen or pencil stroke saved as PDF ink, as other readers and the thumbnails show it, is as wide as PencilKit
    /// drew it on the canvas: a pen point of size 3 is drawn 2 points wide and one of size 8 12 points wide, and the
    /// saved ink took the size as its width, too thick for fine pens and too thin for broad ones.
    func testSavedPDFInkIsAsWideAsPencilKitDrawsTheStroke() throws {
        for (inkType, pointSize) in [(PKInkingTool.InkType.pen, 3.0), (.pen, 8), (.monoline, 4), (.pencil, 4)] {
            let points = (0...40).map { pointIndex in
                PKStrokePoint(location: CGPoint(x: 20 + CGFloat(pointIndex) * 5, y: 120), timeOffset: Double(pointIndex) / 60,
                              size: CGSize(width: pointSize, height: pointSize), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            let stroke = PKStroke(ink: PKInk(inkType, color: .black), path: PKStrokePath(controlPoints: points, creationDate: creationDate))
            let drawnWidth = try renderedHeight(of: stroke)
            let page = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank)))?.page(at: 0))
            let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: page.bounds(for: .cropBox).size)
            let savedStroke = try XCTUnwrap(PDFPageInkTracker.portableStroke(for: stroke, name: "stroke", coordinates: coordinates))
            XCTAssertEqual(savedStroke.width, drawnWidth, accuracy: max(0.3, drawnWidth * 0.06), "\(inkType.rawValue) of point size \(pointSize)")
        }
    }

    func testSamplesThatAreNotFiniteAreLeftOut() throws {
        let samples = [
            ImportedStrokeSample(location: CGPoint(x: 10, y: 20), width: 2, force: nil, azimuthRadians: nil, altitudeRadians: nil),
            ImportedStrokeSample(location: CGPoint(x: CGFloat.nan, y: 20), width: 2, force: nil, azimuthRadians: nil, altitudeRadians: nil),
            ImportedStrokeSample(location: CGPoint(x: 12, y: 20), width: .infinity, force: nil, azimuthRadians: nil, altitudeRadians: nil),
            ImportedStrokeSample(location: CGPoint(x: 14, y: 20), width: 2, force: nil, azimuthRadians: nil, altitudeRadians: nil)
        ]
        let stroke = try built(ImportedStroke(ink: .pen, color: black, samples: samples, outline: nil))
        XCTAssertEqual(Array(stroke.path).map(\.location.x), [10, 14])
        let unusableSamples = [ImportedStrokeSample(location: CGPoint(x: 1, y: 2), width: .nan, force: nil, azimuthRadians: nil, altitudeRadians: nil)]
        let strokeWithoutUsableSample = ImportedStroke(ink: .pen, color: black, samples: unusableSamples, outline: nil)
        XCTAssertNil(ImportedStrokeBuilder.stroke(for: strokeWithoutUsableSample, creationDate: creationDate), "PencilKit cannot hold a stroke without points.")
    }

    func testTheTipIsAQuarterTurnFromTheStrokesDirection() {
        let azimuths = ImportedStrokeBuilder.acrossStrokeAzimuths(along: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
        XCTAssertEqual(azimuths[0], .pi / 2, accuracy: 0.0001, "Along the rows.")
        XCTAssertEqual(azimuths[1], .pi / 2 + .pi / 4, accuracy: 0.0001, "Between neighbours that turn down.")
        XCTAssertEqual(azimuths[2], .pi, accuracy: 0.0001, "Down the page.")
        XCTAssertEqual(ImportedStrokeBuilder.acrossStrokeAzimuths(along: [CGPoint(x: 5, y: 5)]), [.pi / 2], "A dot.")
        XCTAssertEqual(ImportedStrokeBuilder.acrossStrokeAzimuths(along: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 10)]).last ?? 0, .pi,
                       accuracy: 0.0001, "A sample without a direction keeps the one before.")
    }

    // MARK: Ink and color

    func testEachInkIsItsPencilKitInkInThePlannedColor() throws {
        let color = NotebookImportColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.5)
        let expectedInkTypes: [(ImportedStroke.Ink, PKInk.InkType)] = [
            (.monoline, .monoline), (.pen, .pen), (.fountainPen, .fountainPen), (.pencil, .pencil), (.highlighter, .marker)
        ]
        for (ink, expectedInkType) in expectedInkTypes {
            let samples = straightStroke(ink, width: 2, from: .zero, to: CGPoint(x: 9, y: 9)).samples
            let stroke = try built(ImportedStroke(ink: ink, color: color, samples: samples, outline: nil))
            XCTAssertEqual(stroke.ink.inkType, expectedInkType)
            let storedColor = PencilStrokeSampler.color(of: stroke)
            XCTAssertEqual(storedColor.red, 0.2, accuracy: 0.002, "\(ink)")
            XCTAssertEqual(storedColor.green, 0.4, accuracy: 0.002, "\(ink)")
            XCTAssertEqual(storedColor.blue, 0.8, accuracy: 0.002, "\(ink)")
            XCTAssertEqual(storedColor.alpha, 0.5, accuracy: 0.002, "\(ink)")
        }
    }
}
