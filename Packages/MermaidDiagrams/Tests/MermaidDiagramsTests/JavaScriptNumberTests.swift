import XCTest
@testable import MermaidDiagrams

/// `JavaScriptNumber` against what JavaScript's `Number(text)` gives for the same text.
final class JavaScriptNumberTests: XCTestCase {
    private func value(_ text: String) -> Double? {
        JavaScriptNumber.value(of: text)
    }

    func testDecimalNumbersReadWithTheirSignFractionAndExponent() {
        XCTAssertEqual(value("5"), 5)
        XCTAssertEqual(value(" 5 "), 5)
        XCTAssertEqual(value("-7"), -7)
        XCTAssertEqual(value("+2"), 2)
        XCTAssertEqual(value("3.5"), 3.5)
        XCTAssertEqual(value("3."), 3)
        XCTAssertEqual(value(".5"), 0.5)
        XCTAssertEqual(value("1e3"), 1000)
        XCTAssertEqual(value("25E-1"), 2.5)
        XCTAssertEqual(value("007"), 7)
    }

    func testNothingButSpacesIsZero() {
        XCTAssertEqual(value(""), 0)
        XCTAssertEqual(value(" \t\u{00A0}\u{3000}\r"), 0)
    }

    func testInfinityIsANumberInItsOneSpelling() {
        XCTAssertEqual(value("Infinity"), .infinity)
        XCTAssertEqual(value("-Infinity"), -.infinity)
        XCTAssertEqual(value("+Infinity"), .infinity)
        XCTAssertNil(value("infinity"))
        XCTAssertNil(value("inf"))
        XCTAssertEqual(value("1e400"), .infinity)
        XCTAssertEqual(value(String(repeating: "9", count: 400)), .infinity)
    }

    func testHexadecimalOctalAndBinaryWholeNumbersReadWithoutASign() {
        XCTAssertEqual(value("0x1F"), 31)
        XCTAssertEqual(value("0XfF"), 255)
        XCTAssertEqual(value("0o17"), 15)
        XCTAssertEqual(value("0b101"), 5)
        XCTAssertNil(value("-0x10"))
        XCTAssertNil(value("0x"))
        XCTAssertNil(value("0b102"))
        XCTAssertNil(value("0x1.8"))
    }

    func testAnythingElseIsNotANumber() {
        for text in ["abc", "5a", "1_000", "1,5", ".", "e3", "1e", "--1", "NaN", "nan", "0x1p3", "5 5", "\u{FF15}"] {
            XCTAssertNil(value(text), text)
        }
    }
}
