import XCTest
import CoreGraphics
@testable import GraphiteCore

final class CanvasGeometryTests: XCTestCase {
    private func card(_ identifier: String, _ frame: CGRect) -> CanvasNode {
        CanvasNode(id: identifier, content: .text(identifier), frame: frame)
    }

    private func group(_ identifier: String, _ frame: CGRect) -> CanvasNode {
        CanvasNode(id: identifier, content: .group(label: identifier, background: nil, backgroundStyle: .cover), frame: frame)
    }

    // MARK: Connections

    func testConnectionsAttachToTheMiddleOfTheNamedSides() {
        let fromFrame = CGRect(x: 0, y: 0, width: 200, height: 100), toFrame = CGRect(x: 500, y: 300, width: 100, height: 100)
        XCTAssertEqual(CanvasGeometry.anchor(of: fromFrame, side: .top), CGPoint(x: 100, y: 0))
        XCTAssertEqual(CanvasGeometry.anchor(of: fromFrame, side: .right), CGPoint(x: 200, y: 50))
        XCTAssertEqual(CanvasGeometry.anchor(of: fromFrame, side: .bottom), CGPoint(x: 100, y: 100))
        XCTAssertEqual(CanvasGeometry.anchor(of: fromFrame, side: .left), CGPoint(x: 0, y: 50))
        let route = CanvasGeometry.route(from: fromFrame, to: toFrame, fromSide: .bottom, toSide: .top)
        XCTAssertEqual(route.start, CGPoint(x: 100, y: 100))
        XCTAssertEqual(route.end, CGPoint(x: 550, y: 300))
        XCTAssertEqual(route.point(at: 0), route.start)
        XCTAssertEqual(route.point(at: 1), route.end)
    }

    func testCurvesLeaveAndArriveAtRightAnglesToTheirSides() {
        let route = CanvasGeometry.route(from: CGPoint(x: 0, y: 0), fromSide: .right, to: CGPoint(x: 400, y: 300), toSide: .top)
        XCTAssertEqual(route.startControl.y, route.start.y, "Leaves the right side horizontally")
        XCTAssertGreaterThan(route.startControl.x, route.start.x)
        XCTAssertEqual(route.endControl.x, route.end.x, "Arrives at the top side vertically")
        XCTAssertLessThan(route.endControl.y, route.end.y)
        // Half the distance (250), within 70 to 150.
        XCTAssertEqual(route.startControl.x - route.start.x, 150)
        let shortRoute = CanvasGeometry.route(from: CGPoint(x: 0, y: 0), fromSide: .bottom, to: CGPoint(x: 0, y: 40), toSide: .top)
        XCTAssertEqual(shortRoute.startControl, CGPoint(x: 0, y: 70), "A short connection still bows out enough to be seen.")
        let mediumRoute = CanvasGeometry.route(from: CGPoint(x: 0, y: 0), fromSide: .left, to: CGPoint(x: -200, y: 0), toSide: .right)
        XCTAssertEqual(mediumRoute.startControl, CGPoint(x: -100, y: 0))
        XCTAssertEqual(mediumRoute.endControl, CGPoint(x: -100, y: 0))
        XCTAssertEqual(mediumRoute.midpoint, CGPoint(x: -100, y: 0), "The label sits halfway along.")
    }

    func testSidesLeftOpenAreChosenToBringTheEndsTogether() {
        let left = CGRect(x: 0, y: 0, width: 100, height: 100), right = CGRect(x: 400, y: 0, width: 100, height: 100), below = CGRect(x: 0, y: 400, width: 100, height: 100)
        XCTAssertTrue(CanvasGeometry.sides(from: left, to: right, fromSide: nil, toSide: nil) == (.right, .left))
        XCTAssertTrue(CanvasGeometry.sides(from: right, to: left, fromSide: nil, toSide: nil) == (.left, .right))
        XCTAssertTrue(CanvasGeometry.sides(from: left, to: below, fromSide: nil, toSide: nil) == (.bottom, .top))
        XCTAssertTrue(CanvasGeometry.sides(from: left, to: right, fromSide: .top, toSide: nil) == (.top, .left), "A named side is kept; the other is still the nearest.")
        XCTAssertTrue(CanvasGeometry.sides(from: left, to: right, fromSide: .left, toSide: .right) == (.left, .right))
        XCTAssertEqual(CanvasGeometry.nearestSide(of: right, to: CGPoint(x: 450, y: 110)), .bottom)
        XCTAssertEqual(CanvasGeometry.nearestSide(of: right, to: CGPoint(x: 380, y: 60)), .left)
    }

