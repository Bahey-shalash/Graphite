import XCTest
import GraphiteCore
@testable import GraphiteUI

/// A plugin that shows a view tells Graphite which views exist and then to show one. The host
/// shows the view whichever of the two messages it handles first.
@MainActor
final class CommunityPluginHostViewRevealTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    private static func viewList(leafIdentifier: String) -> [String: Any] {
        ["operation": "views.changed", "views": [[
            "leafIdentifier": leafIdentifier, "viewType": "saved-counter", "title": "Counter view", "icon": "clock",
            "placement": "tab", "isLive": false, "state": "{\"clicks\":3}",
        ] as [String: Any]]]
    }

    func testAViewToShowBeforeTheListThatNamesItIsShownWhenTheListArrives() async throws {
        let workspace = try await testBed.workspaceWithPlugins([])
        let host = workspace.communityPlugins

        _ = await host.answer(["operation": "view.reveal", "leafIdentifier": "leaf-7", "placement": "tab"])
        XCTAssertNil(workspace.tabDocuments.values.first { document in document.pluginViewIdentifier != nil }, "Nothing to show yet.")
        _ = await host.answer(Self.viewList(leafIdentifier: "leaf-7"))

        let document = try XCTUnwrap(workspace.tabDocuments.values.first { document in document.pluginViewIdentifier == "leaf-7" })
        XCTAssertEqual(document.restorablePluginView?.viewType, "saved-counter")
        XCTAssertEqual(document.restorablePluginView?.state, "{\"clicks\":3}")
    }

    func testAViewToShowAfterTheListThatNamesItIsShownAtOnce() async throws {
        let workspace = try await testBed.workspaceWithPlugins([])
        let host = workspace.communityPlugins

        _ = await host.answer(Self.viewList(leafIdentifier: "leaf-7"))
        _ = await host.answer(["operation": "view.reveal", "leafIdentifier": "leaf-7", "placement": "tab"])

        XCTAssertNotNil(workspace.tabDocuments.values.first { document in document.pluginViewIdentifier == "leaf-7" })
    }

    /// BUG-SHELL-06: the phone's tab switcher named a tab showing a plugin's view "New Tab"
    /// while the tab bar named it after the view; both now take the workspace's title.
    func testATabShowingAViewIsNamedAfterTheViewWhereverTabsAreListed() async throws {
        let workspace = try await testBed.workspaceWithPlugins([])
        let host = workspace.communityPlugins
        _ = await host.answer(Self.viewList(leafIdentifier: "leaf-7"))
        _ = await host.answer(["operation": "view.reveal", "leafIdentifier": "leaf-7", "placement": "tab"])

        let viewTab = try XCTUnwrap(workspace.layout.allTabs.first { tab in workspace.tabDocuments[tab.id]?.pluginViewIdentifier == "leaf-7" })

        XCTAssertNil(viewTab.path)
        XCTAssertEqual(workspace.title(ofTab: viewTab), "Counter view")
    }
}
