import Foundation
import CryptoKit
import WebKit
import GraphiteCore

/// What a vault's theme is resolved from: the theme and snippet style sheets, plus what the
/// community plugins' page adds (Style Settings' values, plugins' styles) and the body classes
/// and inline style plugins set there (Minimal Theme Settings' schemes and options).
struct ThemeResolverInputs: Sendable, Equatable {
    var themeName: String
    var styleSheets: String
    var bodyClasses: String
    var bodyStyle: String
    /// Graphite's accent as `--accent-h/-s/-l`, which both the theme and Graphite's defaults
    /// are measured with, so a theme that only follows the accent changes nothing.
    var accentStyle: String = ""

    /// Changes whenever anything that could change a resolved value changes, including
    /// Graphite's default layer, so a cached result is used only for the same inputs.
    var fingerprint: String {
        var hasher = SHA256()
        for part in ["v\(ThemeTokenResolver.defaultLayerVersion)", themeName, styleSheets, bodyClasses, bodyStyle, accentStyle] {
            hasher.update(data: Data(part.utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { byte in String(format: "%02x", byte) }.joined()
    }
}

/// Resolves a theme's values in an off-screen web view: WebKit applies the theme to probe
/// elements laid out like Obsidian's reading view and reports the computed styles, so every
/// `var()` chain, `calc()`, `color-mix()` and selector the theme uses is evaluated as Obsidian
/// evaluates it. One web view is kept while a vault's theme is being resolved and released
/// after; results are cached on the device by the inputs' fingerprint.
@MainActor
final class ThemeTokenResolver: NSObject, WKNavigationDelegate {
    /// The version of `graphite-default-variables.css` and the probes; part of every fingerprint.
    nonisolated static let defaultLayerVersion = 2

    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Error>?

    /// Resolves `inputs`, from the device's cache when the same inputs were resolved before.
    func tokens(for inputs: ThemeResolverInputs) async throws -> VaultThemeTokens {
        let fingerprint = await Task.detached(priority: .utility) { inputs.fingerprint }.value
        if let cached = await Self.cachedTokens(fingerprint: fingerprint) { return cached }
        let tokens = try await resolve(inputs, fingerprint: fingerprint)
        await Self.store(tokens)
        return tokens
    }

    private func resolve(_ inputs: ThemeResolverInputs, fingerprint: String) async throws -> VaultThemeTokens {
        defer { releaseWebView() }
        let webView = try await loadedProbePage()
        let measured = try await webView.callAsyncJavaScript("""
            document.getElementById('graphite-themed-styles').textContent = themed;
            return GraphiteThemeProbe.measure(classes, bodyStyle, accentStyle);
            """, arguments: ["themed": inputs.styleSheets, "classes": inputs.bodyClasses, "bodyStyle": inputs.bodyStyle, "accentStyle": inputs.accentStyle],
            in: nil, contentWorld: .page)
        guard let modes = measured as? [String: Any] else { throw GraphiteError.unavailable("The theme could not be measured.") }
        func modeTokens(_ name: String) -> ThemeModeTokens {
            let mode = modes[name] as? [String: Any] ?? [:]
            let themed = mode["themed"] as? [String: String] ?? [:]
            let defaults = mode["defaults"] as? [String: String] ?? [:]
            return ThemeProbeReading.tokens(themed: themed, defaults: defaults)
        }
        return VaultThemeTokens(fingerprint: fingerprint, themeName: inputs.themeName, light: modeTokens("light"), dark: modeTokens("dark"))
    }

    /// The probe page with Graphite's default layer, ready for a theme's styles.
    private func loadedProbePage() async throws -> WKWebView {
        guard let folder = Bundle.module.url(forResource: "ThemeResolver", withExtension: nil),
              let defaults = try? String(contentsOf: folder.appendingPathComponent("graphite-default-variables.css"), encoding: .utf8),
              let probe = try? String(contentsOf: folder.appendingPathComponent("theme-probe.js"), encoding: .utf8) else {
            throw GraphiteError.unavailable("Graphite's theme resources are missing.")
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // The probe runs Graphite's own script only; a theme's CSS cannot run script.
        configuration.userContentController.addUserScript(WKUserScript(source: probe, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <style id="graphite-default-variables">\(defaults)</style>
            <style id="graphite-themed-styles"></style>
            </head><body class="theme-light is-mobile is-tablet is-ios"></body></html>
            """
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(page, baseURL: nil)
            // A page that never finishes loading must not hold the theme back for good.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.loadContinuation?.resume(throwing: GraphiteError.unavailable("The theme's page did not load."))
                self?.loadContinuation = nil
            }
        }
        return webView
    }

    private func releaseWebView() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    // MARK: The device's cache

    /// Resolved themes, by fingerprint, in Caches: derived data that can always be resolved
    /// again, never part of the vault.
    nonisolated static var cacheFolder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("Graphite/ThemeTokens", isDirectory: true)
    }

    nonisolated static func cachedTokens(fingerprint: String) async -> VaultThemeTokens? {
        await Task.detached(priority: .utility) {
            guard let location = cacheFolder?.appendingPathComponent(fingerprint + ".json"),
                  let data = try? Data(contentsOf: location) else { return nil }
            return try? JSONDecoder().decode(VaultThemeTokens.self, from: data)
        }.value
    }

    nonisolated static func store(_ tokens: VaultThemeTokens) async {
        await Task.detached(priority: .utility) {
            guard let folder = cacheFolder, let data = try? JSONEncoder().encode(tokens) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Best effort: a cache that cannot be written only means resolving again next time.
            try? data.write(to: folder.appendingPathComponent(tokens.fingerprint + ".json"), options: .atomic)
        }.value
    }
}
