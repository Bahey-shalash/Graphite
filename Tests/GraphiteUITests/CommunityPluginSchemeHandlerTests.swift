import XCTest
import WebKit
import GraphiteCore
@testable import GraphiteUI

/// `CommunityPluginSchemeHandler` serving the plugin web view: the runtime page's address, the
/// vault files under `graphite-plugins://vault/`, and what is refused. The page fetches the
/// addresses as a plugin's view would.
@MainActor
final class CommunityPluginSchemeHandlerTests: XCTestCase {
    private var temporaryFolders: [URL] = []
    private var loadedWebViews: [WKWebView] = []
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
        for webView in loadedWebViews { webView.stopLoading() }
        loadedWebViews = []
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) }
        temporaryFolders = []
    }

    func testTheRuntimePageAndTheVaultResourcePrefixAreAddressesOnTheGraphitePluginsScheme() {
        XCTAssertEqual(CommunityPluginSchemeHandler.scheme, "graphite-plugins")
        XCTAssertEqual(CommunityPluginSchemeHandler.runtimePageAddress?.absoluteString, "graphite-plugins://runtime/index.html")
        XCTAssertEqual(CommunityPluginSchemeHandler.resourcePathPrefix, "graphite-plugins://vault/")
    }

    func testAVaultFileIsServedWithItsBytesItsTypeAndTheRuntimesOriginAllowed() async throws {
        let vault = try makeVault(files: ["Notes/Plain.txt": "plain text"])

        let served = try await serve("graphite-plugins://vault/Notes/Plain.txt", vaultAt: vault)

        XCTAssertEqual(served.status, 200)
        XCTAssertEqual(served.text, "plain text")
        XCTAssertEqual(served.headers["Content-Type"], "text/plain")
        XCTAssertEqual(served.headers["Content-Length"], "10")
        XCTAssertEqual(served.headers["Access-Control-Allow-Origin"], "graphite-plugins://runtime")
        XCTAssertEqual(served.headers["Cache-Control"], "no-cache")
    }

    func testPercentEscapesInAnAddressAreDecodedOnceAndTheQueryIsIgnored() async throws {
        let vault = try makeVault(files: [
            "100%.txt": "one hundred percent",
            "100%25.txt": "the name holds an escape",
            "A b/ü.txt": "spaces and an umlaut",
            "Notes/Plain.txt": "plain text",
        ])

        let percent = try await serve("graphite-plugins://vault/100%25.txt", vaultAt: vault)
        XCTAssertEqual(percent.text, "one hundred percent", "%25 is one percent sign, not decoded a second time")
        let escapeInName = try await serve("graphite-plugins://vault/100%2525.txt", vaultAt: vault)
        XCTAssertEqual(escapeInName.text, "the name holds an escape")
        let encodedName = try await serve("graphite-plugins://vault/A%20b/%C3%BC.txt", vaultAt: vault)
        XCTAssertEqual(encodedName.text, "spaces and an umlaut")
        let withModifiedTime = try await serve("graphite-plugins://vault/Notes/Plain.txt?1700000000000", vaultAt: vault)
        XCTAssertEqual(withModifiedTime.text, "plain text", "The query only changes the address the page caches by.")
    }

    func testFoldersMissingFilesAndPathsLeavingTheVaultAreAnswered404() async throws {
        let vault = try makeVault(files: ["Notes/Plain.txt": "plain text"])
        let outsideName = "\(vault.lastPathComponent)-outside.txt"
        let outsideFile = vault.deletingLastPathComponent().appendingPathComponent(outsideName)
        try Data("outside".utf8).write(to: outsideFile)
        temporaryFolders.append(outsideFile)

        for refusedAddress in [
            "graphite-plugins://vault/Notes",
            "graphite-plugins://vault/Notes/Missing.txt",
            "graphite-plugins://vault/",
            "graphite-plugins://vault/Notes%2F..%2F..%2F\(outsideName)",
            "graphite-plugins://vault/..%2F\(outsideName)",
            "graphite-plugins://elsewhere/Notes/Plain.txt",
        ] {
            let refused = try await serve(refusedAddress, vaultAt: vault)
            XCTAssertEqual(refused.status, 404, refusedAddress)
            XCTAssertEqual(refused.body, Data(), refusedAddress)
        }
        let staysInside = try await serve("graphite-plugins://vault/Notes%2F..%2FNotes%2FPlain.txt", vaultAt: vault)
        XCTAssertEqual(staysInside.text, "plain text", "A path that goes up and comes back is the file it ends at.")
    }

    func testTheRuntimeHostServesTheRuntimeFilesAndNotThoseOutsideItsFolder() async throws {
        let vault = try makeVault(files: [:])

        let script = try await serve("graphite-plugins://runtime/community-plugin-runtime-foundation.js", vaultAt: vault)
        XCTAssertEqual(script.status, 200)
        XCTAssertTrue(script.text?.contains("GraphitePluginRuntime") == true)
        XCTAssertEqual(script.headers["Access-Control-Allow-Origin"], "graphite-plugins://runtime")
        let page = try await serve(try XCTUnwrap(CommunityPluginSchemeHandler.runtimePageAddress).absoluteString, vaultAt: vault)
        XCTAssertEqual(page.status, 200)
        XCTAssertEqual(page.headers["Content-Type"], "text/html")
        for refusedAddress in ["graphite-plugins://runtime/%2E%2E%2FCommunityPluginHost.swift", "graphite-plugins://runtime/Vendor", "graphite-plugins://runtime/", "graphite-plugins://runtime/Missing.js"] {
            let refused = try await serve(refusedAddress, vaultAt: vault)
            XCTAssertEqual(refused.status, 404, refusedAddress)
        }
    }

    func testThePluginsPageLoadsAVaultFileFromItsAddressThroughTheSchemeHandler() async throws {
        let vault = try makeVault(files: ["Notes/Plain.txt": "plain text"])
        let webView = try await runtimePage(servingVaultAt: vault)

        let fetched = try await fetch("graphite-plugins://vault/Notes/Plain.txt?1", in: webView)
        XCTAssertTrue(fetched.isServed)
        XCTAssertEqual(fetched.text, "plain text")
        let refused = try await fetch("graphite-plugins://vault/Notes/Missing.txt", in: webView)
        XCTAssertFalse(refused.isServed)
    }

    func testThePluginsGetTheVaultAddressPrefixAndFormAFilesAddressFromIt() async throws {
        let source = """
        'use strict';
        const { Plugin } = require('obsidian');
        module.exports = class ResourcePlugin extends Plugin { onload() {} };
        """
        let workspace = try await testBed.workspaceWithRunningPlugins([("resource-plugin", source)], files: ["A b/ü.png": "picture"])
        let host = workspace.communityPlugins

        let address = try await testBed.evaluate("return app.vault.adapter.getResourcePath('A b/ü.png');", in: host) as? String
        XCTAssertEqual(address, "graphite-plugins://vault/A%20b/%C3%BC.png")
        let prefix = try await testBed.evaluate("return GraphitePluginRuntime.obsidianModule.Platform.resourcePathPrefix;", in: host) as? String
        XCTAssertEqual(prefix, CommunityPluginSchemeHandler.resourcePathPrefix)
        let timedAddress = try await testBed.evaluate("const file = app.vault.getFileByPath('A b/ü.png'); return app.vault.getResourcePath(file);", in: host) as? String
        let queryText = try XCTUnwrap(timedAddress?.split(separator: "?", maxSplits: 1).last.map(String.init))
        XCTAssertNotNil(Double(queryText), "The query is the file's modification time in milliseconds.")
        let fetched = try await fetch(try XCTUnwrap(address), in: try XCTUnwrap(host.webView))
        XCTAssertEqual(fetched.text, "picture", "The address a plugin is given loads the file in the plugins' own page.")
    }

    // MARK: Helpers

    private struct FetchResult {
        let isServed: Bool
        let text: String?
    }

    /// What the scheme handler answered a request with.
    private struct ServedAnswer {
        let status: Int
        let headers: [String: String]
        let body: Data
        var text: String? { String(data: body, encoding: .utf8) }
    }

    /// Asks the scheme handler for `address` the way WebKit does, and waits for its answer.
    private func serve(_ address: String, vaultAt vault: URL) async throws -> ServedAnswer {
        let handler = CommunityPluginSchemeHandler(vaultRoot: vault)
        let task = RecordingSchemeTask(request: URLRequest(url: try XCTUnwrap(URL(string: address))))
        handler.webView(WKWebView(), start: task)
        await task.waitUntilFinished()
        return ServedAnswer(status: task.response?.statusCode ?? 0, headers: task.response?.allHeaderFields as? [String: String] ?? [:], body: task.body)
    }

    private func makeVault(files: [String: String]) throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("SchemeHandlerVault-\(UUID().uuidString)").resolvingSymlinksInPath()
        temporaryFolders.append(vault)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        for (relativePath, text) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: location)
        }
        return vault
    }

    /// The runtime's page in a web view whose scheme handler serves `vault`.
    private func runtimePage(servingVaultAt vault: URL) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(CommunityPluginSchemeHandler(vaultRoot: vault), forURLScheme: CommunityPluginSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        loadedWebViews.append(webView)
        let loadWaiter = PageLoadWaiter()
        webView.navigationDelegate = loadWaiter
        webView.load(URLRequest(url: try XCTUnwrap(CommunityPluginSchemeHandler.runtimePageAddress)))
        try await loadWaiter.waitForLoad()
        return webView
    }

    /// What the page gets when it fetches `address`; a failed fetch (a refused address) is not served.
    private func fetch(_ address: String, in webView: WKWebView) async throws -> FetchResult {
        let script = """
        try {
            const response = await fetch(address);
            const text = new TextDecoder().decode(new Uint8Array(await response.arrayBuffer()));
            return { isServed: response.ok, text };
        } catch (error) {
            return { isServed: false };
        }
        """
        let answer = try await webView.callAsyncJavaScript(script, arguments: ["address": address], in: nil, contentWorld: .page) as? [String: Any]
        let fields = try XCTUnwrap(answer)
        return FetchResult(isServed: fields["isServed"] as? Bool == true, text: fields["text"] as? String)
    }
}

