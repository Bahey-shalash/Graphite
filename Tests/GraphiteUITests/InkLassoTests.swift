import XCTest
import CoreGraphics
@testable import GraphiteUI

/// The geometry of Graphite's lasso.
@MainActor
final class InkLassoTests: XCTestCase {
    private let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]

    func testPointsAreInsideALoopByTheEvenOddRule() {
        XCTAssertTrue(InkLasso.isPoint(CGPoint(x: 50, y: 50), insideLoop: square))
        XCTAssertFalse(InkLasso.isPoint(CGPoint(x: 150, y: 50), insideLoop: square))
        XCTAssertFalse(InkLasso.isPoint(CGPoint(x: 50, y: -1), insideLoop: square))
        // The loop closes itself: the hand need not return exactly to where it began.
        let openLoop = square + [CGPoint(x: 0, y: 40)]
        XCTAssertTrue(InkLasso.isPoint(CGPoint(x: 10, y: 20), insideLoop: openLoop))
        // A loop shaped like a C does not take what lies in its opening.
        let cShape = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 30), CGPoint(x: 30, y: 30),
                      CGPoint(x: 30, y: 70), CGPoint(x: 100, y: 70), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]
        XCTAssertFalse(InkLasso.isPoint(CGPoint(x: 70, y: 50), insideLoop: cShape))
        XCTAssertTrue(InkLasso.isPoint(CGPoint(x: 15, y: 50), insideLoop: cShape))
        // Fewer than three points enclose nothing.
        XCTAssertFalse(InkLasso.isPoint(CGPoint(x: 5, y: 0), insideLoop: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]))
    }

    func testAStrokeIsTakenWhenMostOfItIsInside() {
        let strokeAcrossTheEdge = (0..<10).map { pointIndex in CGPoint(x: 55 + Double(pointIndex) * 10, y: 50) }
        XCTAssertEqual(InkLasso.enclosedFraction(of: strokeAcrossTheEdge, inLoop: square), 0.5)
        XCTAssertLessThan(0.5, InkLasso.minimumEnclosedFraction, "Half inside is not selected.")
        let strokeMostlyInside = (0..<10).map { pointIndex in CGPoint(x: 25 + Double(pointIndex) * 10, y: 50) }
        XCTAssertGreaterThanOrEqual(InkLasso.enclosedFraction(of: strokeMostlyInside, inLoop: square), InkLasso.minimumEnclosedFraction)
        XCTAssertEqual(InkLasso.enclosedFraction(of: [], inLoop: square), 0)
        XCTAssertEqual(InkLasso.length(of: square), 300)
        XCTAssertEqual(InkLasso.length(of: [CGPoint(x: 3, y: 4)]), 0)
    }

    func testAMovedAndResizedFrameCarriesItsContentAlongInProportion() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 50)
        let moved = InkLasso.transform(from: frame, to: frame.offsetBy(dx: 30, dy: -5))
        XCTAssertEqual(CGPoint(x: 10, y: 20).applying(moved), CGPoint(x: 40, y: 15))
        XCTAssertEqual(CGPoint(x: 110, y: 70).applying(moved), CGPoint(x: 140, y: 65))

        let doubled = InkLasso.transform(from: frame, to: CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(CGPoint(x: 10, y: 20).applying(doubled), .zero)
        XCTAssertEqual(CGPoint(x: 60, y: 45).applying(doubled), CGPoint(x: 100, y: 50), "The middle stays the middle.")
        XCTAssertEqual(CGPoint(x: 110, y: 70).applying(doubled), CGPoint(x: 200, y: 100))
        // A frame without size has nothing to carry.
        XCTAssertEqual(InkLasso.transform(from: .zero, to: frame), .identity)
    }

    func testThePalettesSelectionSwitchTellsCanvasesOnlyWhenItChanges() {
        PaletteInkSelection.isOn = false
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(forName: PaletteInkSelection.didChange, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { notificationCount += 1 }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            PaletteInkSelection.isOn = false
        }
        PaletteInkSelection.isOn = false
        XCTAssertEqual(notificationCount, 0)
        PaletteInkSelection.isOn = true
        PaletteInkSelection.isOn = true
        XCTAssertEqual(notificationCount, 1)
        PaletteInkSelection.isOn = false
        XCTAssertEqual(notificationCount, 2)
    }
}
