import XCTest
@testable import MermaidDiagrams

final class SequenceHighlightColorSyntaxTests: XCTestCase {
    private func color(_ text: String) -> SequenceHighlightColor? {
        SequenceHighlightColorSyntax.color(from: text)
    }

    private func assertColor(_ text: String, _ expected: (red: Double, green: Double, blue: Double, alpha: Double), file: StaticString = #filePath,
                             line: UInt = #line) {
        guard let color = color(text) else { return XCTFail("\(text) is a color", file: file, line: line) }
        XCTAssertEqual(color.red, expected.red, accuracy: 0.002, text, file: file, line: line)
        XCTAssertEqual(color.green, expected.green, accuracy: 0.002, text, file: file, line: line)
        XCTAssertEqual(color.blue, expected.blue, accuracy: 0.002, text, file: file, line: line)
        XCTAssertEqual(color.alpha, expected.alpha, accuracy: 0.002, text, file: file, line: line)
    }

    func testRGBIsReadWithCommasOrSpacesNumbersOrPercentages() {
        assertColor("rgb(191, 223, 255)", (191 / 255, 223 / 255, 1, 1))
        assertColor("rgba(0, 0, 255, .1)", (0, 0, 1, 0.1))
        assertColor("RGB(100%, 50%, 0%)", (1, 0.5, 0, 1))
        assertColor("rgb(255 128 0 / 50%)", (1, 128 / 255, 0, 0.5))
    }

    func testHSLIsReadInDegreesOrOtherUnits() {
        assertColor("hsl(120, 100%, 50%)", (0, 1, 0, 1))
        assertColor("hsla(240, 100%, 50%, 0.5)", (0, 0, 1, 0.5))
        assertColor("hsl(0.5turn 100% 25%)", (0, 0.5, 0.5, 1))
    }

    func testColorNamesAndTransparentAreRead() {
        assertColor("aqua", (0, 1, 1, 1))
        assertColor("LightGoldenrodYellow", (0xFA / 255.0, 0xFA / 255.0, 0xD2 / 255.0, 1))
        assertColor("yellowgreen", (0x9A / 255.0, 0xCD / 255.0, 0x32 / 255.0, 1))
        assertColor("transparent", (0, 0, 0, 0))
    }

    func testTextThatIsNoColorGivesNone() {
        XCTAssertNil(color(""))
        XCTAssertNil(color("Important stuff"))
        XCTAssertNil(color("rgb(1, 2)"))
        XCTAssertNil(color("calc(1, 2, 3)"))
        XCTAssertNil(color("rgb(a, b, c)"))
    }
}
