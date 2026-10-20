import XCTest
import CoreGraphics
@testable import GraphiteUI

/// The numbers that decide when the Pencil kept still at the end of a stroke turns the stroke
/// into its shape: 0.45 s within 6 screen points, after at least 24 points of stroke. The
/// timer that waits the 0.45 s belongs to the UIKit recognizer; here the distances are driven
/// through `StrokeRest` and the duration is pinned as a number.
final class StrokeRestHoldThresholdsTests: XCTestCase {
    func testTheThresholdsAreFortyFiveHundredthsOfASecondSixPointsAndTwentyFourPoints() {
        XCTAssertEqual(StrokeRest.holdDuration, 0.45)
        XCTAssertEqual(StrokeRest.restingRadius, 6)
        XCTAssertEqual(StrokeRest.minimumStrokeLength, 24)
    }

    func testAStrokeOfExactlyTwentyFourPointsIsLongEnoughForAShapeAndOneShortOfItIsNot() {
        var rest = StrokeRest(startingAt: .zero)
        _ = rest.move(to: CGPoint(x: 23.9, y: 0))
        XCTAssertFalse(rest.isLongEnoughForAShape)
        var longEnough = StrokeRest(startingAt: .zero)
        _ = longEnough.move(to: CGPoint(x: 24, y: 0))
        XCTAssertTrue(longEnough.isLongEnoughForAShape)
    }

    func testTheStrokeLengthIsTheWayTheTouchWentNotTheDistanceFromWhereItBegan() {
        var rest = StrokeRest(startingAt: .zero)
        // Back and forth within the resting radius adds up to a long stroke that never left its place.
        for step in 0..<10 { XCTAssertFalse(rest.move(to: CGPoint(x: step.isMultiple(of: 2) ? 5 : 0, y: 0))) }
        XCTAssertEqual(rest.strokeLength, 50, accuracy: 0.0001, "Every movement counts towards the length.")
        XCTAssertTrue(rest.isLongEnoughForAShape)
        XCTAssertEqual(rest.restingPoint, .zero)
    }

    func testAPointSixAwayIsAtRestAndTheFirstPointBeyondItStartsANewWait() {
        var rest = StrokeRest(startingAt: CGPoint(x: 10, y: 10))
        XCTAssertFalse(rest.move(to: CGPoint(x: 16, y: 10)), "Six screen points is still at rest.")
        XCTAssertEqual(rest.restingPoint, CGPoint(x: 10, y: 10))
        XCTAssertTrue(rest.move(to: CGPoint(x: 16.01, y: 10)), "Beyond six, the touch has left its resting place.")
        XCTAssertEqual(rest.restingPoint, CGPoint(x: 16.01, y: 10), "The wait starts again from the new place.")
    }
}
