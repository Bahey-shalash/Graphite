import XCTest
@testable import GraphiteCore

/// The graph view's zoom and position: the geometry the drawing, the hit testing, the pinch
/// and the fit share.
final class GraphViewportTests: XCTestCase {
    private let viewSize = CGSize(width: 800, height: 600)

    func testAScreenPointLeadsBackToTheLayoutPositionUnderIt() {
        var viewport = GraphViewport(scale: 1.7, offset: SIMD2(-40, 25))
        viewport.move(by: SIMD2(12, -8))
        let position = SIMD2(130.0, -75.0)
        let point = viewport.screenPoint(position, in: viewSize)
        XCTAssertEqual(point.x, 400 - 28 + 130 * 1.7, accuracy: 1e-9, "The origin sits in the middle of the view, moved by the offset.")
        let back = viewport.graphPosition(point, in: viewSize)
        XCTAssertEqual(back.x, position.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, position.y, accuracy: 1e-9)
    }

    func testAPinchKeepsThePointUnderTheFingersInPlace() {
        var viewport = GraphViewport(scale: 0.8, offset: SIMD2(30, -10))
        let fingers = CGPoint(x: 610, y: 140)
        let underFingers = viewport.graphPosition(fingers, in: viewSize)
        viewport.zoom(to: 2.5, keepingInPlace: fingers, in: viewSize)
        XCTAssertEqual(viewport.scale, 2.5)
        let after = viewport.screenPoint(underFingers, in: viewSize)
        XCTAssertEqual(after.x, fingers.x, accuracy: 1e-9)
        XCTAssertEqual(after.y, fingers.y, accuracy: 1e-9)
    }

    func testAPinchStopsAtTheZoomLimits() {
        var viewport = GraphViewport()
        viewport.zoom(to: 100, keepingInPlace: CGPoint(x: 10, y: 10), in: viewSize)
        XCTAssertEqual(viewport.scale, GraphViewport.maximumScale)
        viewport.zoom(to: 0.0001, keepingInPlace: CGPoint(x: 10, y: 10), in: viewSize)
        XCTAssertEqual(viewport.scale, GraphViewport.minimumScale)
    }

    func testCenteringPutsTheNodeInTheMiddleZoomedInFarEnoughForNames() {
        var viewport = GraphViewport(scale: 0.3, offset: SIMD2(200, 200))
        viewport.center(on: SIMD2(-50, 80), zoomingInTo: 1.4)
        XCTAssertEqual(viewport.scale, 1.4)
        let middle = viewport.screenPoint(SIMD2(-50, 80), in: viewSize)
        XCTAssertEqual(middle.x, 400, accuracy: 1e-9)
        XCTAssertEqual(middle.y, 300, accuracy: 1e-9)

        var closer = GraphViewport(scale: 3)
        closer.center(on: .zero, zoomingInTo: 1.4)
        XCTAssertEqual(closer.scale, 3, "A view already zoomed in further stays as close.")
    }

    func testANodeFollowsTheZoomBetweenHalfAndTwiceItsSize() {
        XCTAssertEqual(GraphViewport(scale: 1.3).screenRadius(ofNodeRadius: 10), 13)
        XCTAssertEqual(GraphViewport(scale: 0.05).screenRadius(ofNodeRadius: 10), 5, "Far out, a node keeps half its size.")
        XCTAssertEqual(GraphViewport(scale: 6).screenRadius(ofNodeRadius: 10), 20, "Close in, a node grows to twice its size and no more.")
    }

    func testALinkIsAsWideAsTheZoomWithinLimitsAndWiderWhenFocused() {
        XCTAssertEqual(GraphViewport(scale: 0.8).linkWidth(isFocused: false), 0.8)
        XCTAssertEqual(GraphViewport(scale: 0.1).linkWidth(isFocused: false), 0.5)
        XCTAssertEqual(GraphViewport(scale: 3).linkWidth(isFocused: false), 1.2)
        XCTAssertEqual(GraphViewport(scale: 0.8).linkWidth(isFocused: true), 1.2, accuracy: 1e-9)
        XCTAssertEqual(GraphViewport(scale: 0.1).linkWidth(isFocused: true), 1)
        XCTAssertEqual(GraphViewport(scale: 3).linkWidth(isFocused: true), 2)
    }

    func testTheFitShowsEveryNodeAndItsNameInsideTheView() throws {
        let positions: [SIMD2<Double>] = [SIMD2(-300, -120), SIMD2(420, 40), SIMD2(10, 260), SIMD2(-80, -310)]
        let names = positions.map { _ in GraphViewport.NameRoom(characterCount: 24, shownFromScale: 0) }
        let fitted = try XCTUnwrap(GraphViewport.fitting(positions, names: names, in: viewSize))
        let halfNameWidth = 24 * GraphViewport.halfNameWidthPerCharacterPoints
        for position in positions {
            let point = fitted.screenPoint(position, in: viewSize)
            XCTAssertGreaterThanOrEqual(point.x - halfNameWidth, GraphViewport.fitMarginPoints - 1)
            XCTAssertLessThanOrEqual(point.x + halfNameWidth, viewSize.width - GraphViewport.fitMarginPoints + 1)
            XCTAssertGreaterThanOrEqual(point.y, GraphViewport.fitMarginPoints - 1)
            XCTAssertLessThanOrEqual(point.y + GraphViewport.nameHeightPoints, viewSize.height - GraphViewport.fitMarginPoints + 1,
                                     "The line of names under the lowest node is in sight.")
        }
    }

    func testTheFitLeavesNoRoomForNamesNotShownAtItsZoom() throws {
        let positions: [SIMD2<Double>] = [SIMD2(-2_000, 0), SIMD2(2_000, 0), SIMD2(0, 1_000)]
        let hidden = positions.map { _ in GraphViewport.NameRoom(characterCount: 40, shownFromScale: 1.4) }
        let shown = positions.map { _ in GraphViewport.NameRoom(characterCount: 40, shownFromScale: 0) }
        let withoutNames = try XCTUnwrap(GraphViewport.fitting(positions, names: hidden, in: viewSize))
        let withNames = try XCTUnwrap(GraphViewport.fitting(positions, names: shown, in: viewSize))
        XCTAssertLessThan(withoutNames.scale, 1.4, "A large graph is fitted below the zoom where its names show.")
        XCTAssertGreaterThan(withoutNames.scale, withNames.scale, "Names that do not show at that zoom take no room.")
    }

    func testASmallGraphIsNotBlownUp() throws {
        let fitted = try XCTUnwrap(GraphViewport.fitting([SIMD2(0, 0), SIMD2(10, 5)],
                                                         names: Array(repeating: GraphViewport.NameRoom(characterCount: 3, shownFromScale: 0), count: 2),
                                                         in: viewSize))
        XCTAssertEqual(fitted.scale, GraphViewport.maximumFitScale)
    }

    func testTheFitNeedsPositionsRoomAndOneNamePerPosition() {
        let name = GraphViewport.NameRoom(characterCount: 3, shownFromScale: 0)
        XCTAssertNil(GraphViewport.fitting([], names: [], in: viewSize))
        XCTAssertNil(GraphViewport.fitting([SIMD2(0, 0)], names: [name], in: .zero))
        XCTAssertNil(GraphViewport.fitting([SIMD2(0, 0), SIMD2(1, 1)], names: [name], in: viewSize))
    }
}
