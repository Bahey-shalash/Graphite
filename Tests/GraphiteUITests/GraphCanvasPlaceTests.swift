import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The graph comes back at the zoom and position it was left at.
final class GraphCanvasPlaceTests: XCTestCase {
    private let leftPlace = GraphCanvasPlace(viewport: GraphViewport(scale: 2.3, offset: SIMD2(-140, 85)), framing: .free, servedCenterRequest: nil)

    func testTheGraphComesBackWhereThePersonLeftIt() {
        XCTAssertEqual(GraphCanvasPlace.starting(from: leftPlace, centerRequest: nil), leftPlace)
    }

    func testWithNothingKeptTheWholeGraphIsFitted() {
        let start = GraphCanvasPlace.starting(from: nil, centerRequest: nil)
        XCTAssertEqual(start.framing, .allNodes)
        XCTAssertEqual(start.viewport, GraphViewport())
    }

    func testANewCenterRequestWinsOverTheKeptPlace() {
        let request = GraphCenterRequest(identifier: "Courses/VLSI/Lab.md")
        let start = GraphCanvasPlace.starting(from: leftPlace, centerRequest: request)
        XCTAssertEqual(start.framing, .node("Courses/VLSI/Lab.md"))
        XCTAssertEqual(start.servedCenterRequest, request)
        XCTAssertEqual(start.viewport, leftPlace.viewport, "It moves from where the view is, rather than from the whole graph.")
    }

    func testARequestAlreadyFollowedDoesNotCenterAgainWhenTheGraphComesBack() {
        let request = GraphCenterRequest(identifier: "Courses/VLSI/Lab.md")
        var kept = leftPlace
        kept.servedCenterRequest = request
        XCTAssertEqual(GraphCanvasPlace.starting(from: kept, centerRequest: request), kept)
        let again = GraphCanvasPlace.starting(from: kept, centerRequest: GraphCenterRequest(identifier: "Courses/VLSI/Lab.md"))
        XCTAssertEqual(again.framing, .node("Courses/VLSI/Lab.md"), "Asking again for the same note centers again.")
    }
}
