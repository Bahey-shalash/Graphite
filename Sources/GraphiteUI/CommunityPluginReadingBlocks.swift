import SwiftUI
import WebKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#endif

/// A code block a plugin draws in the reading view, as the note has it.
struct CommunityPluginCodeBlockRequest: Hashable, Sendable {
    let language: String
    let source: String
    /// The note the block is written in.
    let note: VaultPath
    /// The zero-based line of the block's opening fence in `note`, nil when not known.
    let firstLine: Int?
    /// Lines the block spans, fences included.
    let lineCount: Int
}

/// The last copy of a block a plugin drew, with the height it was shown at.
struct CommunityPluginCodeBlockCopy {
    let html: String
    var height: CGFloat
}

extension EnvironmentValues {
    /// Draws plugins' code blocks in the reading view; nil where plugins do not draw them,
    /// which shows such blocks as code.
    @Entry var communityPluginCodeBlocks: CommunityPluginHost? = nil
}

/// One code block shown in a note: its copy of what the plugin drew, kept current. The
/// plugin draws the block in the runtime's page (`community-plugin-runtime-reading.js`);
/// this holds the copy Graphite shows and sends taps back.
@MainActor @Observable
final class CommunityPluginShownCodeBlock {
    enum Appearance: Equatable {
        case drawing
        case drawn(html: String)
        case failed(String)
    }

    /// How long the plugin has to draw a block before the note says it did not.
    static let drawingTimeout: Duration = .seconds(20)
    /// How long a tap waits for the plugin before it is given up.
    static let tapTimeout: Duration = .seconds(5)

    let blockIdentifier = UUID().uuidString
    private(set) var appearance: Appearance = .drawing
    /// The copy's height in points, as its web view measured it.
    var height: CGFloat = 0
    @ObservationIgnored private weak var host: CommunityPluginHost?
    @ObservationIgnored private var request: CommunityPluginCodeBlockRequest?

    init(host: CommunityPluginHost) {
        self.host = host
    }

    /// The vault's folder, whose files a block's pictures load from.
    var vaultRoot: URL? { host?.workspace?.folderAccess?.root }

    /// Asks the plugin to draw the block, showing the last copy meanwhile.
    func draw(_ request: CommunityPluginCodeBlockRequest, width: CGFloat) async {
        guard let host else { return }
        // Drawing again under the same identifier replaces the plugin's earlier block there;
        // a separate release could arrive after this drawing and remove it.
        self.request = request
        host.shownCodeBlocks[blockIdentifier] = self
        if let lastCopy = host.lastCodeBlockCopies[request] {
            appearance = .drawn(html: lastCopy.html)
            height = lastCopy.height
        } else {
            appearance = .drawing
        }
        var message: [String: Any] = [
            "operation": "codeBlock.render", "blockIdentifier": blockIdentifier, "language": request.language, "source": request.source,
            "sourcePath": request.note.rawValue, "lineCount": request.lineCount, "width": Double(max(width, 200)),
        ]
        if let firstLine = request.firstLine { message["firstLine"] = firstLine }
        // `getSectionInfo` gives a plugin the whole note; only an open note's text is at hand.
        if let noteText = host.openNoteText(at: request.note), (noteText as NSString).length <= 1_048_576 { message["noteText"] = noteText }
        do {
            let answer = try await host.send(message, timeout: Self.drawingTimeout)
            guard self.request == request else { return }
            if let styles = answer["styles"] as? String { host.updatePluginStyleSheets(styles) }
            if answer["isDrawn"] as? Bool == true, let html = answer["html"] as? String {
                receive(html: html)
            } else {
                appearance = .failed(answer["message"] as? String ?? "The plugin did not draw this block.")
            }
        } catch {
            guard self.request == request else { return }
            appearance = .failed(error.localizedDescription)
        }
    }

    func receive(html: String) {
        appearance = .drawn(html: html)
        if let request { host?.lastCodeBlockCopies[request] = CommunityPluginCodeBlockCopy(html: html, height: height) }
    }

    func heightDidChange(_ newHeight: CGFloat) {
        guard abs(newHeight - height) >= 0.5 else { return }
        height = newHeight
        if let request { host?.lastCodeBlockCopies[request]?.height = newHeight }
    }

    /// A tap on the copy, as the path of element positions from the block down to the
    /// element tapped, delivered to that element in the plugin's block.
    func tap(elementPath: [Int]) {
        deliver(["eventType": "tap", "elementPath": elementPath])
    }

