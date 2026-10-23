import XCTest
@testable import MermaidDiagrams

final class XYChartTicksTests: XCTestCase {
    func testTheStepIsOneTwoOrFiveTimesAPowerOfTen() {
        XCTAssertEqual(XYChartTicks.step(span: 7, count: 7), 1)
        XCTAssertEqual(XYChartTicks.step(span: 100, count: 7), 20)
        XCTAssertEqual(XYChartTicks.step(span: 7000, count: 2), 5000)
        XCTAssertEqual(XYChartTicks.step(span: 9, count: 1), 10)
    }

    func testAStepBelowOneIsTheNegativeOfItsInverse() {
        XCTAssertEqual(XYChartTicks.step(span: 1, count: 10), -10)
        XCTAssertEqual(XYChartTicks.step(span: 1, count: 5), -5)
        XCTAssertEqual(XYChartTicks.values(from: 0, to: 0.35, step: -10), [0, 0.1, 0.2, 0.3], "Found by division: 0.3, not 0.30000000000000004")
    }

    func testTheValuesAreTheStepsMultiplesWithinTheRangeAndBounded() {
        XCTAssertEqual(XYChartTicks.values(from: 4000, to: 11000, step: 1000), [4000, 5000, 6000, 7000, 8000, 9000, 10000, 11000])
        XCTAssertEqual(XYChartTicks.values(from: -5, to: 5.5, step: 5), [-5, 0, 5])
        XCTAssertEqual(XYChartTicks.values(from: 0, to: 1e6, step: 1).count, XYChartTicks.maximumMarkCount)
    }
}
