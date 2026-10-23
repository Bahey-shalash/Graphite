import XCTest
@testable import MermaidDiagrams

/// The cases of Mermaid 12.1.0's `quadrantDb.spec.ts` (as Pele ports it in `tests/compat/quadrant`) for the styles of a
/// point or a class.
final class QuadrantChartPointStyleSyntaxTests: XCTestCase {
    private func style(_ styles: [String]) throws -> QuadrantChartPointStyle {
        try QuadrantChartPointStyleSyntax.style(from: styles, line: 1)
    }

    private func error(_ styles: [String]) -> MermaidSyntaxProblem? {
        do {
            _ = try QuadrantChartPointStyleSyntax.style(from: styles, line: 1)
            return nil
        } catch {
            guard case .invalidSyntax(_, let problem) = error else { return nil }
            return problem
        }
    }

    func testTheFourStylesAreRead() throws {
        XCTAssertEqual(try style(["radius: 10", "color: #ff0000", "stroke-color: #ff00ff", "stroke-width: 10px"]),
                       QuadrantChartPointStyle(radius: 10, color: QuadrantChartColor(red: 255, green: 0, blue: 0),
                                               strokeColor: QuadrantChartColor(red: 255, green: 0, blue: 255), strokeWidth: 10))
    }

    func testAStyleOfAnotherNameIsAnError() {
        XCTAssertEqual(error(["test_name: value"]), .unsupportedPointStyle(name: "test_name"))
    }

    func testNoStylesIsAnEmptyStyle() throws {
        XCTAssertEqual(try style([]), QuadrantChartPointStyle())
    }

    func testAValueOfTheWrongFormIsAnError() {
        XCTAssertEqual(error(["radius: f"]), .invalidPointStyleValue(name: "radius", value: "f"))
        XCTAssertEqual(error(["color: ffaa"]), .invalidPointStyleValue(name: "color", value: "ffaa"))
        XCTAssertEqual(error(["stroke-color: #f677779"]), .invalidPointStyleValue(name: "stroke-color", value: "#f677779"))
        XCTAssertEqual(error(["stroke-width: 30"]), .invalidPointStyleValue(name: "stroke-width", value: "30"))
        XCTAssertEqual(error(["radius"]), .invalidPointStyleValue(name: "radius", value: "undefined"), "Without a colon, as Mermaid's split leaves it")
    }

    func testAShortColorDoublesEachDigitAndTheNumberSignIsOptional() throws {
        XCTAssertEqual(try style(["color: 00f"]).color, QuadrantChartColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(try style(["color: #AbC"]).color, QuadrantChartColor(red: 0xAA, green: 0xBB, blue: 0xCC))
    }

    func testTheValueStopsAtASecondColonAndALaterStyleWins() throws {
        XCTAssertEqual(QuadrantChartPointStyleSyntax.nameAndValue(" radius :  7 : 9 ").value, "7")
        XCTAssertEqual(try style(["radius: 7", "radius: 9"]).radius, 9)
    }
}
