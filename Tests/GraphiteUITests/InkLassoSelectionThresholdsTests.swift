import XCTest
import CoreGraphics
@testable import GraphiteUI

/// The numbers behind Graphite's lasso: how much of a stroke or picture must lie inside the
/// loop, how small a loop is a slip, and how far a tap reaches. The loop's length and the
/// stroke's sample spacing are applied by the UIKit selection controller
/// (`InkSelectionControllerTests`).
final class InkLassoSelectionThresholdsTests: XCTestCase {
    private let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]

    func testTheThresholdsAreSixtyPercentTwentyFourPointsFourteenPointsAndSixSamplesPerSide() {
        XCTAssertEqual(InkLasso.minimumEnclosedFraction, 0.6)
        XCTAssertEqual(InkLasso.minimumLoopLength, 24)
        XCTAssertEqual(InkLasso.tapReach, 14)
        XCTAssertEqual(InkLasso.pictureSamplesPerSide, 6)
    }

    func testSixOfTenSamplesInsideTheLoopTakeAStrokeAndFiveDoNot() {
        // Ten samples along y = 50; the square covers x from 0 to 100.
        func samples(insideCount: Int) -> [CGPoint] {
            (0..<10).map { index in CGPoint(x: index < insideCount ? Double(index) * 10 : 200 + Double(index), y: 50) }
        }
        XCTAssertGreaterThanOrEqual(InkLasso.enclosedFraction(of: samples(insideCount: 6), inLoop: square), InkLasso.minimumEnclosedFraction)
        XCTAssertLessThan(InkLasso.enclosedFraction(of: samples(insideCount: 5), inLoop: square), InkLasso.minimumEnclosedFraction)
    }

    func testAPictureIsTestedAtThirtySixSamplesAndTakenWhenFourOfItsSixColumnsLieInsideTheLoop() {
        let picture = CGRect(x: 0, y: 0, width: 120, height: 60)
        let samples = InkLasso.samplePoints(ofRectangle: picture, turnedBy: 0)
        XCTAssertEqual(samples.count, 36, "Six samples along each of six rows.")
        // Columns sit at 10, 30, 50, 70, 90, 110: a loop to x = 80 holds four of six columns, to x = 100 five.
        func loop(rightEdge: Double) -> [CGPoint] {
            [CGPoint(x: -1, y: -1), CGPoint(x: rightEdge, y: -1), CGPoint(x: rightEdge, y: 61), CGPoint(x: -1, y: 61)]
        }
        XCTAssertEqual(InkLasso.enclosedFraction(of: samples, inLoop: loop(rightEdge: 80)), 4.0 / 6.0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(InkLasso.enclosedFraction(of: samples, inLoop: loop(rightEdge: 80)), InkLasso.minimumEnclosedFraction)
        XCTAssertEqual(InkLasso.enclosedFraction(of: samples, inLoop: loop(rightEdge: 60)), 3.0 / 6.0, accuracy: 0.0001)
        XCTAssertLessThan(InkLasso.enclosedFraction(of: samples, inLoop: loop(rightEdge: 60)), InkLasso.minimumEnclosedFraction)
    }
}
