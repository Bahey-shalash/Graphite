import XCTest
@testable import GraphiteCore

/// The plugin runtime's messages about links plugins ask Graphite to preview, decoded once
/// from what WebKit hands over (dictionaries of JSON values).
final class CommunityPluginLinkHoverMessagesTests: XCTestCase {
    func testALiveViewsHoverIsDecodedWithItsLinkAndTheElementsFrame() throws {
        let message: [String: Any] = [
            "operation": "hoverLink.show", "hoverNumber": 3, "leafIdentifier": "graphite-leaf-1",
            "rect": ["x": 12.5, "y": 40, "width": 80, "height": 18], "linktext": "Other#Plan", "sourcePath": "Notes/Note.md", "source": "rows",
        ]
        let hover = try XCTUnwrap(CommunityPluginRuntimeMessage.decoded(CommunityPluginLiveLinkHover.self, from: message))
        XCTAssertEqual(hover.hoverNumber, 3)
        XCTAssertEqual(hover.leafIdentifier, "graphite-leaf-1")
        XCTAssertEqual(hover.rect, CommunityPluginMeasuredRect(x: 12.5, y: 40, width: 80, height: 18))
        XCTAssertEqual(hover.link, CommunityPluginHoveredLink(linktext: "Other#Plan", sourcePath: "Notes/Note.md"))
        XCTAssertEqual(hover.link.sourceNote, try VaultPath("Notes/Note.md"))
    }

    func testAMessageOfAnotherShapeIsNoHover() {
        XCTAssertNil(CommunityPluginRuntimeMessage.decoded(CommunityPluginLiveLinkHover.self, from: ["operation": "hoverLink.show", "linktext": "Other"]),
                     "A hover without its number, leaf or frame is not shown.")
        XCTAssertNil(CommunityPluginRuntimeMessage.decoded(CommunityPluginLiveLinkHover.self, from: ["date": Date()]), "Values JSON cannot hold are refused.")
    }

    func testACopysHoverAnswerCarriesTheLinkOnlyWhenAPluginAskedForOne() throws {
        let asked = try XCTUnwrap(CommunityPluginRuntimeMessage.decoded(CommunityPluginCopyHoverAnswer.self, from: [
            "isHandled": true, "linkHover": ["linktext": "Folder/Other.md", "sourcePath": "", "source": "recent-files"],
        ]))
        XCTAssertEqual(asked.linkHover, CommunityPluginHoveredLink(linktext: "Folder/Other.md", sourcePath: ""))
        let notAsked = try XCTUnwrap(CommunityPluginRuntimeMessage.decoded(CommunityPluginCopyHoverAnswer.self, from: ["isHandled": true]))
        XCTAssertNil(notAsked.linkHover)
    }

    func testWhatACopysScriptSaysOfThePointerKeepsItsFrameAndLink() throws {
        let onLink = try XCTUnwrap(CommunityPluginRuntimeMessage.decoded(CommunityPluginCopyPointer.self, from: [
            "kind": "linkHover", "linktext": "Other", "rect": ["x": 1, "y": 2, "width": 3, "height": 4],
        ]))
        XCTAssertEqual(onLink, CommunityPluginCopyPointer(rect: CommunityPluginMeasuredRect(x: 1, y: 2, width: 3, height: 4), linktext: "Other"))
        let offTheLink = try XCTUnwrap(CommunityPluginRuntimeMessage.decoded(CommunityPluginCopyPointer.self, from: ["kind": "linkHover", "linktext": NSNull(), "rect": NSNull()]))
        XCTAssertEqual(offTheLink, CommunityPluginCopyPointer(rect: nil, linktext: nil))
    }

    func testALinkWithNoSourcePathOrAnInvalidOneResolvesFromTheVaultsRoot() {
        XCTAssertEqual(CommunityPluginHoveredLink(linktext: "Other", sourcePath: "").sourceNote, .root)
        XCTAssertEqual(CommunityPluginHoveredLink(linktext: "Other", sourcePath: "../Outside.md").sourceNote, .root)
    }
}