    func testArrowheadsPointIntoTheCard() {
        let route = CanvasGeometry.route(from: CGPoint(x: 0, y: 0), fromSide: .right, to: CGPoint(x: 300, y: 0), toSide: .left)
        XCTAssertEqual(route.arrowhead(atStart: false, length: 12, halfWidth: 5), [CGPoint(x: 300, y: 0), CGPoint(x: 288, y: -5), CGPoint(x: 288, y: 5)],
                       "The tip touches the card's left side and the base lies outside it.")
        XCTAssertEqual(route.arrowhead(atStart: true, length: 12, halfWidth: 5), [CGPoint(x: 0, y: 0), CGPoint(x: 12, y: 5), CGPoint(x: 12, y: -5)])
        let downward = CanvasGeometry.route(from: CGPoint(x: 0, y: 0), fromSide: .bottom, to: CGPoint(x: 0, y: 300), toSide: .top)
        XCTAssertEqual(downward.arrowhead(atStart: false, length: 10, halfWidth: 4), [CGPoint(x: 0, y: 300), CGPoint(x: 4, y: 290), CGPoint(x: -4, y: 290)])
    }

    func testDistanceToAConnectionFollowsItsCurve() {
        let straight = CanvasGeometry.route(from: CGPoint(x: 0, y: 0), fromSide: .right, to: CGPoint(x: 300, y: 0), toSide: .left)
        XCTAssertEqual(straight.distance(to: CGPoint(x: 150, y: 9)), 9, accuracy: 0.01)
        XCTAssertEqual(straight.distance(to: CGPoint(x: -30, y: 40)), 50, accuracy: 0.01, "Past its end, the distance is to the end.")
        let curved = CanvasGeometry.route(from: CGPoint(x: 0, y: 0), fromSide: .right, to: CGPoint(x: 300, y: 300), toSide: .left)
        XCTAssertLessThan(curved.distance(to: curved.point(at: 0.37)), 0.5)
        XCTAssertGreaterThan(curved.distance(to: CGPoint(x: 150, y: 0)), 40, "A point on the straight line between the ends is off an S-shaped curve.")
        XCTAssertTrue(curved.bounds.contains(curved.point(at: 0.2)) && curved.bounds.contains(curved.point(at: 0.8)))
    }

    // MARK: Hit testing

    func testTheTopmostCardAtAPointIsHitThenConnectionsThenGroupBorders() {
        let nodes = [group("group", CGRect(x: -50, y: -50, width: 600, height: 400)), card("under", CGRect(x: 0, y: 0, width: 200, height: 100)),
                     card("over", CGRect(x: 100, y: 50, width: 200, height: 100)), card("far", CGRect(x: 400, y: 200, width: 100, height: 100))]
        let routes = [(identifier: "edge", route: CanvasGeometry.route(from: nodes[2].frame, to: nodes[3].frame, fromSide: .right, toSide: .left))]
        func target(_ point: CGPoint) -> CanvasHitTarget? {
            CanvasGeometry.target(at: point, nodes: nodes, edgeRoutes: routes, edgeTolerance: 10, groupLabelFrames: ["group": CGRect(x: -50, y: -80, width: 80, height: 26)], borderTolerance: 8)
        }
        XCTAssertEqual(target(CGPoint(x: 150, y: 75)), .node("over"), "Where cards overlap, the later one in the file is on top.")
        XCTAssertEqual(target(CGPoint(x: 50, y: 25)), .node("under"))
        XCTAssertEqual(target(routes[0].route.point(at: 0.5)), .edge("edge"))
        XCTAssertEqual(target(CGPoint(x: routes[0].route.midpoint.x, y: routes[0].route.midpoint.y + 8)), .edge("edge"))
        XCTAssertNil(target(CGPoint(x: 20, y: 250)), "Inside a group, away from cards and connections, is empty board.")
        XCTAssertEqual(target(CGPoint(x: -48, y: 200)), .node("group"), "A group is taken by its border")
        XCTAssertEqual(target(CGPoint(x: 548, y: 345)), .node("group"))
        XCTAssertEqual(target(CGPoint(x: 0, y: -70)), .node("group"), "or by its label.")
        XCTAssertNil(target(CGPoint(x: 900, y: 900)))
    }

