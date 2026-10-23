import XCTest
@testable import MermaidDiagrams

final class FlowchartEdgePortsTests: XCTestCase {
    func testEndsStayWhereTheyAreSpreadWhenNothingIsKeptClear() {
        XCTAssertEqual(FlowchartEdgePorts.clear([-10, 10], of: [], reach: 50), [-10, 10])
    }

    func testEndsMoveTheLeastThatKeepsThemHalfAPortGapFromAKeptPoint() {
        // An edge crosses the box's border at its middle: the one end there moves 10 points aside.
        XCTAssertEqual(FlowchartEdgePorts.clear([0], of: [0], reach: 50), [10])
        XCTAssertEqual(FlowchartEdgePorts.clear([-10, 10], of: [12], reach: 50), [-18, 2])
    }

    func testEndsThatCannotKeepClearWithinTheirSideStayWhereTheyWere() {
        XCTAssertEqual(FlowchartEdgePorts.clear([0], of: [-4, 4], reach: 5), [0])
    }
}
