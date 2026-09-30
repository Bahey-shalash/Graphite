import XCTest
@testable import GraphiteCore

final class AccentLegibilityTests: XCTestCase {
    func testDarkAccentIsLightenedJustEnoughToReadOnADarkBackground() {
        // Graphite's ink blue, #2d5da1.
        let inkBlue = (red: 45.0 / 255, green: 93.0 / 255, blue: 161.0 / 255)
        XCTAssertLessThan(AccentLegibility.contrastOnDarkBackground(red: inkBlue.red, green: inkBlue.green, blue: inkBlue.blue),
                          AccentLegibility.minimumTextContrast, "As chosen, it is too dark for dark appearance.")
        let lightened = AccentLegibility.lightenedForDarkBackground(red: inkBlue.red, green: inkBlue.green, blue: inkBlue.blue)
        let contrast = AccentLegibility.contrastOnDarkBackground(red: lightened.red, green: lightened.green, blue: lightened.blue)
        XCTAssertGreaterThanOrEqual(contrast, AccentLegibility.minimumTextContrast)
        XCTAssertLessThan(contrast, AccentLegibility.minimumTextContrast + 0.1, "No lighter than needed.")
        XCTAssertGreaterThan(lightened.blue, lightened.green)
        XCTAssertGreaterThan(lightened.green, lightened.red, "It is still the same blue.")
    }

    func testAccentThatAlreadyReadsIsLeftAsChosen() {
        let amber = (red: 0.88, green: 0.63, blue: 0.0)
        let result = AccentLegibility.lightenedForDarkBackground(red: amber.red, green: amber.green, blue: amber.blue)
        XCTAssertEqual(result.red, amber.red); XCTAssertEqual(result.green, amber.green); XCTAssertEqual(result.blue, amber.blue)
    }

    func testBlackBecomesAReadableGrayAndLuminanceMatchesTheStandard() {
        let gray = AccentLegibility.lightenedForDarkBackground(red: 0, green: 0, blue: 0)
        XCTAssertEqual(gray.red, gray.green); XCTAssertEqual(gray.green, gray.blue)
        XCTAssertGreaterThanOrEqual(AccentLegibility.contrastOnDarkBackground(red: gray.red, green: gray.green, blue: gray.blue), 4.5)
        XCTAssertEqual(AccentLegibility.relativeLuminance(red: 1, green: 1, blue: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(AccentLegibility.relativeLuminance(red: 0, green: 0, blue: 0), 0, accuracy: 0.0001)
    }
}
