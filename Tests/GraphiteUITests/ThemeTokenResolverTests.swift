import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The theme resolver: WebKit evaluates a theme's variables and selectors for light and dark,
/// and values a theme leaves at Graphite's defaults stay nil.
@MainActor
final class ThemeTokenResolverTests: XCTestCase {
    private func resolve(_ css: String, classes: String = "", bodyStyle: String = "") async throws -> VaultThemeTokens {
        let inputs = ThemeResolverInputs(themeName: "Test \(UUID().uuidString)", styleSheets: css, bodyClasses: classes, bodyStyle: bodyStyle)
        return try await ThemeTokenResolver().tokens(for: inputs)
    }

    func testLiteralsVariableChainsCalcAndColorMixAreResolvedPerAppearance() async throws {
        let css = """
        .theme-light { --base-ink: #102030; --page: #fffcf0; }
        .theme-dark { --base-ink: #e0e0e0; --page: #100f0f; }
        body { --text-normal: var(--base-ink); --background-primary: var(--page);
               --h1-color: var(--my-heading, #aa0000); --h2-size: calc(1.5em + 4px);
               --tag-background: color-mix(in srgb, #ff0000 50%, #0000ff); --file-line-width: 40rem; --line-height-normal: 1.6; }
        .markdown-rendered h3 { color: #00aa00; font-weight: 800; }
        .callout[data-callout="warning"] { --callout-color: 200, 100, 0; }
        """
        let tokens = try await resolve(css)
        XCTAssertEqual(tokens.light.textNormal?.hex, "#102030", "A var() chain is followed.")
        XCTAssertEqual(tokens.dark.textNormal?.hex, "#e0e0e0", "Each appearance has its own values.")
        XCTAssertEqual(tokens.light.background?.hex, "#fffcf0")
        XCTAssertEqual(tokens.light.headings[0].color?.hex, "#aa0000", "A var() fallback is used when the variable is missing.")
        XCTAssertEqual(tokens.light.headings[1].sizeScale ?? 0, (16 * 1.5 + 4) / 16, accuracy: 0.01, "calc() is evaluated.")
        XCTAssertEqual(tokens.light.headings[2].color?.hex, "#00aa00", "A theme's own selectors apply.")
        XCTAssertEqual(tokens.light.headings[2].weight, 800)
        let mixed = try XCTUnwrap(tokens.light.tagBackground)
        XCTAssertEqual(mixed.red, 0.5, accuracy: 0.02, "color-mix() is evaluated.")
        XCTAssertEqual(mixed.blue, 0.5, accuracy: 0.02)
        XCTAssertEqual(tokens.light.calloutColors["warning"]?.hex, "#c86400")
        XCTAssertEqual(tokens.light.calloutColors["caution"], nil, "Other types keep their default color.")
        XCTAssertEqual(tokens.light.lineWidth ?? 0, 640, accuracy: 0.5)
        XCTAssertEqual(tokens.light.lineHeight ?? 0, 1.6, accuracy: 0.01)
        XCTAssertNil(tokens.light.headings[0].sizeScale, "A value left at Graphite's default is nil, so Graphite draws it as always.")
        XCTAssertNil(tokens.light.codeBackground)
    }

    func testBodyClassesAndInlineVariablesFromThemeSettingsPluginsApply() async throws {
        let css = ".theme-dark.scheme-nord { --background-primary: #2e3440; --text-normal: #d8dee9; }"
        let plain = try await resolve(css)
        XCTAssertNil(plain.dark.background, "Without the scheme's class the theme changes nothing.")
        let schemed = try await resolve(css, classes: "scheme-nord", bodyStyle: "--h1-color: #88c0d0;")
        XCTAssertEqual(schemed.dark.background?.hex, "#2e3440")
        XCTAssertEqual(schemed.dark.headings[0].color?.hex, "#88c0d0", "Variables a plugin sets on the page's body apply.")
    }

    func testResultsAreCachedByTheirInputs() async throws {
        let inputs = ThemeResolverInputs(themeName: "Cached \(UUID().uuidString)", styleSheets: "body { --text-normal: #123456; }", bodyClasses: "", bodyStyle: "")
        let first = try await ThemeTokenResolver().tokens(for: inputs)
        let cached = await ThemeTokenResolver.cachedTokens(fingerprint: inputs.fingerprint)
        XCTAssertEqual(cached, first)
        var changed = inputs
        changed.bodyClasses = "other"
        XCTAssertNotEqual(changed.fingerprint, inputs.fingerprint, "Different inputs are resolved again.")
    }
}