    func testASelectionRectangleTakesTouchedCardsAndOnlyWhollyEnclosedGroups() {
        let nodes = [group("group", CGRect(x: 0, y: 0, width: 500, height: 500)), card("inside", CGRect(x: 50, y: 50, width: 100, height: 100)),
                     card("partly", CGRect(x: 180, y: 50, width: 100, height: 100)), card("outside", CGRect(x: 300, y: 300, width: 50, height: 50))]
        XCTAssertEqual(CanvasGeometry.nodes(selectedBy: CGRect(x: 40, y: 40, width: 150, height: 150), among: nodes).map(\.id), ["inside", "partly"])
        XCTAssertEqual(CanvasGeometry.nodes(selectedBy: CGRect(x: -10, y: -10, width: 600, height: 600), among: nodes).map(\.id), ["group", "inside", "partly", "outside"])
        XCTAssertEqual(CanvasGeometry.nodes(inside: nodes[0], among: nodes).map(\.id), ["inside", "partly", "outside"], "Cards wholly inside a group move with it.")
        XCTAssertEqual(CanvasGeometry.nodes(inside: group("small", CGRect(x: 0, y: 0, width: 200, height: 200)), among: nodes).map(\.id), ["inside"])
    }

    // MARK: Snapping

    func testMovingSnapsToOtherCardsFirstAndElseToTheGrid() {
        let other = CGRect(x: 300, y: 100, width: 200, height: 100)
        // Left edge 4 away from the other's left edge; top 33 away from anything.
        let alongside = CanvasGeometry.snappedMove(of: CGRect(x: 296, y: 333, width: 120, height: 80), otherFrames: [other], gridSpacing: 20, tolerance: 8)
        XCTAssertEqual(alongside.frame, CGRect(x: 300, y: 340, width: 120, height: 80))
        XCTAssertEqual(alongside.verticalGuide, 300, "The line both cards now share is shown.")
        XCTAssertNil(alongside.horizontalGuide, "On the grid there is no guide.")
        // Middles line up: the moving card's middle (x 397) against the other's (x 400).
        let centered = CanvasGeometry.snappedMove(of: CGRect(x: 337, y: 400, width: 120, height: 80), otherFrames: [other], gridSpacing: nil, tolerance: 8)
        XCTAssertEqual(centered.frame.midX, 400)
        XCTAssertEqual(centered.frame.minY, 400, "Without the grid, an axis with nothing near stays where it was dragged.")
        // Right edge against the other's left edge, bottom against its top.
        let touching = CanvasGeometry.snappedMove(of: CGRect(x: 183, y: 17, width: 120, height: 80), otherFrames: [other], gridSpacing: 20, tolerance: 8)
        XCTAssertEqual(touching.frame, CGRect(x: 180, y: 20, width: 120, height: 80))
        XCTAssertEqual(touching.verticalGuide, 300)
        XCTAssertEqual(touching.horizontalGuide, 100)
        // Snapping to objects off: only the grid.
        XCTAssertEqual(CanvasGeometry.snappedMove(of: CGRect(x: 296, y: 333, width: 120, height: 80), otherFrames: [], gridSpacing: 20, tolerance: 8).frame.origin, CGPoint(x: 300, y: 340))
        XCTAssertEqual(CanvasGeometry.snappedMove(of: CGRect(x: -29, y: -31, width: 10, height: 10), otherFrames: [], gridSpacing: 20, tolerance: 8).frame.origin, CGPoint(x: -20, y: -40))
        // Both off: nothing moves.
        XCTAssertEqual(CanvasGeometry.snappedMove(of: CGRect(x: 296.5, y: 333, width: 120, height: 80), otherFrames: [], gridSpacing: nil, tolerance: 8).frame.origin, CGPoint(x: 296.5, y: 333))
    }

