import XCTest
import CoreGraphics
@testable import GraphiteCore

/// The mapping between a page overlay (top-left origin, unrotated) and the PDF crop box
/// (bottom-left origin): `x = minX + px·w/W`, `y = maxY − py·h/H`, and its inverse.
final class PageCoordinatesTests: XCTestCase {
    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001, message, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, message, line: line)
    }

    func testOverlayPointsMapByTheDocumentedFormulaOnCropBoxesWithNonZeroOrigins() throws {
        let cropBoxes = [CGRect(x: 31, y: 72, width: 600, height: 800), CGRect(x: -297, y: -421, width: 595, height: 842), CGRect(x: 0, y: 0, width: 612, height: 792)]
        let overlaySizes = [CGSize(width: 300, height: 1_600), CGSize(width: 1_190, height: 421), CGSize(width: 612, height: 792)]
        let overlayPoints = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 1_200 / 3), CGPoint(x: 123.5, y: 77.25)]
        for cropBox in cropBoxes {
            for overlaySize in overlaySizes {
                let coordinates = try PageCoordinates(cropBox: cropBox, overlaySize: overlaySize)
                for overlayPoint in overlayPoints {
                    let expectedPDFPoint = CGPoint(x: cropBox.minX + overlayPoint.x * cropBox.width / overlaySize.width,
                                                   y: cropBox.maxY - overlayPoint.y * cropBox.height / overlaySize.height)
                    assertPoint(coordinates.pdfPoint(fromOverlay: overlayPoint), expectedPDFPoint, "\(cropBox) \(overlaySize) \(overlayPoint)")
                    assertPoint(coordinates.overlayPoint(fromPDF: expectedPDFPoint), overlayPoint, "inverse of \(overlayPoint)")
                }
            }
        }
    }

    func testTheOverlaysTopLeftIsTheCropBoxsTopLeftAndItsBottomRightTheCropBoxsBottomRight() throws {
        let cropBox = CGRect(x: 31, y: 72, width: 600, height: 800)
        let coordinates = try PageCoordinates(cropBox: cropBox, overlaySize: CGSize(width: 300, height: 400))
        assertPoint(coordinates.pdfPoint(fromOverlay: .zero), CGPoint(x: 31, y: 872))
        assertPoint(coordinates.pdfPoint(fromOverlay: CGPoint(x: 300, y: 400)), CGPoint(x: 631, y: 72))
    }

    func testInvalidGeometryThrows() {
        let validCropBox = CGRect(x: 0, y: 0, width: 100, height: 100), validOverlay = CGSize(width: 100, height: 100)
        let invalidCropBoxes = [
            CGRect(x: 0, y: 0, width: 0, height: 100), CGRect(x: 0, y: 0, width: 100, height: 0), CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), CGRect(x: 0, y: CGFloat.infinity, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100), CGRect(x: 0, y: 0, width: 100, height: CGFloat.nan)
        ]
        for cropBox in invalidCropBoxes { XCTAssertThrowsError(try PageCoordinates(cropBox: cropBox, overlaySize: validOverlay), "\(cropBox)") }
        let invalidOverlays = [CGSize(width: 0, height: 100), CGSize(width: 100, height: 0), CGSize(width: -1, height: 100),
                               CGSize(width: CGFloat.nan, height: 100), CGSize(width: 100, height: CGFloat.infinity)]
        for overlaySize in invalidOverlays { XCTAssertThrowsError(try PageCoordinates(cropBox: validCropBox, overlaySize: overlaySize), "\(overlaySize)") }
        XCTAssertNoThrow(try PageCoordinates(cropBox: validCropBox, overlaySize: validOverlay))
    }
}