    /// Text typed into a field of the copy (a query's filter), given to the plugin's field.
    func enter(_ value: String, elementPath: [Int]) {
        deliver(["eventType": "input", "elementPath": elementPath, "value": value])
    }

    private func deliver(_ event: [String: Any]) {
        guard let host else { return }
        var message = event
        message["operation"] = "codeBlock.event"
        message["blockIdentifier"] = blockIdentifier
        Task {
            guard let answer = try? await host.send(message, timeout: Self.tapTimeout) else { return }
            if let html = answer["html"] as? String { receive(html: html) }
        }
    }

    /// The note no longer shows the block: the plugin's block and what it keeps up to date go.
    func release() {
        guard let host, request != nil else { return }
        request = nil
        host.shownCodeBlocks[blockIdentifier] = nil
        let blockIdentifier = blockIdentifier
        Task { _ = try? await host.send(["operation": "codeBlock.release", "blockIdentifier": blockIdentifier], timeout: .seconds(5)) }
    }
}

extension CommunityPluginHost {
    /// The text of a note open in Graphite, as its editor holds it.
    func openNoteText(at path: VaultPath) -> String? {
        workspace?.openMarkdownSession(at: path)?.text
    }

    /// The name of the plugin that draws a code block language, for what the note shows
    /// while it draws.
    func pluginName(drawingLanguage language: String) -> String? {
        codeBlockLanguageOwners[language].flatMap(pluginName(of:))
    }
}

