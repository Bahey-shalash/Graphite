import XCTest
@testable import MermaidDiagrams

final class FlowchartShapeGeometryTests: XCTestCase {
    private let textSize = CGSize(width: 40, height: 24)

    func testEveryShapeIsLargerThanItsTextExceptBareText() {
        for shape in FlowchartNodeShape.allCases {
            let size = FlowchartShapeGeometry.size(of: shape, textSize: textSize).size
            XCTAssertGreaterThan(size.width, textSize.width, "\(shape)")
            XCTAssertGreaterThan(size.height, textSize.height, "\(shape)")
        }
    }

    func testARectangleIsNeverNarrowerThanFortyEightPoints() {
        XCTAssertEqual(FlowchartShapeGeometry.size(of: .rectangle, textSize: CGSize(width: 2, height: 24)).size.width, 48)
    }

    func testOnlyACylinderMovesItsTextDown() {
        for shape in FlowchartNodeShape.allCases {
            let offset = FlowchartShapeGeometry.size(of: shape, textSize: textSize).textOffset
            XCTAssertEqual(offset > 0, shape == .cylinder, "\(shape)")
        }
    }

    func testRoundOutlinesFallAwayFromTheBoxTowardTheEndsOfASide() {
        let size = CGSize(width: 60, height: 60)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .circle, size: size, side: .bottom, offset: 0), 0)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .circle, size: size, side: .bottom, offset: 30), 30, accuracy: 0.01)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .diamond, size: CGSize(width: 100, height: 50), side: .top, offset: 20), 10, accuracy: 0.01)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .rectangle, size: size, side: .left, offset: 25), 0)
    }

    func testSpansAreNeverNegative() {
        for shape in FlowchartNodeShape.allCases {
            for side in DiagramSide.allCases {
                XCTAssertGreaterThanOrEqual(FlowchartShapeGeometry.span(of: shape, size: CGSize(width: 10, height: 10), side: side), 0, "\(shape) \(side)")
            }
        }
    }
}
