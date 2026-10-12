import Foundation
import WebKit
import UniformTypeIdentifiers
import GraphiteCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The plugin runtime's page and the vault's files as the plugin web view loads them:
/// `graphite-plugins://runtime/…` from the app's bundle, and `graphite-plugins://vault/…`
/// (Obsidian's `getResourcePath`) from the open vault, read-only. Nothing else is served.
@MainActor
final class CommunityPluginSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "graphite-plugins"
    static let runtimeHost = "runtime"
    static let vaultHost = "vault"
    static var runtimePageAddress: URL? { URL(string: scheme + "://" + runtimeHost + "/index.html") }
    static var resourcePathPrefix: String { scheme + "://" + vaultHost + "/" }

    /// The largest vault file a plugin view can load as a resource.
    private static let maximumResourceBytes = 256 * 1_048_576

    private let runtimeFolder: URL?
    private let vaultRoot: URL
    /// Tasks WebKit has not stopped; a stopped task must not be answered.
    private var activeTasks: Set<ObjectIdentifier> = []

    init(vaultRoot: URL) {
        self.vaultRoot = vaultRoot
        runtimeFolder = Bundle.module.url(forResource: "CommunityPluginRuntime", withExtension: nil)
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let taskIdentifier = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(taskIdentifier)
        guard let requestedAddress = urlSchemeTask.request.url, let location = location(for: requestedAddress) else {
            fail(urlSchemeTask, status: 404)
            return
        }
        let maximumBytes = Self.maximumResourceBytes
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumBytes else { return nil }
                return try? Data(contentsOf: location, options: .mappedIfSafe)
            }.value
            guard self.activeTasks.contains(taskIdentifier) else { return }
            guard let data else {
                self.fail(urlSchemeTask, status: 404)
                return
            }
            let mimeType = UTType(filenameExtension: location.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let headers = [
                "Content-Type": mimeType,
                "Content-Length": String(data.count),
                // Plugin views fetch vault resources from the runtime's own origin.
                "Access-Control-Allow-Origin": Self.scheme + "://" + Self.runtimeHost,
                "Cache-Control": "no-cache",
            ]
            if let response = HTTPURLResponse(url: requestedAddress, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            }
            self.activeTasks.remove(taskIdentifier)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    private func fail(_ urlSchemeTask: any WKURLSchemeTask, status: Int) {
        let taskIdentifier = ObjectIdentifier(urlSchemeTask)
        guard activeTasks.contains(taskIdentifier) else { return }
        activeTasks.remove(taskIdentifier)
        if let address = urlSchemeTask.request.url, let response = HTTPURLResponse(url: address, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) {
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
        } else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    /// The file an address names, if it is one this handler serves.
    private func location(for address: URL) -> URL? {
        // `URL.path` is already percent-decoded; decoding again would misread “100%.png”.
        let relativePath = String(address.path.drop { character in character == "/" })
        switch address.host {
        case Self.runtimeHost:
            guard let runtimeFolder, let path = try? VaultPath(relativePath), !path.rawValue.isEmpty,
                  let location = try? path.url(in: runtimeFolder) else { return nil }
            return location
        case Self.vaultHost:
            // Vault paths go through `VaultPath`, which keeps them, and their symbolic
            // links, inside the vault.
            guard let path = try? VaultPath(relativePath), !path.rawValue.isEmpty, let location = try? path.url(in: vaultRoot) else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
            return location
        default:
            return nil
        }
    }
}

/// Receives the runtime's messages and the web view's navigation, and passes them to the
/// host. A separate object, because WebKit keeps its message handlers strongly and the
/// host must be able to go away with its vault.
@MainActor
final class CommunityPluginMessageReceiver: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    weak var host: CommunityPluginHost?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let host else { return (["failure": ["kind": "unavailable", "message": "Graphite closed this vault's plugins."]], nil) }
        return (await host.answer(message.body), nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        host?.runtimePageDidLoad(in: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
        host?.runtimePageDidFail(in: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        host?.runtimePageDidFail(in: webView, error: error)
    }

    /// iOS ends a web view's content process under memory pressure; the plugins start again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        host?.runtimeProcessDidEnd(in: webView)
    }

    /// The runtime's page stays where it is. Web links plugins open go to the browser.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let address = navigationAction.request.url else { return .cancel }
        if address.scheme == CommunityPluginSchemeHandler.scheme { return navigationAction.targetFrame?.isMainFrame == false || address.host == CommunityPluginSchemeHandler.runtimeHost ? .allow : .cancel }
        if address.scheme == "about" { return .allow }
        if let scheme = address.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme), navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
            ExternalLinkOpener.open(address)
        }
        return .cancel
    }
}

enum ExternalLinkOpener {
    @MainActor static func open(_ address: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(address)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(address)
        #endif
    }
}
