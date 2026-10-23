import XCTest
@testable import MermaidDiagrams

/// Numbers read as JavaScript's `parseFloat` reads them, the cases of its specification's `StrDecimalLiteral`.
final class JavaScriptNumberReadingTests: XCTestCase {
    func testTheLongestNumberAtTheStartIsRead() {
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("124.729"), 124.729)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("  \t42"), 42)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("12 kg"), 12)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("1.2.3"), 1.2)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("7."), 7)
    }

    func testSignsFractionsAndExponentsAreRead() {
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("-.5"), -0.5)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("+3"), 3)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("1e3"), 1000)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("2.5E-1"), 0.25)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("5e"), 5, "An exponent without digits is left")
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("Infinity"), .infinity)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("-Infinity"), -.infinity)
        XCTAssertEqual(JavaScriptNumberReading.parseFloat("1e400"), .infinity)
    }

    func testTextThatStartsWithNoNumberIsNotANumber() {
        for text in ["abc", "", ".", "+", "-e5", "infinity"] {
            XCTAssertNil(JavaScriptNumberReading.parseFloat(text), text)
        }
    }
}