/// A plugin's code block in the reading view: what the plugin drew, shown in a web view
/// that runs no script of the page, sized to its content.
struct CommunityPluginCodeBlockView: View {
    let host: CommunityPluginHost
    let request: CommunityPluginCodeBlockRequest
    let textSize: Double
    @State private var shownBlock: CommunityPluginShownCodeBlock?
    @State private var availableWidth: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accent) private var accent

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in availableWidth = width }
            .task(id: DrawingKey(request: request, hasWidth: availableWidth > 0)) {
                guard availableWidth > 0 else { return }
                let block = shownBlock ?? CommunityPluginShownCodeBlock(host: host)
                shownBlock = block
                await block.draw(request, width: availableWidth)
            }
            .onDisappear {
                shownBlock?.release()
                shownBlock = nil
            }
    }

    /// Drawn again when the block's text changes, or once its width is known.
    private struct DrawingKey: Equatable {
        let request: CommunityPluginCodeBlockRequest
        let hasWidth: Bool
    }

    @ViewBuilder private var content: some View {
        switch shownBlock?.appearance ?? .drawing {
        case .drawing:
            HStack(spacing: 8) {
                ProgressView()
                Text(drawingDescription).font(.callout).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .drawn(let html):
            if let shownBlock {
                CommunityPluginCodeBlockDisplay(block: shownBlock, html: html, styleSheets: host.pluginStyleSheets,
                                                isDark: colorScheme == .dark, textSize: textSize, accentHex: accent.sRGBHex)
                    .frame(height: max(shownBlock.height, 1))
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
                Text(request.source)
                    .font(.system(size: textSize * 0.85, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var drawingDescription: String {
        if let pluginName = host.pluginName(drawingLanguage: request.language) { return "\(pluginName) is drawing this block…" }
        return "Drawing this block…"
    }
}

/// The page a block's copy is shown in. It loads only the runtime's style sheet and the
/// vault's files through the plugin scheme; script in the copy never runs
/// (`allowsContentJavaScript` is off), and Graphite's own script, in its own content world,
/// measures the page and reports taps.
enum CommunityPluginCodeBlockPage {
    static let messageHandlerName = "graphiteCodeBlock"

    static var shell: String {
        """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="community-plugin-runtime.css">
        <style id="graphite-plugin-styles"></style>
        <style>
        html, body { background: transparent !important; margin: 0; padding: 0; overflow-x: auto; overflow-y: hidden; }
        body { -webkit-user-select: text; }
        .graphite-code-block-root { padding: 1px 0; }
        .graphite-code-block-root > * { margin-top: 0; }
        </style>
        </head><body class="theme-light is-mobile is-ios"><div class="markdown-preview-view markdown-rendered graphite-code-block-root"></div></body></html>
        """
    }

    /// Runs in Graphite's content world: shows copies, reports the page's height, and turns
    /// taps into element paths, cancelling them here so nothing happens twice.
    static let script = """
    (function () {
        'use strict';
        const handler = window.webkit.messageHandlers.graphiteCodeBlock;
        function root() { return document.querySelector('.graphite-code-block-root'); }
        function blockElement() { return root() && root().firstElementChild; }
        /// Element positions from the block's element down to `element`, which is how the
        /// plugin's block finds the same element.
        function pathTo(element) {
            const path = [];
            while (element && element !== blockElement()) {
                path.unshift(Array.prototype.indexOf.call(element.parentElement.children, element));
                element = element.parentElement;
            }
            return path;
        }
        /// Brings `current` to what `wanted` holds by changing only what differs, so a field
        /// being typed in stays the same element, keeps its text and caret, and the keyboard
        /// keeps every key; replacing the page's HTML would drop keys typed meanwhile.
        function morph(current, wanted) {
            const currentChildren = Array.from(current.childNodes);
            const wantedChildren = Array.from(wanted.childNodes);
            wantedChildren.forEach((wantedChild, position) => {
                const currentChild = currentChildren[position];
                if (!currentChild) { current.appendChild(wantedChild.cloneNode(true)); return; }
                const isSameKind = currentChild.nodeType === wantedChild.nodeType && currentChild.nodeName === wantedChild.nodeName;
                if (!isSameKind) { current.replaceChild(wantedChild.cloneNode(true), currentChild); return; }
                if (currentChild.nodeType !== Node.ELEMENT_NODE) {
                    if (currentChild.nodeValue !== wantedChild.nodeValue) currentChild.nodeValue = wantedChild.nodeValue;
                    return;
                }
                const isBeingTyped = currentChild === document.activeElement && 'value' in currentChild;
                for (const attribute of Array.from(currentChild.attributes)) {
                    if (!wantedChild.hasAttribute(attribute.name)) currentChild.removeAttribute(attribute.name);
                }
                for (const attribute of Array.from(wantedChild.attributes)) {
                    if (isBeingTyped && attribute.name === 'value') continue;
                    if (currentChild.getAttribute(attribute.name) !== attribute.value) currentChild.setAttribute(attribute.name, attribute.value);
                }
                if (currentChild.tagName === 'INPUT') {
                    if (currentChild.type === 'checkbox' || currentChild.type === 'radio') currentChild.checked = wantedChild.hasAttribute('checked');
                    else if (!isBeingTyped) currentChild.value = wantedChild.getAttribute('value') || '';
                }
                if (currentChild.tagName === 'TEXTAREA' && !isBeingTyped) currentChild.value = wantedChild.textContent;
                if (!isBeingTyped) morph(currentChild, wantedChild);
            });
            for (const extraChild of currentChildren.slice(wantedChildren.length)) extraChild.remove();
        }
        let lastHeight = -1;
        function reportHeight() {
            const element = root();
            const height = Math.ceil(element ? element.getBoundingClientRect().height : document.documentElement.scrollHeight);
            if (height !== lastHeight) { lastHeight = height; handler.postMessage({ kind: 'height', height }); }
        }
        window.GraphiteCodeBlock = {
            show(html, styleSheets, isDark, textSize, accent) {
                const styleElement = document.getElementById('graphite-plugin-styles');
                if (styleElement.textContent !== styleSheets) styleElement.textContent = styleSheets;
                document.body.classList.toggle('theme-dark', isDark);
                document.body.classList.toggle('theme-light', !isDark);
                document.body.style.setProperty('--font-text-size', textSize + 'px');
                if (accent) {
                    document.body.style.setProperty('--color-accent', accent);
                    document.body.style.setProperty('--interactive-accent', accent);
                    document.body.style.setProperty('--text-accent', accent);
                }
                const element = root();
                if (element.innerHTML !== html) {
                    const template = document.createElement('template');
                    template.innerHTML = html;
                    morph(element, template.content);
                }
                reportHeight();
            },
        };
        new ResizeObserver(reportHeight).observe(document.documentElement);
        document.addEventListener('click', (event) => {
            const element = event.target instanceof Element ? event.target : null;
            if (!blockElement() || !element || !blockElement().contains(element)) return;
            // Typing goes to text fields here; the plugin hears the text, not the tap.
            if (element.matches('input:not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]), textarea, select')) return;
            event.preventDefault();
            event.stopPropagation();
            handler.postMessage({ kind: 'tap', path: pathTo(element) });
        }, true);
        function forwardText(event) {
            const element = event.target instanceof Element ? event.target : null;
            if (!blockElement() || !element || !blockElement().contains(element) || !('value' in element)) return;
            if (element.type === 'checkbox' || element.type === 'radio') return;
            handler.postMessage({ kind: 'input', path: pathTo(element), value: String(element.value) });
        }
        document.addEventListener('input', forwardText, true);
        document.addEventListener('change', forwardText, true);
    })();
    """
}

/// Receives a block page's messages. Separate from the view, because WebKit keeps its
/// message handlers strongly.
@MainActor
final class CommunityPluginCodeBlockDisplayCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var block: CommunityPluginShownCodeBlock?
    var isLoaded = false
    /// What the page should show once it has loaded.
    var pendingPresentation: [String: Any]?
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "height":
            if let height = body["height"] as? Double { block?.heightDidChange(CGFloat(height)) }
        case "tap":
            if let path = body["path"] as? [Int] { block?.tap(elementPath: path) }
        case "input":
            if let path = body["path"] as? [Int], let value = body["value"] as? String { block?.enter(value, elementPath: path) }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        isLoaded = true
        if let pendingPresentation { present(pendingPresentation) }
    }

    /// Only the block's own page loads; links are followed by the plugin's block.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard !isLoaded, navigationAction.targetFrame?.isMainFrame == true else { return .cancel }
        return .allow
    }

    func present(_ presentation: [String: Any]) {
        pendingPresentation = presentation
        guard isLoaded, let webView else { return }
        webView.callAsyncJavaScript("GraphiteCodeBlock.show(html, styleSheets, isDark, textSize, accent)", arguments: presentation,
                                    in: nil, in: .defaultClient) { _ in }
    }
}

/// The web view that shows a block's copy.
@MainActor
struct CommunityPluginCodeBlockDisplay {
    let block: CommunityPluginShownCodeBlock
    let html: String
    let styleSheets: String
    let isDark: Bool
    let textSize: Double
    let accentHex: String?

    /// One store for every block page: no page keeps anything, and sharing it lets WebKit
    /// share its processes between blocks.
    @MainActor static let dataStore = WKWebsiteDataStore.nonPersistent()

    func makeCoordinator() -> CommunityPluginCodeBlockDisplayCoordinator { CommunityPluginCodeBlockDisplayCoordinator() }

    @MainActor private func makeWebView(coordinator: CommunityPluginCodeBlockDisplayCoordinator, vaultRoot: URL?) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.dataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        if let vaultRoot {
            configuration.setURLSchemeHandler(CommunityPluginSchemeHandler(vaultRoot: vaultRoot), forURLScheme: CommunityPluginSchemeHandler.scheme)
        }
        let script = WKUserScript(source: CommunityPluginCodeBlockPage.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(coordinator, contentWorld: .defaultClient, name: CommunityPluginCodeBlockPage.messageHandlerName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        #if canImport(UIKit)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // The note scrolls; the block only shows what it holds.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        #if DEBUG
        webView.isInspectable = true
        #endif
        coordinator.webView = webView
        coordinator.block = block
        if let baseAddress = URL(string: CommunityPluginSchemeHandler.scheme + "://" + CommunityPluginSchemeHandler.runtimeHost + "/") {
            webView.loadHTMLString(CommunityPluginCodeBlockPage.shell, baseURL: baseAddress)
        }
        return webView
    }

    @MainActor private func update(_ coordinator: CommunityPluginCodeBlockDisplayCoordinator) {
        coordinator.block = block
        coordinator.present(["html": html, "styleSheets": styleSheets, "isDark": isDark, "textSize": textSize, "accent": accentHex ?? ""])
    }

    @MainActor private static func dismantle(_ webView: WKWebView) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.stopLoading()
    }
}

#if canImport(UIKit)
extension CommunityPluginCodeBlockDisplay: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator, vaultRoot: block.vaultRoot)
        update(context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(context.coordinator)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: CommunityPluginCodeBlockDisplayCoordinator) {
        dismantle(webView)
    }
}
#elseif canImport(AppKit)
extension CommunityPluginCodeBlockDisplay: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator, vaultRoot: block.vaultRoot)
        update(context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(context.coordinator)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: CommunityPluginCodeBlockDisplayCoordinator) {
        dismantle(webView)
    }
}
#endif
