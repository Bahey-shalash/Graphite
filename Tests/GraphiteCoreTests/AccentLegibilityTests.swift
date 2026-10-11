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

    func testLightAccentIsDarkenedJustEnoughToReadOnALightBackground() {
        // The Amber preset, #b8860b, reads only 2.9:1 on the grouped light background.
        let amber = (red: 184.0 / 255, green: 134.0 / 255, blue: 11.0 / 255)
        XCTAssertLessThan(AccentLegibility.contrastOnLightBackground(red: amber.red, green: amber.green, blue: amber.blue),
                          AccentLegibility.minimumTextContrast, "As chosen, it is too light for light appearance.")
        let darkened = AccentLegibility.darkenedForLightBackground(red: amber.red, green: amber.green, blue: amber.blue)
        let contrast = AccentLegibility.contrastOnLightBackground(red: darkened.red, green: darkened.green, blue: darkened.blue)
        XCTAssertGreaterThanOrEqual(contrast, AccentLegibility.minimumTextContrast)
        XCTAssertLessThan(contrast, AccentLegibility.minimumTextContrast + 0.1, "No darker than needed.")
        XCTAssertGreaterThan(darkened.red, darkened.green)
        XCTAssertGreaterThan(darkened.green, darkened.blue, "It is still the same amber.")
    }

    func testInkBlueAlreadyReadsInLightAppearanceAndIsLeftAsChosen() {
        let inkBlue = (red: 45.0 / 255, green: 93.0 / 255, blue: 161.0 / 255)
        let result = AccentLegibility.darkenedForLightBackground(red: inkBlue.red, green: inkBlue.green, blue: inkBlue.blue)
        XCTAssertEqual(result.red, inkBlue.red); XCTAssertEqual(result.green, inkBlue.green); XCTAssertEqual(result.blue, inkBlue.blue)
    }

    func testCalloutTitleReadsOnItsOwnTint() {
        // The system cyan of a summary callout, #00C0E8, measured 2.0:1 on its 10% tint.
        let cyan = (red: 0.0, green: 192.0 / 255, blue: 232.0 / 255)
        let tintOpacity = 0.1
        let title = AccentLegibility.darkenedForOwnTint(red: cyan.red, green: cyan.green, blue: cyan.blue, tintOpacity: tintOpacity)
        func tinted(_ component: Double) -> Double { component * tintOpacity + (1 - tintOpacity) }
        let tintLuminance = AccentLegibility.relativeLuminance(red: tinted(cyan.red), green: tinted(cyan.green), blue: tinted(cyan.blue))
        let titleLuminance = AccentLegibility.relativeLuminance(red: title.red, green: title.green, blue: title.blue)
        XCTAssertGreaterThanOrEqual(AccentLegibility.contrast(betweenLuminance: titleLuminance, and: tintLuminance), 4.5)
        XCTAssertLessThan(AccentLegibility.contrast(betweenLuminance: titleLuminance, and: tintLuminance), 4.6)
    }

    func testLightenedAccentReachesTheFullContrastOnTheDarkBackground() {
        // The background's luminance comes from its own components, so a lightened color
        // reaches 4.5:1 rather than stopping just short of it.
        let lightened = AccentLegibility.lightenedForDarkBackground(red: 0.3, green: 0.3, blue: 0.9)
        let darkBackgroundLuminance = AccentLegibility.relativeLuminance(red: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255)
        let lightenedLuminance = AccentLegibility.relativeLuminance(red: lightened.red, green: lightened.green, blue: lightened.blue)
        XCTAssertGreaterThanOrEqual(AccentLegibility.contrast(betweenLuminance: lightenedLuminance, and: darkBackgroundLuminance), 4.5)
    }

    func testBlackBecomesAReadableGrayAndLuminanceMatchesTheStandard() {
        let gray = AccentLegibility.lightenedForDarkBackground(red: 0, green: 0, blue: 0)
        XCTAssertEqual(gray.red, gray.green); XCTAssertEqual(gray.green, gray.blue)
        XCTAssertGreaterThanOrEqual(AccentLegibility.contrastOnDarkBackground(red: gray.red, green: gray.green, blue: gray.blue), 4.5)
        XCTAssertEqual(AccentLegibility.relativeLuminance(red: 1, green: 1, blue: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(AccentLegibility.relativeLuminance(red: 0, green: 0, blue: 0), 0, accuracy: 0.0001)
    }
}
