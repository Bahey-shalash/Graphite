import XCTest
@testable import MermaidDiagrams

final class FlowchartNodeShapeTests: XCTestCase {
    func testEveryMermaidNameNamesItsOwnShape() {
        for shape in FlowchartNodeShape.allCases {
            for name in shape.mermaidNames {
                XCTAssertEqual(FlowchartNodeShape(shapeName: name), shape, name)
            }
        }
    }

    func testNoNameIsGivenToTwoShapes() {
        let names = FlowchartNodeShape.allCases.flatMap(\.mermaidNames)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testShapeNamesAreMatchedWithoutRegardToCase() {
        XCTAssertEqual(FlowchartNodeShape(shapeName: "squareRect"), .rectangle)
        XCTAssertEqual(FlowchartNodeShape(shapeName: "DIAM"), .diamond)
        XCTAssertEqual(FlowchartNodeShape(shapeName: "doubleCircle"), .doubleCircle)
    }

    func testAShapeNotDrawnYetHasNoCase() {
        XCTAssertNil(FlowchartNodeShape(shapeName: "cloud"))
        XCTAssertNil(FlowchartNodeShape(shapeName: ""))
    }
}
