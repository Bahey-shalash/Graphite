import XCTest
@testable import MermaidDiagrams

/// Text 8 points a character, fitted in 40 points.
final class TimelineTextFittingTests: XCTestCase {
    private func fitted(_ lines: [String]) -> [String] {
        TimelineTextFitting.fitted(DiagramLabel(lines: lines), measurer: UniformWidthTextMeasurer(), maximumWidth: 40).lines
    }

    func testTextThatFitsIsOnlyWrappedAtSpaces() {
        XCTAssertEqual(fitted(["aaa bbb ccc"]), ["aaa", "bbb", "ccc"])
    }

    func testAWordTooWideIsCutWhereItReachesTheEdgeAndASpaceStartsANewRun() {
        XCTAssertEqual(fitted(["aaa bbbbbbbbbb"]), ["aaa", "bbbbb", "bbbbb"])
        XCTAssertEqual(fitted(["cccccccc", "dd"]), ["ccccc", "ccc", "dd"])
    }
}
