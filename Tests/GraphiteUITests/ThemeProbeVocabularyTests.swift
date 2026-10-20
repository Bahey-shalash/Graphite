import XCTest
import WebKit
import GraphiteCore
@testable import GraphiteUI

/// The probe page measures what a theme makes of Obsidian's note elements and
/// `ThemeProbeReading` reads the answers by name; the two must use the same vocabulary. The
/// probe runs here as the theme resolver runs it, with Graphite's default variables alone.
@MainActor
final class ThemeProbeVocabularyTests: XCTestCase {
    private final class PageLoad: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Error>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { continuation?.resume(throwing: error); continuation = nil }
    }

    /// One appearance's measured values by probe key, from the page the resolver builds.
    private func measuredValues(isDark: Bool, themedStyleSheet: String = "") async throws -> [String: String] {
        let probeFolder = try XCTUnwrap(Bundle.module.url(forResource: "ThemeResolver", withExtension: nil))
        let runtimeFolder = try XCTUnwrap(Bundle.module.url(forResource: "CommunityPluginRuntime", withExtension: nil))
        let defaults = try String(contentsOf: runtimeFolder.appendingPathComponent("graphite-default-variables.css"), encoding: .utf8)
        let probe = try String(contentsOf: probeFolder.appendingPathComponent("theme-probe.js"), encoding: .utf8)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(source: probe, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), configuration: configuration)
        let load = PageLoad()
        webView.navigationDelegate = load
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <style id="graphite-default-variables">\(defaults)</style>
            <style id="graphite-themed-styles"></style>
            </head><body class="theme-light is-mobile is-tablet is-ios"></body></html>
            """
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            load.continuation = continuation
            webView.loadHTMLString(page, baseURL: nil)
        }
        let measured = try await webView.callAsyncJavaScript("""
            document.getElementById('graphite-themed-styles').textContent = themed;
            return GraphiteThemeProbe.measure('', '', '');
            """, arguments: ["themed": themedStyleSheet], in: nil, contentWorld: .page)
        let modes = try XCTUnwrap(measured as? [String: Any])
        let mode = try XCTUnwrap(modes[isDark ? "dark" : "light"] as? [String: Any])
        return try XCTUnwrap(mode["themed"] as? [String: String])
    }

    func testTheProbeMeasuresOneHundredFiftyNineKeysOfWhichTwentySevenAreCalloutsAndElevenArePrismTokens() async throws {
        let keys = Set(try await measuredValues(isDark: false).keys)
        XCTAssertEqual(keys.count, 159)
        XCTAssertEqual(keys.filter { key in key.hasPrefix("callout.") }.count - 3, 27, "Besides the 27 types: callout.borderRadius, borderWidth and background.")
        XCTAssertEqual(Set(keys.filter { key in key.hasPrefix("codeToken.") }.map { key in String(key.dropFirst("codeToken.".count)) }),
                       Set(ThemeModeTokens.codeTokenProbeClasses.values))
        XCTAssertEqual(ThemeModeTokens.codeTokenProbeClasses.count, 11)
        let calloutTypeKeys = Set(keys.filter { key in key.hasPrefix("callout.") }.map { key in String(key.dropFirst("callout.".count)) })
            .subtracting(["borderRadius", "borderWidth", "background"])
        XCTAssertEqual(calloutTypeKeys, Set(ObsidianCalloutTypes.variableNamesByType.keys))
    }

    /// A value of the kind each probe key measures, unlike Graphite's defaults, so that
    /// reading it changes a token.
    private func syntheticValue(forKey key: String) -> String {
        switch key {
        case "body.fontSize": return "20px"
        case "body.lineHeight": return "30px"
        case "callout.background": return "rgba(40, 90, 160, 0.25)"
        case "lineWidth.width": return "700px"
        case "unresolvedLink.opacity": return "0.6"
        case "hr.borderStyle": return "dashed"
        case "link.textDecorationLine": return "underline"
        default: break
        }
        if key.hasSuffix(".fontSize") { return "30px" }
        if key.hasSuffix(".fontWeight") { return "700" }
        if key.hasSuffix(".fontFamily") { return "\"Test Font\", serif" }
        if key.hasSuffix(".fontStyle") { return "italic" }
        if key.hasSuffix(".textTransform") { return "uppercase" }
        if key.hasSuffix(".beforeContent") { return "\"§\"" }
        if key.hasSuffix("Width") || key.hasSuffix("Radius") { return "2px" }
        return "rgb(40, 90, 160)"
    }

    /// Reading the probe's answers uses every key the probe measures, and the tokens it makes
    /// from them set every one of the theme-styling groups.
    func testEveryKeyTheProbeMeasuresChangesTheTokensReadFromItsAnswers() async throws {
        let keys = try await measuredValues(isDark: false).keys.sorted()
        let themed = Dictionary(uniqueKeysWithValues: keys.map { key in (key, syntheticValue(forKey: key)) })
        let everythingChanged = ThemeProbeReading.tokens(themed: themed, defaults: [:])
        XCTAssertEqual(everythingChanged.changedGroupCount, ThemeModeTokens.groupCount, "Every group of tokens is set by some probe key.")
        var unread: [String] = []
        for key in keys {
            var withoutKey = themed
            withoutKey[key] = nil
            if ThemeProbeReading.tokens(themed: withoutKey, defaults: [:]) == everythingChanged { unread.append(key) }
        }
        XCTAssertEqual(unread, [], "Probe keys that no token depends on.")
    }

    func testAValueEqualToTheDefaultLayersReadsAsNilForEveryKey() async throws {
        let keys = try await measuredValues(isDark: false).keys.sorted()
        let values = Dictionary(uniqueKeysWithValues: keys.map { key in (key, syntheticValue(forKey: key)) })
        let sameAsDefaults = ThemeProbeReading.tokens(themed: values, defaults: values)
        // With a theme, unresolved links are taken as drawn even where the theme keeps the default.
        XCTAssertNotNil(sameAsDefaults.unresolvedLinkColor)
        var onlyUnresolvedLinks = ThemeModeTokens()
        onlyUnresolvedLinks.unresolvedLinkColor = sameAsDefaults.unresolvedLinkColor
        XCTAssertEqual(sameAsDefaults, onlyUnresolvedLinks)
    }
}