/// Waits for a web view's first page to finish loading.
@MainActor
private final class PageLoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?

    func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in self.continuation = continuation }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// A request the scheme handler is asked to answer, recording the answer it gives.
private final class RecordingSchemeTask: NSObject, WKURLSchemeTask, @unchecked Sendable {
    let request: URLRequest
    // The handler answers from the main actor, the test waits from it too; the lock keeps the state whole.
    private let lock = NSLock()
    private var recordedResponse: HTTPURLResponse?
    private var recordedBody = Data()
    private var isFinished = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(request: URLRequest) {
        self.request = request
    }

    var response: HTTPURLResponse? { lock.withLock { recordedResponse } }
    var body: Data { lock.withLock { recordedBody } }

    func waitUntilFinished() async {
        await withCheckedContinuation { continuation in
            let isAlreadyFinished = lock.withLock { () -> Bool in
                if !isFinished { waiter = continuation }
                return isFinished
            }
            if isAlreadyFinished { continuation.resume() }
        }
    }

    func didReceive(_ response: URLResponse) {
        lock.withLock { recordedResponse = response as? HTTPURLResponse }
    }

    func didReceive(_ data: Data) {
        lock.withLock { recordedBody.append(data) }
    }

    func didFinish() {
        finish()
    }

    func didFailWithError(_ error: any Error) {
        finish()
    }

    private func finish() {
        let pendingWaiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            isFinished = true
            defer { waiter = nil }
            return waiter
        }
        pendingWaiter?.resume()
    }
}
