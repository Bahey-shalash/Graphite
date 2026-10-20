#if canImport(UIKit)
import XCTest
import PencilKit
import UIKit
@testable import GraphiteApple

/// What makes two Pencil strokes the same stroke to the ink tracker: PencilKit stores a
/// stroke's color and transform as 32-bit numbers, so those compare at that precision,
/// while points, creation date, seed and mask compare exactly.
final class PDFStrokeFingerprintTests: XCTestCase {
    private func points(offset: CGFloat = 0) -> [PKStrokePoint] {
        (0...5).map { step in
            PKStrokePoint(location: CGPoint(x: 10 + CGFloat(step) * 20 + offset, y: 40), timeOffset: TimeInterval(step) / 10,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
    }

    private func stroke(color: UIColor = .black, transform: CGAffineTransform = .identity, mask: UIBezierPath? = nil, seed: UInt32 = 7,
                        creationDate: Date = Date(timeIntervalSince1970: 1_000), pointOffset: CGFloat = 0) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points(offset: pointOffset), creationDate: creationDate),
                 transform: transform, mask: mask, randomSeed: seed)
    }

    private func afterStorage(_ stroke: PKStroke) throws -> PKStroke {
        let stored = try PKDrawing(data: PKDrawing(strokes: [stroke]).dataRepresentation())
        return try XCTUnwrap(stored.strokes.first)
    }

    func testAColorFromAHexValueAndAMovedStrokeKeepTheirFingerprintThroughStorage() throws {
        // 0xFF8040 as fractions is not exactly representable in 32 bits.
        let hexColor = UIColor(red: CGFloat(0xFF) / 255, green: CGFloat(0x80) / 255, blue: CGFloat(0x40) / 255, alpha: 0.7)
        let moved = CGAffineTransform(translationX: 12.345678901234, y: -3.1).rotated(by: 0.3).scaledBy(x: 1.1, y: 0.9)
        let original = stroke(color: hexColor, transform: moved)
        XCTAssertEqual(PDFStrokeFingerprint(stroke: try afterStorage(original)), PDFStrokeFingerprint(stroke: original))
    }

    func testColorAndTransformDifferencesBelowThirtyTwoBitsDoNotMatterButVisibleOnesDo() {
        let base = stroke(color: UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        let nearlyTheSameColor = stroke(color: UIColor(red: 0.2 + 1e-12, green: 0.4, blue: 0.6, alpha: 1))
        let anotherColor = stroke(color: UIColor(red: 0.2, green: 0.4, blue: 0.61, alpha: 1))
        XCTAssertEqual(PDFStrokeFingerprint(stroke: base), PDFStrokeFingerprint(stroke: nearlyTheSameColor))
        XCTAssertNotEqual(PDFStrokeFingerprint(stroke: base), PDFStrokeFingerprint(stroke: anotherColor))
        let nearlyTheSameTransform = stroke(transform: CGAffineTransform(translationX: 1 + 1e-12, y: 0))
        XCTAssertEqual(PDFStrokeFingerprint(stroke: stroke(transform: CGAffineTransform(translationX: 1, y: 0))), PDFStrokeFingerprint(stroke: nearlyTheSameTransform))
        XCTAssertNotEqual(PDFStrokeFingerprint(stroke: stroke()), PDFStrokeFingerprint(stroke: stroke(transform: CGAffineTransform(translationX: 1, y: 0))))
    }

    func testPointsCreationDateSeedAndMaskCompareExactly() {
        let base = PDFStrokeFingerprint(stroke: stroke())
        XCTAssertEqual(base, PDFStrokeFingerprint(stroke: stroke()))
        XCTAssertNotEqual(base, PDFStrokeFingerprint(stroke: stroke(pointOffset: 0.01)), "Every point moved by a hundredth of a point.")
        XCTAssertNotEqual(base, PDFStrokeFingerprint(stroke: stroke(creationDate: Date(timeIntervalSince1970: 1_000.001))))
        XCTAssertNotEqual(base, PDFStrokeFingerprint(stroke: stroke(seed: 8)))
        let firstMask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 100))
        let secondMask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 100.5))
        XCTAssertEqual(PDFStrokeFingerprint(stroke: stroke(mask: firstMask)), PDFStrokeFingerprint(stroke: stroke(mask: UIBezierPath(rect: firstMask.bounds))))
        XCTAssertNotEqual(PDFStrokeFingerprint(stroke: stroke(mask: firstMask)), PDFStrokeFingerprint(stroke: stroke(mask: secondMask)))
        XCTAssertNotEqual(base, PDFStrokeFingerprint(stroke: stroke(mask: firstMask)))
    }
}
#endif
