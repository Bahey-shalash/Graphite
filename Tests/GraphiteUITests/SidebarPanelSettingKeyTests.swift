import XCTest
@testable import GraphiteUI

/// The device settings of the left and right sidebars: the names they are kept under and the
/// raw values of the panels they remember.
final class SidebarPanelSettingKeyTests: XCTestCase {
    func testTheLeftSidebarSettingsAreKeptUnderTheseUnprefixedNames() {
        XCTAssertEqual(SidebarPanelSettingKey.panel, "sidebarPanel")
        XCTAssertEqual(SidebarPanelSettingKey.tagSortOrder, "tagsViewSortOrder")
        XCTAssertEqual(SidebarPanelSettingKey.showsNestedTags, "tagsViewShowsNestedTags")
        XCTAssertEqual(SidebarPanelSettingKey.propertySortOrder, "propertiesViewSortOrder")
    }

    func testTheLeftSidebarRemembersItsPanelByTheseRawValues() {
        XCTAssertEqual(SidebarPanel.allCases.map(\.rawValue), ["files", "tags", "properties", "bookmarks"])
    }

    func testTheRightSidebarRemembersItsPanelByTheseRawValues() {
        XCTAssertEqual(NoteLinksInspector.InspectorPanel.allCases.map(\.rawValue),
                       ["outline", "backlinks", "outgoingLinks", "tags", "footnotes", "graph", "map"])
    }
}
