import XCTest
@testable import MermaidDiagrams

final class LayeredPositioningTests: XCTestCase {
    func testTheFitOfAnOrderedSequenceIsTheSequence() {
        XCTAssertEqual(LayeredPositioning.nondecreasingFit([1, 2, 3], weights: [1, 1, 1]), [1, 2, 3])
    }

    func testViolatorsArePooledToTheirWeightedMean() {
        XCTAssertEqual(LayeredPositioning.nondecreasingFit([3, 1, 2], weights: [1, 1, 1]), [2, 2, 2])
        XCTAssertEqual(LayeredPositioning.nondecreasingFit([4, 0], weights: [3, 1]), [3, 3])
        XCTAssertEqual(LayeredPositioning.nondecreasingFit([0, 5, 1, 9], weights: [1, 1, 1, 1]), [0, 3, 3, 9])
    }
}
