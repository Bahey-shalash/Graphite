import XCTest
import WebKit
@testable import GraphiteUI

/// Where the plugin web view may navigate. The runtime page stays where it is: a link a
/// plugin renders, a script address, a file address or a frame that tries to replace it is
/// cancelled. Web addresses a person did not tap are cancelled too; only a tapped `http`,
/// `https` or `mailto` link leaves for the system, which this file cannot try without
/// opening a browser.
@MainActor
final class CommunityPluginMessageReceiverNavigationTests: XCTestCase {
    private final class FakeFrame: WKFrameInfo {
        private let frameIsMain: Bool
        init(isMainFrame: Bool) { frameIsMain = isMainFrame; super.init() }
        override var isMainFrame: Bool { frameIsMain }
    }

    private final class FakeNavigationAction: WKNavigationAction {
        private let navigationRequest: URLRequest
        private let kind: WKNavigationType
        private let frame: WKFrameInfo?
        init(address: String, kind: WKNavigationType, targetFrame frame: WKFrameInfo?) {
            navigationRequest = URLRequest(url: URL(string: address)!)
            self.kind = kind
            self.frame = frame
            super.init()
        }
        override var request: URLRequest { navigationRequest }
        override var navigationType: WKNavigationType { kind }
        override var targetFrame: WKFrameInfo? { frame }
    }

    /// WebKit's action and frame classes crash when an instance made without WebKit is freed, so
    /// the fakes are kept for the rest of the test run.
    private static var keepAlive: [AnyObject] = []

    private func policy(for address: String, kind: WKNavigationType = .linkActivated, inMainFrame isMainFrame: Bool? = true) async -> WKNavigationActionPolicy {
        let action = FakeNavigationAction(address: address, kind: kind, targetFrame: isMainFrame.map { FakeFrame(isMainFrame: $0) })
        Self.keepAlive.append(action)
        return await CommunityPluginMessageReceiver().webView(WKWebView(frame: .zero), decidePolicyFor: action)
    }

    func testTheRuntimePageItselfIsAllowedToLoad() async throws {
        let address = try XCTUnwrap(CommunityPluginSchemeHandler.runtimePageAddress).absoluteString
        let decision = await policy(for: address, kind: .other)
        XCTAssertEqual(decision, .allow)
    }

    func testAnotherPageInTheMainFrameIsCancelledSoTheRuntimeIsNeverReplaced() async throws {
        for address in ["graphite-plugins://runtime/other.html", "graphite-plugins://vault/Note.html", "graphite-plugins://runtime/index.html.evil", "graphite-plugins://other/index.html"] {
            for kind in [WKNavigationType.linkActivated, .other, .formSubmitted] {
                let decision = await policy(for: address, kind: kind)
                XCTAssertEqual(decision, .cancel, "\(address) (\(kind.rawValue))")
            }
        }
    }

    func testAFrameAPluginMakesMayLoadVaultFiles() async throws {
        let decision = await policy(for: "graphite-plugins://vault/Note.html", kind: .other, inMainFrame: false)
        XCTAssertEqual(decision, .allow)
    }

    func testScriptFileDataAndOtherSchemesAreCancelledEvenWhenTapped() async throws {
        let addresses = [
            "javascript:alert(1)", "JavaScript:alert(1)", "file:///etc/hosts", "data:text/html,<script>alert(1)</script>",
            "ftp://blocked.invalid/file", "tel:+41000000000", "blob:graphite-plugins://runtime/1234", "view-source:https://blocked.invalid",
        ]
        for address in addresses {
            for isMainFrame in [true, false] {
                let decision = await policy(for: address, inMainFrame: isMainFrame)
                XCTAssertEqual(decision, .cancel, "\(address) (main frame: \(isMainFrame))")
            }
        }
    }

    func testAWebAddressThatIsNotATappedLinkIsCancelledWithoutOpeningAnything() async throws {
        // A navigation a script made inside an existing frame: not a link the person tapped.
        let decision = await policy(for: "https://blocked.invalid/page", kind: .other, inMainFrame: true)
        XCTAssertEqual(decision, .cancel)
        let formDecision = await policy(for: "mailto:someone@blocked.invalid", kind: .formSubmitted, inMainFrame: false)
        XCTAssertEqual(formDecision, .cancel)
    }

    func testBlankPagesAreAllowed() async throws {
        let decision = await policy(for: "about:blank", kind: .other, inMainFrame: false)
        XCTAssertEqual(decision, .allow)
    }
}
