#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Plugins' links in WebKit, in a window, with the plugins running. In a copy of a plugin's
/// block, the pointer moving onto an element the plugin listens on asks, through the plugin's
/// own `hover-link`, for a card beside that element, and moving onto an internal link the
/// plugin drew asks for that link's card, as a link of the reading view does. In a view shown
/// live, the plugin's `hover-link` asks for a card beside its element, which closes when the
/// pointer leaves it.
@MainActor
final class CommunityPluginLinkHoversInWebKitTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
        windows = []
        await testBed.tearDown()
    }

    /// Its `rows` blocks and its view have a row that asks to preview `Other` when the pointer
    /// comes onto it; its blocks also have an internal link to `Notes/Third` it does not listen on.
    private static let pluginSource = """
    'use strict';
    const { Plugin, ItemView } = require('obsidian');
    function addRow(plugin, element) {
        const row = element.createDiv({ cls: 'row', text: 'Other' });
        row.addEventListener('mouseover', (event) => {
            plugin.app.workspace.trigger('hover-link', { event, source: 'rows', hoverParent: plugin, targetEl: row, linktext: 'Other' });
        });
    }
    class RowsView extends ItemView {
        constructor(leaf, plugin) { super(leaf); this.plugin = plugin; }
        getViewType() { return 'rows-view'; }
        getDisplayText() { return 'Rows'; }
        async onOpen() { addRow(this.plugin, this.contentEl); }
    }
    module.exports = class RowsPlugin extends Plugin {
        onload() {
            this.registerView('rows-view', (leaf) => new RowsView(leaf, this));
            this.addCommand({ id: 'open-view', name: 'Open view', callback: async () => {
                await this.app.workspace.getLeaf('tab').setViewState({ type: 'rows-view', active: true });
            } });
            this.registerMarkdownCodeBlockProcessor('rows', (source, element) => {
                addRow(this, element);
                element.createEl('a', { cls: 'internal-link', text: 'Third', attr: { 'data-href': 'Notes/Third', href: 'Notes/Third' } });
            });
        }
    };
    """

    private func waitingRequest(_ cards: LinkPreviewModel) -> LinkPreviewRequest? {
        if case .waiting(let request) = cards.phase { request } else { nil }
    }

    /// `view` with the window's cards, in a transparent window on screen.
    private func showInWindow(_ view: some View, cards: LinkPreviewModel) -> NSView {
        let hostingView = NSHostingView(rootView: view.environment(\.linkPreviews, cards).frame(width: 400, height: 200))
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = hostingView
        window.showInvisibly()
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    /// Gives the copy's script animation frames from a timer: the test's window is transparent,
    /// which WebKit treats as hidden and gives no frames, and the copy sends a hover on the
    /// frame after the move.
    private func giveAnimationFrames(to webView: WKWebView) async throws {
        let script = """
        window.requestAnimationFrame = (callback) => setTimeout(() => callback(performance.now()), 16);
        window.cancelAnimationFrame = (frame) => clearTimeout(frame);
        """
        _ = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
    }

    /// Moves a mouse pointer onto the first element `selector` finds in the copy's page, as
    /// WebKit reports it to the copy's own script.
    private func movePointer(onto selector: String, in webView: WKWebView) async throws {
        let script = """
        const element = document.querySelector(selector);
        const bounds = element.getBoundingClientRect();
        element.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, pointerType: 'mouse', buttons: 0, clientX: bounds.left + 2, clientY: bounds.top + 2 }));
        """
        _ = try await webView.callAsyncJavaScript(script, arguments: ["selector": selector], in: nil, contentWorld: .defaultClient)
    }

    func testThePointerOnAPluginsElementOrOnAnInternalLinkInACopyAsksForItsCardBesideIt() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("rows-plugin", Self.pluginSource)], files: ["Note.md": "```rows\n```\n"])
        let host = workspace.communityPlugins
        try await waitUntil("the plugin draws rows") { host.codeBlockLanguages.contains("rows") }
        let block = CommunityPluginShownCodeBlock(host: host)
        await block.draw(CommunityPluginReadingBlockRequest(kind: .codeBlock(language: "rows"), source: "", note: try VaultPath("Note.md"), firstLine: 0, lineCount: 2),
                         width: 400)
        guard case .drawn(let html) = block.appearance else { return XCTFail("The block is drawn: \(block.appearance)") }

        let cards = LinkPreviewModel(clock: ManualClock(), announceHover: { _ in })
        let display = CommunityPluginCodeBlockDisplay(block: block, html: html, styleSheets: "", isDark: false, textSize: 16, accentHex: nil)
        let hostingView = showInWindow(display, cards: cards)
        let webView = try XCTUnwrap(Self.firstWebView(in: hostingView), "The copy builds its web view.")
        try await waitUntil("the copy shows the plugin's row") {
            (try? await webView.callAsyncJavaScript("return document.querySelector('.row') !== null;", arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
        }
        try await giveAnimationFrames(to: webView)

        try await movePointer(onto: ".row", in: webView)
        try await waitUntil("the plugin's link asks for its card") { self.waitingRequest(cards)?.target == "Other" }
        let onRow = try XCTUnwrap(waitingRequest(cards))
        XCTAssertEqual(onRow.source, .plugin)
        XCTAssertEqual(onRow.sourceNote, .root, "The plugin named no source path.")
        XCTAssertGreaterThan(onRow.anchor.width, 0, "The card goes beside the row, measured in the copy.")

        try await movePointer(onto: "a.internal-link", in: webView)
        try await waitUntil("the drawn link asks for its card") { self.waitingRequest(cards)?.target == "Notes/Third" }
        XCTAssertEqual(try XCTUnwrap(waitingRequest(cards)).sourceNote, try VaultPath("Note.md"), "A drawn link starts from the block's note.")
        block.release()
    }

    func testThePointerOnAPluginsElementInALiveViewAsksForItsCardAndLeavingItClosesIt() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("rows-plugin", Self.pluginSource)])
        let host = workspace.communityPlugins
        try await testBed.runCommand("open-view", of: "rows-plugin", in: workspace)
        try await waitUntil("the view opens in a tab") { workspace.tabDocuments.values.contains { document in document.pluginViewIdentifier != nil } }
        let viewIdentifier = try XCTUnwrap(workspace.tabDocuments.values.compactMap(\.pluginViewIdentifier).first)

        let cards = LinkPreviewModel(clock: ManualClock(), announceHover: { _ in })
        let hostingView = showInWindow(CommunityPluginLiveViewContent(host: host, viewIdentifier: viewIdentifier), cards: cards)
        try await waitUntil("the view is shown live in the window") {
            guard host.liveViewIdentifier == viewIdentifier, host.webView?.window === hostingView.window else { return false }
            return (try? await self.testBed.evaluate("return document.querySelector('.graphite-live-view .row') !== null;", in: host)) as? Bool == true
        }

        _ = try await testBed.evaluate("document.querySelector('.graphite-live-view .row').dispatchEvent(new MouseEvent('mouseover', { bubbles: true })); return true;", in: host)
        try await waitUntil("the plugin's link asks for its card") { self.waitingRequest(cards)?.target == "Other" }
        let request = try XCTUnwrap(waitingRequest(cards))
        XCTAssertEqual(request.source, .plugin)
        XCTAssertGreaterThan(request.anchor.width, 0)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 400, height: 200).intersects(request.anchor), "The card goes beside the row, in the window showing the view.")

        _ = try await testBed.evaluate("document.querySelector('.graphite-live-view .row').dispatchEvent(new MouseEvent('mouseleave')); return true;", in: host)
        try await waitUntil("leaving the row stops its card") { if case .hidden = cards.phase { true } else { false } }
    }

    private static func firstWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = firstWebView(in: subview) { return found }
        }
        return nil
    }
}
#endif
