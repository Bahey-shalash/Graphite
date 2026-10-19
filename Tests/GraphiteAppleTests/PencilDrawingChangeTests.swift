#if canImport(UIKit)
import XCTest
import PencilKit
import UIKit
@testable import GraphiteApple

/// A step of a document's ink history applies only to the drawing it produced, and the strokes
/// it puts back are rebuilt from their parts.
final class PencilDrawingChangeTests: XCTestCase {
    private func stroke(startX: CGFloat, createdAt seconds: TimeInterval, color: UIColor = .black, transform: CGAffineTransform = .identity,
                        mask: UIBezierPath? = nil, seed: UInt32 = 7) -> PKStroke {
        let points = (0...4).map { step in
            PKStrokePoint(location: CGPoint(x: startX + CGFloat(step) * 10, y: 20), timeOffset: TimeInterval(step) / 10,
                          size: CGSize(width: 3, height: 3), opacity: 0.9, force: 0.5, azimuth: 0.25, altitude: 1)
        }
        return PKStroke(ink: PKInk(.marker, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: seconds)),
                        transform: transform, mask: mask, randomSeed: seed)
    }

    func testAChangeAppliesOnlyToADrawingWithTheStrokeCountItProducedAndTheStrokesItTouches() throws {
        let kept = stroke(startX: 0, createdAt: 100)
        let removed = stroke(startX: 50, createdAt: 200)
        let before = PKDrawing(strokes: [kept, removed])
        let after = PKDrawing(strokes: [kept])
        let change = try XCTUnwrap(PencilDrawingChange(from: before, to: after))

        XCTAssertNotNil(change.reverting(after))
        // Another stroke count.
        XCTAssertNil(change.reverting(PKDrawing(strokes: [kept, removed])))
        XCTAssertNil(change.reverting(PKDrawing()))
        // A change that only removed strokes checks the count alone: it added nothing to look for.
        let foreign = PKDrawing(strokes: [stroke(startX: 300, createdAt: 900)])
        XCTAssertEqual(change.reverting(foreign)?.strokes.count, 2)
        // Reapplying belongs to the drawing before.
        XCTAssertNotNil(change.reapplying(to: before))
        XCTAssertNil(change.reapplying(to: PKDrawing(strokes: [removed, kept])), "Same strokes in another order are another drawing.")
        XCTAssertNil(change.reapplying(to: PKDrawing(strokes: [kept, stroke(startX: 50, createdAt: 201)])))
    }

    func testRevertingAnAddedStrokeNeedsThatStrokeInThePlaceItWasAdded() throws {
        let drawn = stroke(startX: 0, createdAt: 100)
        let added = stroke(startX: 50, createdAt: 200)
        let change = try XCTUnwrap(PencilDrawingChange(from: PKDrawing(strokes: [drawn]), to: PKDrawing(strokes: [drawn, added])))
        XCTAssertEqual(change.appendedStrokeIndex, 1)
        // Two strokes, but the second is not the one the change added.
        XCTAssertNil(change.reverting(PKDrawing(strokes: [drawn, stroke(startX: 50, createdAt: 999)])))
        XCTAssertEqual(change.reverting(PKDrawing(strokes: [drawn, added]))?.strokes.count, 1)
    }

    func testNoChangeIsRecordedForTwoDrawingsWithTheSameStrokesInTheSameOrder() {
        let strokes = [stroke(startX: 0, createdAt: 100), stroke(startX: 50, createdAt: 200)]
        XCTAssertNil(PencilDrawingChange(from: PKDrawing(strokes: strokes), to: PKDrawing(strokes: strokes)))
    }

    func testARevertedStrokeIsRebuiltFromItsInkPathTransformMaskAndSeed() throws {
        let transform = CGAffineTransform(translationX: 12, y: -4).scaledBy(x: 1.5, y: 1.5)
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 30, height: 30))
        let original = stroke(startX: 0, createdAt: 100, color: UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1), transform: transform, mask: mask, seed: 99)
        let other = stroke(startX: 80, createdAt: 300)
        let change = try XCTUnwrap(PencilDrawingChange(from: PKDrawing(strokes: [original, other]), to: PKDrawing(strokes: [other])))

        let restored = try XCTUnwrap(change.reverting(PKDrawing(strokes: [other])))

        XCTAssertEqual(restored.strokes.count, 2)
        let rebuilt = restored.strokes[0]
        XCTAssertEqual(rebuilt.ink.inkType, original.ink.inkType)
        XCTAssertEqual(PDFStrokeFingerprint(stroke: rebuilt), PDFStrokeFingerprint(stroke: original), "Date, seed, points' ends, transform, mask and ink all match.")
        XCTAssertEqual(rebuilt.transform, original.transform)
        XCTAssertEqual(rebuilt.randomSeed, 99)
        XCTAssertEqual(rebuilt.mask?.cgPath, original.mask?.cgPath)
        XCTAssertNotNil(rebuilt.mask)
        XCTAssertEqual(Array(rebuilt.path).map(\.location), Array(original.path).map(\.location))
        XCTAssertEqual(Array(rebuilt.path).map(\.size), Array(original.path).map(\.size))
        XCTAssertEqual(Array(rebuilt.path).map(\.timeOffset), Array(original.path).map(\.timeOffset))
        XCTAssertEqual(rebuilt.path.creationDate, original.path.creationDate)
        XCTAssertEqual(PDFStrokeFingerprint(stroke: restored.strokes[1]), PDFStrokeFingerprint(stroke: other))
    }

    func testAMovedStrokeCountsAsRemovedAndAddedAndAChangeCanBeReappliedAfterBeingReverted() throws {
        let original = stroke(startX: 0, createdAt: 100)
        let moved = stroke(startX: 0, createdAt: 100, transform: CGAffineTransform(translationX: 40, y: 0))
        let before = PKDrawing(strokes: [original]), after = PKDrawing(strokes: [moved])
        let change = try XCTUnwrap(PencilDrawingChange(from: before, to: after))
        XCTAssertEqual(change.changedStrokeCount, 2)
        XCTAssertNil(change.appendedStrokeIndex)
        let reverted = try XCTUnwrap(change.reverting(after))
        XCTAssertEqual(reverted.strokes.first?.transform, .identity)
        let reapplied = try XCTUnwrap(change.reapplying(to: reverted))
        XCTAssertEqual(reapplied.strokes.first?.transform, CGAffineTransform(translationX: 40, y: 0))
    }
}
#endif
