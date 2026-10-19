import XCTest
import SwiftUI
import WebKit
import GraphiteCore
@testable import GraphiteUI

/// The copies of a plugin's blocks and views that notes and panes show. A copy is a page
/// that runs no script of its own, keeps nothing between loads, and follows no navigation
/// after its first load.
@MainActor
final class CommunityPluginCodeBlockDisplayTests: XCTestCase {
    private final class FakeFrame: WKFrameInfo {
        private let frameIsMain: Bool
        init(isMainFrame: Bool) { frameIsMain = isMainFrame; super.init() }
        override var isMainFrame: Bool { frameIsMain }
    }

    private final class FakeNavigationAction: WKNavigationAction {
        private let frame: WKFrameInfo?
        init(targetFrame frame: WKFrameInfo?) { self.frame = frame; super.init() }
        override var targetFrame: WKFrameInfo? { frame }
    }

    /// WebKit's action and frame classes crash when an instance made without WebKit is freed, so
    /// the fakes are kept for the rest of the test run.
    private static var keepAlive: [AnyObject] = []

    private func policy(afterFirstLoad isLoaded: Bool, inMainFrame isMainFrame: Bool?) async -> WKNavigationActionPolicy {
        let coordinator = CommunityPluginCodeBlockDisplayCoordinator()
        coordinator.isLoaded = isLoaded
        let action = FakeNavigationAction(targetFrame: isMainFrame.map { FakeFrame(isMainFrame: $0) })
        Self.keepAlive.append(action)
        return await coordinator.webView(WKWebView(frame: .zero), decidePolicyFor: action)
    }

    func testTheFirstLoadOfTheCopysOwnPageIsAllowed() async throws {
        let decision = await policy(afterFirstLoad: false, inMainFrame: true)
        XCTAssertEqual(decision, .allow)
    }

    func testNoNavigationIsFollowedOnceTheCopyHasLoaded() async throws {
        for isMainFrame: Bool? in [true, false, nil] {
            let decision = await policy(afterFirstLoad: true, inMainFrame: isMainFrame)
            XCTAssertEqual(decision, .cancel, "main frame: \(String(describing: isMainFrame))")
        }
    }

    func testNavigationOutsideTheMainFrameIsNeverFollowed() async throws {
        let subframe = await policy(afterFirstLoad: false, inMainFrame: false)
        XCTAssertEqual(subframe, .cancel)
        let newWindow = await policy(afterFirstLoad: false, inMainFrame: nil)
        XCTAssertEqual(newWindow, .cancel)
    }

    func testAllCopiesShareOneNonPersistentWebsiteDataStore() {
        XCTAssertFalse(CommunityPluginCodeBlockDisplay.dataStore.isPersistent)
        XCTAssertTrue(CommunityPluginCodeBlockDisplay.dataStore === CommunityPluginCodeBlockDisplay.dataStore)
        XCTAssertNil(CommunityPluginCodeBlockDisplay.dataStore.identifier)
    }

    #if canImport(AppKit)
    func testTheCopyShownInAWindowRunsNoPageScriptAndUsesTheSharedNonPersistentStore() throws {
        let workspace = WorkspaceModel()
        let block = CommunityPluginShownCodeBlock(host: workspace.communityPlugins)
        let display = CommunityPluginCodeBlockDisplay(block: block, html: "<p>Copy</p>", styleSheets: "", isDark: false, textSize: 16, accentHex: nil)
        let hostingView = NSHostingView(rootView: display)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()

        let webView = try XCTUnwrap(Self.firstWebView(in: hostingView), "The copy builds its web view.")
        XCTAssertFalse(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript, "Scripts in the copy's page do not run.")
        XCTAssertTrue(webView.configuration.websiteDataStore === CommunityPluginCodeBlockDisplay.dataStore)
        XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
    }

    private static func firstWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = firstWebView(in: subview) { return found }
        }
        return nil
    }
    #endif
}
