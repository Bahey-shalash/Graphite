import XCTest
@testable import GraphiteBenchmarks

final class AppProjectBenchmarkTests: XCTestCase {
    /// "100k" used to fall back to 10,000 records without a word, so the run measured a
    /// tenth of the workload that was asked for.
    func testRecordCountRejectsAnythingButOneWholeNumberInRange() {
        XCTAssertEqual(GraphiteBenchmarks.recordCount(fromArguments: []), 10_000)
        XCTAssertEqual(GraphiteBenchmarks.recordCount(fromArguments: ["100000"]), 100_000)
        XCTAssertEqual(GraphiteBenchmarks.recordCount(fromArguments: ["1"]), 1)
        XCTAssertEqual(GraphiteBenchmarks.recordCount(fromArguments: ["1000000"]), 1_000_000)
        for rejectedArguments in [["100k"], ["1e5"], ["abc"], ["0"], ["-5"], ["1000001"], ["10", "20"]] {
            XCTAssertNil(GraphiteBenchmarks.recordCount(fromArguments: rejectedArguments), "\(rejectedArguments)")
        }
    }

    /// Indexes 95 and 50 of 100 sorted samples were the 96th and 51st values, one rank
    /// above the nearest-rank p95 and p50.
    func testPercentilesUseNearestRank() {
        let hundredSamples = (1...100).map(Double.init)
        XCTAssertEqual(GraphiteBenchmarks.percentile(95, ofAscending: hundredSamples), 95)
        XCTAssertEqual(GraphiteBenchmarks.percentile(50, ofAscending: hundredSamples), 50)
        XCTAssertEqual(GraphiteBenchmarks.percentile(100, ofAscending: hundredSamples), 100)
        XCTAssertEqual(GraphiteBenchmarks.percentile(1, ofAscending: hundredSamples), 1)
        let tenSamples = (1...10).map(Double.init)
        XCTAssertEqual(GraphiteBenchmarks.percentile(50, ofAscending: tenSamples), 5)
        XCTAssertEqual(GraphiteBenchmarks.percentile(95, ofAscending: tenSamples), 10)
        XCTAssertEqual(GraphiteBenchmarks.percentile(50, ofAscending: [7]), 7)
    }

    func testRegularExpressionQueryExpectsLecturesWrittenAsNineAndMoreDigits() {
        XCTAssertFalse(GraphiteBenchmarks.isNineFollowedByDigits(9))
        XCTAssertTrue(GraphiteBenchmarks.isNineFollowedByDigits(90))
        XCTAssertTrue(GraphiteBenchmarks.isNineFollowedByDigits(912))
        XCTAssertFalse(GraphiteBenchmarks.isNineFollowedByDigits(190))
    }
}
