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
    nonisolated static let defaultLayerVersion = 4

    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var measurementsInProgress: [String: Task<VaultThemeTokens, Error>] = [:]
    private var latestMeasurement: Task<VaultThemeTokens, Error>?
    private var measurementGeneration = 0

    /// Resolves `inputs`, from the device's cache when the same inputs were resolved before.
    func tokens(for inputs: ThemeResolverInputs) async throws -> VaultThemeTokens {
        let fingerprint = await Task.detached(priority: .utility) { inputs.fingerprint }.value
        if let cached = await Self.cachedTokens(fingerprint: fingerprint) { return cached }
        // The same inputs asked for again while they are measured share that measurement.
        if let measurement = measurementsInProgress[fingerprint] { return try await measurement.value }
        // One page is measured at a time: two measurements on the one web view would each
        // wait for the other's page.
        let previousMeasurement = latestMeasurement
        let measurement = Task { @MainActor [weak self] () throws -> VaultThemeTokens in
            _ = await previousMeasurement?.result
            guard let self else { throw CancellationError() }
            let tokens = try await self.resolveWithinDeadline(inputs, fingerprint: fingerprint)
            await Self.store(tokens)
            return tokens
        }
        measurementsInProgress[fingerprint] = measurement
        latestMeasurement = measurement
        defer { measurementsInProgress[fingerprint] = nil }
        return try await measurement.value
    }

    /// How long one measurement may take. A web content process that stops answering must
    /// not hold the theme back for good; notes keep Graphite's look until the next change.
    static let measurementDeadline = Duration.seconds(15)

    private func resolveWithinDeadline(_ inputs: ThemeResolverInputs, fingerprint: String) async throws -> VaultThemeTokens {
        let outcome = MeasurementOutcome()
        // Whichever of the two ends first stops the other: the deadline held the resolver
        // for its whole 15 seconds after every measurement, and a measurement given up kept
        // running scripts on a web view that was let go.
        let tasks = MeasurementTasks()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<VaultThemeTokens, Error>) in
            tasks.measurement = Task { @MainActor in
                defer { tasks.deadline?.cancel() }
                do {
                    let tokens = try await self.resolve(inputs, fingerprint: fingerprint)
                    if outcome.finish() { continuation.resume(returning: tokens) }
                } catch {
                    if outcome.finish() { continuation.resume(throwing: error) }
                }
            }
            tasks.deadline = Task { @MainActor in
                try? await Task.sleep(for: Self.measurementDeadline)
                guard outcome.finish() else { return }
                tasks.measurement?.cancel()
                // The page is given up: a load still awaited ends, and the web view goes.
                self.loadContinuation?.resume(throwing: GraphiteError.unavailable("The theme's page did not load."))
                self.loadContinuation = nil
                self.releaseWebView()
                continuation.resume(throwing: GraphiteError.unavailable("The theme could not be measured in time."))
            }
        }
    }

    private func resolve(_ inputs: ThemeResolverInputs, fingerprint: String) async throws -> VaultThemeTokens {
        // A measurement given up at its deadline may still end later; it must not release the
        // web view of the measurement after it.
        measurementGeneration += 1
        let generation = measurementGeneration
        defer { if measurementGeneration == generation { releaseWebView() } }
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
        // The default layer lives with the plugin runtime, which links the same file, so the
        // values a theme is compared against are the values plugin pages start from.
        guard let folder = Bundle.module.url(forResource: "ThemeResolver", withExtension: nil),
              let runtimeFolder = Bundle.module.url(forResource: "CommunityPluginRuntime", withExtension: nil),
              let defaults = try? String(contentsOf: runtimeFolder.appendingPathComponent("graphite-default-variables.css"), encoding: .utf8),
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

/// Whether a measurement has ended, by its result or by its deadline; only the first ends it.
@MainActor
private final class MeasurementOutcome {
    private var isFinished = false

    /// True for the first caller only.
    func finish() -> Bool {
        guard !isFinished else { return false }
        isFinished = true
        return true
    }
}

/// The measurement and its deadline, so either can stop the other.
@MainActor
private final class MeasurementTasks {
    var measurement: Task<Void, Never>?
    var deadline: Task<Void, Never>?
}
