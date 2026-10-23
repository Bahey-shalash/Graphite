import XCTest
@testable import MermaidDiagrams

/// Numbers written as JavaScript's `String(number)` writes them, the cases of its specification's Number::toString.
final class JavaScriptNumberTextTests: XCTestCase {
    func testWholeNumbersHaveNoFraction() {
        XCTAssertEqual(JavaScriptNumberText.text(0), "0")
        XCTAssertEqual(JavaScriptNumberText.text(-0.0), "0")
        XCTAssertEqual(JavaScriptNumberText.text(100), "100")
        XCTAssertEqual(JavaScriptNumberText.text(-4000), "-4000")
        XCTAssertEqual(JavaScriptNumberText.text(1e20), "100000000000000000000")
    }

    func testFractionsHaveTheirShortestDigits() {
        XCTAssertEqual(JavaScriptNumberText.text(0.3), "0.3")
        XCTAssertEqual(JavaScriptNumberText.text(198.2), "198.2")
        XCTAssertEqual(JavaScriptNumberText.text(-2.5), "-2.5")
        XCTAssertEqual(JavaScriptNumberText.text(0.000001), "0.000001")
    }

    func testVeryLargeAndVerySmallNumbersHaveAnExponent() {
        XCTAssertEqual(JavaScriptNumberText.text(1e21), "1e+21")
        XCTAssertEqual(JavaScriptNumberText.text(1.5e300), "1.5e+300")
        XCTAssertEqual(JavaScriptNumberText.text(1e-7), "1e-7")
        XCTAssertEqual(JavaScriptNumberText.text(-2.5e-8), "-2.5e-8")
    }
}
