import XCTest
import CoreGraphics
@testable import GraphiteUI
import GraphiteTestSupport

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

    func testARectangularLassoIsTheBoxBetweenTwoCornersDraggedEitherWay() {
        let dragged = InkLasso.rectangleLoop(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 20, y: 10))
        XCTAssertEqual(InkLasso.bounds(of: dragged), CGRect(x: 20, y: 10, width: 80, height: 70))
        XCTAssertTrue(InkLasso.isPoint(CGPoint(x: 50, y: 50), insideLoop: dragged))
        XCTAssertFalse(InkLasso.isPoint(CGPoint(x: 10, y: 50), insideLoop: dragged))
        XCTAssertTrue(InkLasso.bounds(of: []).isNull)
    }

    func testAPictureIsTakenWhenMostOfItsAreaIsInsideTheLoopAsTurned() {
        // A picture half over the loop's right edge is not taken; one mostly inside is.
        let halfOutside = InkLasso.samplePoints(ofRectangle: CGRect(x: 50, y: 20, width: 100, height: 60), turnedBy: 0)
        XCTAssertEqual(InkLasso.enclosedFraction(of: halfOutside, inLoop: square), 0.5)
        let mostlyInside = InkLasso.samplePoints(ofRectangle: CGRect(x: 10, y: 20, width: 100, height: 60), turnedBy: 0)
        XCTAssertGreaterThanOrEqual(InkLasso.enclosedFraction(of: mostlyInside, inLoop: square), InkLasso.minimumEnclosedFraction)
        // A long, thin picture turned a quarter fits where it would not upright.
        let tall = CGRect(x: -20, y: 40, width: 140, height: 20)
        XCTAssertLessThan(InkLasso.enclosedFraction(of: InkLasso.samplePoints(ofRectangle: tall, turnedBy: 0), inLoop: [CGPoint(x: 35, y: -30), CGPoint(x: 65, y: -30), CGPoint(x: 65, y: 130), CGPoint(x: 35, y: 130)]), 0.6)
        XCTAssertEqual(InkLasso.enclosedFraction(of: InkLasso.samplePoints(ofRectangle: tall, turnedBy: .pi / 2), inLoop: [CGPoint(x: 35, y: -30), CGPoint(x: 65, y: -30), CGPoint(x: 65, y: 130), CGPoint(x: 35, y: 130)]), 1)
    }

    func testTheLassoTypeAndTheLaserStyleAreRememberedAndStartFreehandWithADot() throws {
        let defaults = try IsolatedDeviceState.make(prefix: "InkLassoTests", for: self).preferences
        XCTAssertEqual(LassoShape.stored(in: defaults), .freehand)
        XCTAssertEqual(LaserPointerStyle.stored(in: defaults), .dot)
        LassoShape.rectangle.store(in: defaults)
        LaserPointerStyle.line.store(in: defaults)
        XCTAssertEqual(LassoShape.stored(in: defaults), .rectangle)
        XCTAssertEqual(LaserPointerStyle.stored(in: defaults), .line)
        XCTAssertEqual(defaults.string(forKey: "GraphiteLassoShape"), "rectangle")
        XCTAssertEqual(defaults.string(forKey: "GraphiteLaserPointerStyle"), "line")
        defaults.set("triangle", forKey: LassoShape.preferenceKey)
        defaults.set("beam", forKey: LaserPointerStyle.preferenceKey)
        XCTAssertEqual(LassoShape.stored(in: defaults), .freehand, "A value another build wrote reads as the default.")
        XCTAssertEqual(LaserPointerStyle.stored(in: defaults), .dot, "A value another build wrote reads as the default.")
    }

    func testAPictureNamedAfterAPageBecomesAFileNameLinksCanHold() {
        XCTAssertEqual(LassoNoteDestination.fileStem(for: "Lecture 3, page 4"), "Lecture 3, page 4")
        XCTAssertEqual(LassoNoteDestination.fileStem(for: "a/b:c|d"), "a-b-c-d")
        XCTAssertEqual(LassoNoteDestination.fileStem(for: "..."), "Screenshot")
    }
}
