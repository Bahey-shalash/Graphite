import XCTest
import CoreGraphics
@testable import GraphiteCore

/// Positions and sizes of canvas cards are written as whole numbers: rounded half away
/// from zero, held to the range a canvas can show, and 0 when a number is not finite.
final class CanvasJSONWriterWholeNumberTests: XCTestCase {
    func testWholeNumbersRoundHalfAwayFromZero() {
        let cases: [(number: Double, whole: Int)] = [
            (0, 0), (0.49, 0), (0.5, 1), (-0.5, -1), (-0.49, 0),
            (1.5, 2), (2.5, 3), (-1.5, -2), (-2.5, -3), (119.5, 120), (-0.6, -1), (1_000.4, 1_000)
        ]
        for testCase in cases {
            XCTAssertEqual(CanvasJSONWriter.wholeNumber(testCase.number), testCase.whole, "\(testCase.number)")
        }
    }

    func testWholeNumbersAreHeldToTenMillionInEachDirection() {
        XCTAssertEqual(CanvasFile.maximumCoordinate, 10_000_000)
        let cases: [(number: Double, whole: Int)] = [
            (10_000_000, 10_000_000), (-10_000_000, -10_000_000), (10_000_000.4, 10_000_000), (-10_000_000.4, -10_000_000),
            (10_000_001, 10_000_000), (-10_000_001, -10_000_000), (1e8, 10_000_000), (-1e8, -10_000_000),
            (1e300, 10_000_000), (-1e300, -10_000_000), (9_999_999.5, 10_000_000)
        ]
        for testCase in cases {
            XCTAssertEqual(CanvasJSONWriter.wholeNumber(testCase.number), testCase.whole, "\(testCase.number)")
        }
    }

    func testNumbersThatAreNotFiniteAreWrittenAsZero() {
        for number in [Double.nan, .infinity, -.infinity, .signalingNaN] {
            XCTAssertEqual(CanvasJSONWriter.wholeNumber(number), 0, "\(number)")
            XCTAssertEqual(CanvasJSONWriter.integer(number), Array("0".utf8), "\(number)")
        }
    }

    func testIntegerBytesAreTheDecimalDigitsOfTheWholeNumber() {
        XCTAssertEqual(String(decoding: CanvasJSONWriter.integer(-0.5), as: UTF8.self), "-1")
        XCTAssertEqual(String(decoding: CanvasJSONWriter.integer(250), as: UTF8.self), "250")
        XCTAssertEqual(String(decoding: CanvasJSONWriter.integer(1e8), as: UTF8.self), "10000000")
        XCTAssertEqual(String(decoding: CanvasJSONWriter.integer(-1e8), as: UTF8.self), "-10000000")
    }

    /// The production path: an edit that moves a card writes the rounded, held number into the file.
    func testMovingACardWritesTheWholeNumberIntoTheFile() throws {
        let text = "{\"nodes\":[{\"id\":\"a\",\"type\":\"text\",\"text\":\"t\",\"x\":0,\"y\":0,\"width\":100,\"height\":50}]}"
        let file = try CanvasFixtures.file(text)
        let moved = try file.applying([.setFrames(["a": CGRect(x: -0.5, y: 1e8, width: 100, height: 50)])]).file
        XCTAssertEqual(String(decoding: moved.data, as: UTF8.self),
                       "{\"nodes\":[{\"id\":\"a\",\"type\":\"text\",\"text\":\"t\",\"x\":-1,\"y\":10000000,\"width\":100,\"height\":50}]}")
        let nonFinite = try file.applying([.setFrames(["a": CGRect(x: CGFloat.nan, y: -CGFloat.infinity, width: 100, height: 50)])]).file
        XCTAssertEqual(nonFinite.data, file.data, "A position that is not finite is written as 0, which is where the card already is.")
    }
}
