import XCTest
@testable import GraphiteUI

/// The attribute names Graphite's own page reads on the copies of a plugin's blocks. The
/// plugins' page writes them (`reading-block-attributes.test.js` pins that side), so a
/// renamed attribute leaves menus and drags unheard.
final class CommunityPluginCodeBlockPageAttributeTests: XCTestCase {
    func testTheShellStylesElementsThatListenForAMenuByTheirAttribute() {
        XCTAssertTrue(CommunityPluginCodeBlockPage.shell.contains(#"[data-graphite-listens~="menu"]"#))
    }

    func testTheScriptFindsTheElementsAPluginListensWithByTheirAttribute() {
        XCTAssertTrue(CommunityPluginCodeBlockPage.script.contains("current.getAttribute('data-graphite-listens')"))
        // The kinds this page asks about; `drop` is only written by the plugins' page.
        for kind in ["menu", "hover", "press", "drag"] {
            XCTAssertTrue(CommunityPluginCodeBlockPage.script.contains("listener(element, '\(kind)')"), kind)
        }
    }
}