    func testResizingMovesOnlyTheHandlesEdgesSnapsThemAndKeepsAMinimumSize() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let other = CGRect(x: 400, y: 300, width: 100, height: 100)
        let grown = CanvasGeometry.snappedResize(of: frame, handle: .bottomRight, translation: CGSize(width: 97, height: 53), otherFrames: [other], gridSpacing: 20, tolerance: 8)
        XCTAssertEqual(grown.frame, CGRect(x: 100, y: 100, width: 300, height: 160), "The right edge meets the other card's left edge; the bottom goes to the grid.")
        XCTAssertEqual(grown.verticalGuide, 400)
        XCTAssertNil(grown.horizontalGuide)
        XCTAssertEqual(CanvasGeometry.snappedResize(of: frame, handle: .topLeft, translation: CGSize(width: -33, height: 12), otherFrames: [], gridSpacing: 20, tolerance: 8).frame,
                       CGRect(x: 60, y: 120, width: 240, height: 80))
        XCTAssertEqual(CanvasGeometry.snappedResize(of: frame, handle: .left, translation: CGSize(width: 500, height: 500), otherFrames: [], gridSpacing: 20, tolerance: 8).frame,
                       CGRect(x: 260, y: 100, width: 40, height: 100), "An edge dragged past the opposite one stops at the smallest size.")
        let freelyResized = CanvasGeometry.snappedResize(of: frame, handle: .top, translation: CGSize(width: 40, height: -7.25), otherFrames: [], gridSpacing: nil, tolerance: 8).frame
        XCTAssertEqual(freelyResized, CGRect(x: 100, y: 92.75, width: 200, height: 107.25), "Without snapping the edge follows the finger, and only the top moves.")
        for handle in CanvasResizeHandle.allCases {
            XCTAssertTrue(CGRect(x: 100, y: 100, width: 200, height: 100).insetBy(dx: -0.1, dy: -0.1).contains(handle.position(on: frame)))
        }
        XCTAssertEqual(CanvasResizeHandle.bottomLeft.position(on: frame), CGPoint(x: 100, y: 200))
        XCTAssertEqual(CanvasResizeHandle.right.position(on: frame), CGPoint(x: 300, y: 150))
    }

    // MARK: Viewport

    func testViewportMapsBoardPointsToTheViewAndBack() {
        let viewport = CanvasViewport(scale: 0.5, origin: CGPoint(x: -300, y: 120))
        XCTAssertEqual(viewport.viewPoint(forBoardPoint: CGPoint(x: -300, y: 120)), .zero)
        XCTAssertEqual(viewport.viewPoint(forBoardPoint: CGPoint(x: 100, y: 320)), CGPoint(x: 200, y: 100))
        XCTAssertEqual(viewport.boardPoint(forViewPoint: CGPoint(x: 200, y: 100)), CGPoint(x: 100, y: 320))
        XCTAssertEqual(viewport.viewFrame(forBoardFrame: CGRect(x: 100, y: 320, width: 400, height: 200)), CGRect(x: 200, y: 100, width: 200, height: 100))
        XCTAssertEqual(viewport.visibleBoardFrame(viewSize: CGSize(width: 800, height: 600)), CGRect(x: -300, y: 120, width: 1600, height: 1200))
    }

    func testZoomingKeepsThePointUnderTheFingersAndStaysWithinLimits() {
        var viewport = CanvasViewport(scale: 1, origin: CGPoint(x: 50, y: 50))
        let pinchCenter = CGPoint(x: 300, y: 200)
        let boardPointUnderFingers = viewport.boardPoint(forViewPoint: pinchCenter)
        viewport.zoom(by: 2.5, around: pinchCenter)
        XCTAssertEqual(viewport.scale, 2.5)
        XCTAssertEqual(viewport.viewPoint(forBoardPoint: boardPointUnderFingers).x, pinchCenter.x, accuracy: 0.0001)
        XCTAssertEqual(viewport.viewPoint(forBoardPoint: boardPointUnderFingers).y, pinchCenter.y, accuracy: 0.0001)
        viewport.zoom(by: 1_000, around: pinchCenter)
        XCTAssertEqual(viewport.scale, CanvasViewport.maximumScale)
        viewport.zoom(by: 0.000_001, around: pinchCenter)
        XCTAssertEqual(viewport.scale, CanvasViewport.minimumScale)
        XCTAssertEqual(viewport.viewPoint(forBoardPoint: boardPointUnderFingers).x, pinchCenter.x, accuracy: 0.0001)
        viewport.pan(byViewTranslation: CGSize(width: 10, height: -20))
        XCTAssertEqual(viewport.viewPoint(forBoardPoint: boardPointUnderFingers).x, pinchCenter.x + 10, accuracy: 0.0001)
        XCTAssertEqual(viewport.viewPoint(forBoardPoint: boardPointUnderFingers).y, pinchCenter.y - 20, accuracy: 0.0001)
        XCTAssertEqual(CanvasViewport(scale: .nan).scale, 1)
    }

    func testZoomToFitShowsEveryCardCenteredAndNeverMagnifies() throws {
        let file = try CanvasFixtures.file(CanvasFixtures.obsidianBoard)
        let bounds = CanvasGeometry.bounds(of: file.nodes)
        XCTAssertEqual(bounds, CGRect(x: -420, y: -320, width: 1300, height: 560))
        let viewSize = CGSize(width: 800, height: 600)
        let fitted = CanvasViewport.fitting(bounds, in: viewSize, padding: 40)
        XCTAssertEqual(fitted.scale, 720.0 / 1300.0, accuracy: 0.0001, "The width is what limits this board.")
        let shown = fitted.viewFrame(forBoardFrame: bounds)
        XCTAssertEqual(shown.minX, 40, accuracy: 0.001)
        XCTAssertEqual(shown.maxX, 760, accuracy: 0.001)
        XCTAssertEqual(shown.midY, 300, accuracy: 0.001)
        for node in file.nodes {
            XCTAssertTrue(CGRect(origin: .zero, size: viewSize).contains(fitted.viewFrame(forBoardFrame: node.frame)), "\(node.id) is inside the view")
        }
        let small = CanvasViewport.fitting(CGRect(x: 1000, y: 1000, width: 100, height: 50), in: viewSize, padding: 40)
        XCTAssertEqual(small.scale, 1, "A small board is shown at its own size, in the middle.")
        XCTAssertEqual(small.viewFrame(forBoardFrame: CGRect(x: 1000, y: 1000, width: 100, height: 50)), CGRect(x: 350, y: 275, width: 100, height: 50))
        let empty = CanvasViewport.fitting(.null, in: viewSize, padding: 40)
        XCTAssertEqual(empty.viewPoint(forBoardPoint: .zero), CGPoint(x: 400, y: 300), "An empty board shows its origin in the middle.")
        let huge = CanvasViewport.fitting(CGRect(x: 0, y: 0, width: 10_000_000, height: 10), in: viewSize, padding: 40)
        XCTAssertEqual(huge.scale, CanvasViewport.minimumScale)
    }

    func testRevealMovesTheBoardOnlyAsFarAsNeeded() {
        var viewport = CanvasViewport(scale: 1, origin: .zero)
        let unobscured = CGRect(x: 0, y: 0, width: 800, height: 300)
        viewport.reveal(CGRect(x: 100, y: 50, width: 200, height: 100), in: unobscured, margin: 20)
        XCTAssertEqual(viewport.origin, .zero, "A card already in view stays put.")
        viewport.reveal(CGRect(x: 100, y: 400, width: 200, height: 100), in: unobscured, margin: 20)
        XCTAssertEqual(viewport.viewFrame(forBoardFrame: CGRect(x: 100, y: 400, width: 200, height: 100)), CGRect(x: 100, y: 180, width: 200, height: 100),
                       "A card under the keyboard comes up to just above it.")
        viewport.reveal(CGRect(x: -500, y: 0, width: 2000, height: 1000), in: unobscured, margin: 20)
        XCTAssertEqual(viewport.viewPoint(forBoardPoint: CGPoint(x: -500, y: 0)), CGPoint(x: 20, y: 20), "A card larger than the space shows its top-left corner.")
    }

    // MARK: Reading order

    func testCardsAreReadRowByRowFromTheTopLeft() {
        let nodes = [card("bottom", CGRect(x: 0, y: 500, width: 100, height: 100)), card("top-right", CGRect(x: 400, y: 10, width: 100, height: 100)),
                     card("top-left", CGRect(x: 0, y: 25, width: 100, height: 100)), group("group", CGRect(x: -20, y: -20, width: 600, height: 700)),
                     card("middle", CGRect(x: 200, y: 200, width: 100, height: 100))]
        XCTAssertEqual(CanvasGeometry.readingOrder(of: nodes).map(\.id), ["group", "top-left", "top-right", "middle", "bottom"],
                       "Cards whose tops are nearly level form a row, read from the left; a group comes before what it holds.")
    }

    func testFindingWhatIsVisibleOnAVeryLargeBoardIsQuick() throws {
        let file = try CanvasFixtures.file(CanvasFixtures.largeBoard(cardCount: 20_000))
        let viewport = CanvasViewport(scale: 1, origin: CGPoint(x: 9_000, y: 12_000))
        let visibleFrame = viewport.visibleBoardFrame(viewSize: CGSize(width: 1200, height: 900))
        let frameCount = 600
        let start = ContinuousClock.now
        var visibleCount = 0
        for frameIndex in 0..<frameCount {
            let panned = visibleFrame.offsetBy(dx: CGFloat(frameIndex), dy: 0)
            visibleCount = file.nodes.reduce(0) { count, node in count + (node.frame.intersects(panned) ? 1 : 0) }
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(visibleCount, 4 * 5, "Only the cards in view are found: 4 columns by 5 rows here.")
        let secondsPerFrame = Double(elapsed.components.seconds) / Double(frameCount) + Double(elapsed.components.attoseconds) / 1e18 / Double(frameCount)
        print("Canvas measurement: finding the visible cards among 20000 takes \(String(format: "%.3f", secondsPerFrame * 1000)) ms per frame")
        XCTAssertLessThan(secondsPerFrame, 0.008, "Well inside one frame at 120 Hz.")
    }
}
