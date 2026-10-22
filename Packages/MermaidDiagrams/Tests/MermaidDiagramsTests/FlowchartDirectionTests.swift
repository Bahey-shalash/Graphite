import XCTest
@testable import MermaidDiagrams

final class FlowchartDirectionTests: XCTestCase {
    func testDirectionKeywordsIncludeTheOlderArrows() {
        XCTAssertEqual(FlowchartDirection(keyword: "TD"), .topToBottom)
        XCTAssertEqual(FlowchartDirection(keyword: "tb"), .topToBottom)
        XCTAssertEqual(FlowchartDirection(keyword: "v"), .topToBottom)
        XCTAssertEqual(FlowchartDirection(keyword: "^"), .bottomToTop)
        XCTAssertEqual(FlowchartDirection(keyword: ">"), .leftToRight)
        XCTAssertEqual(FlowchartDirection(keyword: "<"), .rightToLeft)
        XCTAssertNil(FlowchartDirection(keyword: "LT"))
    }

    func testOnlyLeftToRightAndRightToLeftRunAcross() {
        XCTAssertEqual(FlowchartDirection.allCases.filter(\.runsAcross), [.leftToRight, .rightToLeft])
    }
}
