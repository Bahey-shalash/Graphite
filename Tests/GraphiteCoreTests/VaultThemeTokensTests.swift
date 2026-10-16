import XCTest
@testable import GraphiteCore

final class VaultThemeTokensTests: XCTestCase {
    func testComputedColorsAreRead() throws {
        XCTAssertEqual(ThemeColor(computedCSS: "rgb(46, 52, 64)")?.hex, "#2e3440")
        XCTAssertEqual(ThemeColor(computedCSS: "rgba(0, 0, 0, 0.5)")?.alpha, 0.5)
        XCTAssertEqual(ThemeColor(computedCSS: "rgb(255 0 0 / 25%)")?.alpha, 0.25)
        let mixed = try XCTUnwrap(ThemeColor(computedCSS: "color(srgb 0.5 0.25 1 / 0.8)"))
        XCTAssertEqual(mixed.green, 0.25)
        XCTAssertEqual(mixed.alpha, 0.8)
        XCTAssertNil(ThemeColor(computedCSS: "transparent"))
        XCTAssertNil(ThemeColor(computedCSS: "var(--x)"))
    }

    func testValuesLeftAtGraphitesDefaultsAreNil() {
        let defaults: ThemeProbeReading.Values = ["body.fontSize": "16px", "body.color": "rgb(34, 34, 34)", "h1.fontSize": "25.6px",
                                                  "h1.color": "rgb(34, 34, 34)", "callout.note": "rgb(8, 109, 221)", "body.lineHeight": "24px"]
        var themed = defaults
        themed["h1.fontSize"] = "32px"
        themed["callout.note"] = "rgb(136, 192, 208)"
        themed["body.lineHeight"] = "28.8px"
        themed["unresolvedLink.color"] = "rgb(100, 100, 255)"
        themed["unresolvedLink.opacity"] = "0.5"
        let tokens = ThemeProbeReading.tokens(themed: themed, defaults: defaults)
        XCTAssertNil(tokens.textNormal, "Unchanged: Graphite keeps drawing it.")
        XCTAssertNil(tokens.headings[0].color)
        XCTAssertEqual(tokens.headings[0].sizeScale, 2, "Sizes become multiples of the text size, so Dynamic Type still scales them.")
        XCTAssertEqual(tokens.calloutColors["note"]?.hex, "#88c0d0")
        XCTAssertEqual(tokens.lineHeight, 1.8)
        XCTAssertEqual(tokens.unresolvedLinkColor?.alpha, 0.5, "Unresolved links are dimmed as Obsidian dims them.")
        XCTAssertEqual(tokens.changedGroupCount, 4)
    }

    func testTheContrastGuardKeepsTextReadableOnTheThemesPage() {
        let white = ThemeColor(red: 1, green: 1, blue: 1), nord = ThemeColor(computedCSS: "rgb(46, 52, 64)")!
        let paleLink = ThemeColor(computedCSS: "rgb(180, 200, 255)")!
        let fixed = ThemeContrastGuard.readable(paleLink, on: white, target: ThemeContrastGuard.textContrast)
        XCTAssertGreaterThanOrEqual(fixed.contrast(with: white), 4.5, "A pale link on white is darkened until it reads.")
        let increased = ThemeContrastGuard.readable(paleLink, on: white, target: AccentLegibility.increasedTextContrast)
        XCTAssertGreaterThanOrEqual(increased.contrast(with: white), 7, "Increase Contrast pushes further.")
        let darkText = ThemeColor(computedCSS: "rgb(60, 66, 80)")!
        let lightened = ThemeContrastGuard.readable(darkText, on: nord, target: ThemeContrastGuard.textContrast)
        XCTAssertGreaterThanOrEqual(lightened.contrast(with: nord), 4.5, "Dark text on a dark page is lightened.")
        let readable = ThemeColor(computedCSS: "rgb(216, 222, 233)")!
        XCTAssertEqual(ThemeContrastGuard.readable(readable, on: nord, target: 4.5), readable, "A color that reads is kept as the theme made it.")
        let translucent = ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.3)
        XCTAssertGreaterThanOrEqual(ThemeContrastGuard.readable(translucent, on: white, target: 4.5).contrast(with: white), 4.5, "Translucent text is judged as drawn.")
    }

    func testAHighlightLikeReadAloudsIsRecognized() {
        XCTAssertTrue(ThemeContrastGuard.resemblesReadAloudHighlight(ThemeColor(computedCSS: "rgba(0, 122, 255, 0.3)")!))
        XCTAssertFalse(ThemeContrastGuard.resemblesReadAloudHighlight(ThemeColor(computedCSS: "rgba(255, 208, 0, 0.4)")!))
        XCTAssertFalse(ThemeContrastGuard.resemblesReadAloudHighlight(ThemeColor(computedCSS: "rgb(128, 128, 128)")!), "A gray has no hue to confuse.")
    }

    func testUnknownCalloutTypesTakeTheNoteColor() {
        XCTAssertEqual(ObsidianCalloutTypes.canonicalType("Warning"), "warning")
        XCTAssertEqual(ObsidianCalloutTypes.canonicalType("my-own"), "note")
    }

    func testSyntaxColorsAreTakenTogetherWhenTheThemeChangesAny() {
        var defaults: ThemeProbeReading.Values = ["body.fontSize": "16px"]
        for (kind, tokenClass) in ThemeModeTokens.codeTokenProbeClasses { defaults["codeToken." + tokenClass] = kind == "comment" ? "rgb(171, 171, 171)" : "rgb(213, 57, 132)" }
        XCTAssertNil(ThemeProbeReading.tokens(themed: defaults, defaults: defaults).codeTokenColors, "A theme that keeps Obsidian's syntax colors leaves Graphite's.")
        var themed = defaults
        themed["codeToken.keyword"] = "rgb(255, 0, 0)"
        let colors = ThemeProbeReading.tokens(themed: themed, defaults: defaults).codeTokenColors
        XCTAssertEqual(colors?[CodeTokenKind.keyword.rawValue], ThemeColor(computedCSS: "rgb(255, 0, 0)"))
        XCTAssertEqual(colors?[CodeTokenKind.comment.rawValue], ThemeColor(computedCSS: "rgb(171, 171, 171)"), "The theme's other syntax colors come with it.")
        XCTAssertEqual(colors?.count, CodeTokenKind.allCases.count)
    }
}
