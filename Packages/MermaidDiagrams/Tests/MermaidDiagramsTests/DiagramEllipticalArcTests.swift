import XCTest
@testable import MermaidDiagrams

final class DiagramEllipticalArcTests: XCTestCase {
    func testAnArcTooSmallToReachIsAHalfEllipse() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        DiagramEllipticalArc.addArc(to: path, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 20, y: 0), radii: CGSize(width: 1, height: 1))
        // Swept with increasing angle on a page whose y runs down, from left to right: over the top.
        XCTAssertEqual(path.boundingBoxOfPath.minY, -10, accuracy: 0.05)
        XCTAssertEqual(path.boundingBoxOfPath.maxY, 0, accuracy: 0.05)
        XCTAssertEqual(path.currentPoint.x, 20, accuracy: 0.001)
    }
}
