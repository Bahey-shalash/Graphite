import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

private extension CommunityPluginHost {
    /// Delivers a message as WebKit would hand it over.
    func deliver(_ message: [String: Any]) async -> Any { await answer(message) }
}

/// Obsidian's `hover-link` between Graphite and plugins, through the host and a running
/// runtime: Graphite's hovers reach plugins that listen, a plugin's link in a copy comes back
/// with the hover the copy forwarded, and a live view's hovers find the window showing it.
@MainActor
final class CommunityPluginLinkHoversTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    /// Keeps the hovers it hears; its `rows` blocks ask to preview `Other` when the pointer
    /// comes onto a row, as Recent Files does.
    private static let pluginSource = """
    'use strict';
    const { Plugin } = require('obsidian');
    module.exports = class HoverPlugin extends Plugin {
        onload() {
            globalThis.heardHovers = [];
            this.registerEvent(this.app.workspace.on('hover-link', (hover) => {
                globalThis.heardHovers.push(hover.source + ' ' + hover.linktext + ' ' + hover.sourcePath + ' ' + hover.targetEl.getAttribute('data-href'));
            }));
            this.registerMarkdownCodeBlockProcessor('rows', (source, element) => {
                const row = element.createDiv({ cls: 'row', text: 'Other' });
                row.addEventListener('mouseover', (event) => {
                    this.app.workspace.trigger('hover-link', { event, source: 'rows', hoverParent: this, targetEl: row, linktext: 'Other' });
                });
            });
        }
    };
    """

    private func request(_ target: String, source: LinkPreviewSource) throws -> LinkPreviewRequest {
        LinkPreviewRequest(target: target, isWiki: true, sourceNote: try VaultPath("Note.md"), anchor: .zero, trigger: .hover, source: source)
    }

    func testGraphitesOwnHoversReachPluginsThatListenAndPagePreviewIsOnInTheRuntime() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("hover-plugin", Self.pluginSource)], files: ["Note.md": "See [[Other]].\n", "Other.md": "Other.\n"])
        let host = workspace.communityPlugins
        try await waitUntil("the host hears that a plugin listens") { host.hasHoverLinkListeners }
        let isPagePreviewOn = try await testBed.evaluate("return app.internalPlugins.getEnabledPluginById('page-preview') !== null;", in: host) as? Bool
        XCTAssertEqual(isPagePreviewOn, true, "The runtime knows the core plugin is on.")

        host.announceLinkHover(try request("Other", source: .editor))
        host.announceLinkHover(try request("Other#Plan", source: .plugin))
        host.announceLinkHover(try request("Note", source: .reading))
        try await waitUntil("the plugin hears both of Graphite's hovers") {
            (try await self.testBed.evaluate("return globalThis.heardHovers.length;", in: host) as? Int) == 2
        }
        let heard = try await testBed.evaluate("return globalThis.heardHovers;", in: host) as? [String]
        XCTAssertEqual(heard, ["editor Other Note.md Other", "preview Note Note.md Note"], "A plugin's own link is not sent back to plugins.")
    }

    func testAPluginsLinkInACopyComesBackWithTheHoverTheCopyForwarded() async throws {
        let workspace = try await testBed.workspaceWithRunningPlugins([("hover-plugin", Self.pluginSource)], files: ["Note.md": "```rows\n```\n"])
        let host = workspace.communityPlugins
        try await waitUntil("the plugin draws rows") { host.codeBlockLanguages.contains("rows") }
        let block = CommunityPluginShownCodeBlock(host: host)
        let blockRequest = CommunityPluginReadingBlockRequest(kind: .codeBlock(language: "rows"), source: "", note: try VaultPath("Note.md"), firstLine: 0, lineCount: 2)
        await block.draw(blockRequest, width: 400)
        guard case .drawn = block.appearance else { return XCTFail("The block is drawn: \(block.appearance)") }

        var answeredLinks: [CommunityPluginHoveredLink] = []
        block.forward("hover", details: ["path": [0], "x": 4.0, "y": 4.0], linkHovered: { link in answeredLinks.append(link) })
        try await waitUntil("the plugin's link comes back") { !answeredLinks.isEmpty }
        XCTAssertEqual(answeredLinks, [CommunityPluginHoveredLink(linktext: "Other", sourcePath: "")])
        XCTAssertEqual(block.linkSourceNote, try VaultPath("Note.md"))
        block.release()
    }

    func testTheHostKnowsWhetherPluginsListenForHoversAndALiveHoverNeedsItsViewShownLive() async throws {
        let host = CommunityPluginHost()
        _ = await host.deliver(["operation": "editor.listenersChanged", "hasHoverLinkListeners": true])
        XCTAssertTrue(host.hasHoverLinkListeners)

        let cards = LinkPreviewModel(clock: ManualClock(), announceHover: { _ in })
        host.useLinkPreviews(cards, forLiveView: "graphite-leaf-1")
        _ = await host.deliver(["operation": "hoverLink.show", "hoverNumber": 1, "leafIdentifier": "graphite-leaf-1", "linktext": "Other", "sourcePath": "",
                                "rect": ["x": 0, "y": 0, "width": 10, "height": 10] as [String: Double]])
        guard case .hidden = cards.phase else { return XCTFail("A view that is not shown live, in no window, shows no card.") }
        _ = await host.deliver(["operation": "hoverLink.end", "hoverNumber": 1])
        guard case .hidden = cards.phase else { return XCTFail() }
    }
}

/// The window's cards a live view's hovers are shown with, and the end of the hover that
/// asked for the card shown.
@MainActor
final class CommunityPluginLiveLinkHoversTests: XCTestCase {
    func testAViewsCardsAreThoseOfTheWindowShowingItAndOnlyTheLatestHoverEnds() throws {
        var hovers = CommunityPluginLiveLinkHovers()
        let cards = LinkPreviewModel(clock: ManualClock(), announceHover: { _ in })
        hovers.use(cards, forView: "leaf")
        XCTAssertTrue(hovers.linkPreviews(forView: "leaf") === cards)
        XCTAssertNil(hovers.linkPreviews(forView: "other"))

        let request = CommunityPluginHoveredLink(linktext: "Other", sourcePath: "").previewRequest(anchoredAt: CGRect(x: 1, y: 2, width: 3, height: 4))
        hovers.record(hoverNumber: 4, viewIdentifier: "leaf", request: request)
        XCTAssertNil(hovers.endHover(numbered: 3), "An earlier hover's end closes nothing.")
        let ended = try XCTUnwrap(hovers.endHover(numbered: 4))
        XCTAssertEqual(ended.request, request)
        XCTAssertTrue(ended.linkPreviews === cards)
        XCTAssertNil(hovers.endHover(numbered: 4), "A hover ends once.")

        hovers.use(nil, forView: "leaf")
        XCTAssertNil(hovers.linkPreviews(forView: "leaf"))
    }
}
