import XCTest
@testable import MermaidDiagrams

/// Numbers read as JavaScript's `parseFloat` reads them, the cases of its specification's `StrDecimalLiteral`.
final class JavaScriptNumberReadingTests: XCTestCase {
    private func parseFloat(_ text: String) -> Double? {
        JavaScriptNumberReading.parseFloat(Array(text.utf8)[...])
    }

    func testTheLongestNumberAtTheStartIsRead() {
        XCTAssertEqual(parseFloat("124.729"), 124.729)
        XCTAssertEqual(parseFloat("  \t42"), 42)
        XCTAssertEqual(parseFloat("12 kg"), 12)
        XCTAssertEqual(parseFloat("1.2.3"), 1.2)
        XCTAssertEqual(parseFloat("7."), 7)
    }

    func testSignsFractionsAndExponentsAreRead() {
        XCTAssertEqual(parseFloat("-.5"), -0.5)
        XCTAssertEqual(parseFloat("+3"), 3)
        XCTAssertEqual(parseFloat("1e3"), 1000)
        XCTAssertEqual(parseFloat("2.5E-1"), 0.25)
        XCTAssertEqual(parseFloat("5e"), 5, "An exponent without digits is left")
        XCTAssertEqual(parseFloat("Infinity"), .infinity)
        XCTAssertEqual(parseFloat("-Infinity"), -.infinity)
        XCTAssertEqual(parseFloat("1e400"), .infinity)
    }

    func testTextThatStartsWithNoNumberIsNotANumber() {
        for text in ["abc", "", ".", "+", "-e5", "infinity"] {
            XCTAssertNil(parseFloat(text), text)
        }
    }
}
