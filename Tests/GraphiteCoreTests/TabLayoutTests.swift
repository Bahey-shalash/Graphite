import XCTest
@testable import GraphiteCore

final class TabLayoutTests: XCTestCase {
    private func path(_ rawPath: String) throws -> VaultPath { try VaultPath(rawPath) }

    /// Opens `rawPath` in the tab the layout picks for opening "here".
    private func openHere(_ rawPath: String, in layout: inout TabLayout) throws -> UUID {
        let tabID = layout.tabForOpeningHere()
        layout.show(try path(rawPath), inTab: tabID, recordsHistory: true)
        return tabID
    }

    func testANewLayoutHasOneEmptyTab() {
        let layout = TabLayout()
        XCTAssertEqual(layout.groups.count, 1)
        XCTAssertFalse(layout.isSplit)
        XCTAssertNil(layout.activeTab.path)
    }

    func testOpeningHereReplacesTheActiveTabUnlessItIsPinned() throws {
        var layout = TabLayout()
        let firstTab = try openHere("A.md", in: &layout)
        XCTAssertEqual(try openHere("B.md", in: &layout), firstTab, "An unpinned tab changes file.")
        XCTAssertEqual(layout.activeTab.history.entries.map(\.name), ["A.md", "B.md"])
        layout.setPinned(true, tabID: firstTab)
        let secondTab = try openHere("C.md", in: &layout)
        XCTAssertNotEqual(secondTab, firstTab, "A pinned tab keeps its file; a new tab opens beside it.")
        XCTAssertEqual(layout.focusedGroup.tabs.map { tab in tab.path?.name }, ["B.md", "C.md"])
        XCTAssertEqual(layout.tabID(showing: try path("B.md")), firstTab)
    }

    func testOpeningToTheRightCreatesTheSplitAndReusesItsEmptyTab() throws {
        var layout = TabLayout()
        let noteTab = try openHere("Notes.md", in: &layout)
        let rightTab = layout.tabForOpeningInOtherGroup()
        XCTAssertTrue(layout.isSplit)
        XCTAssertEqual(layout.focusedGroup.tabs.map(\.id), [rightTab])
        layout.show(try path("Slides.pdf"), inTab: rightTab, recordsHistory: true)
        layout.focus(tabID: noteTab)
        let secondRightTab = layout.tabForOpeningInOtherGroup()
        XCTAssertNotEqual(secondRightTab, rightTab, "A tab with a file is not replaced; a new tab opens there.")
        XCTAssertEqual(layout.groups.count, TabLayout.maximumGroupCount, "There are at most two groups.")
        XCTAssertEqual(layout.focusedGroup.tabs.count, 2)
    }

    func testShowingATabOnTheOtherSideKeepsFocus() throws {
        var layout = TabLayout()
        let noteTab = try openHere("Notes.md", in: &layout)
        let pdfTab = layout.tabForOpeningInOtherGroup()
        layout.show(try path("Slides.pdf"), inTab: pdfTab, recordsHistory: true)
        let otherRightTab = layout.addTab(showing: try path("Other.md"))
        layout.focus(tabID: noteTab)
        layout.activateWithoutFocus(tabID: pdfTab)
        XCTAssertEqual(layout.activeTab.id, noteTab, "The note's side stays focused.")
        XCTAssertEqual(layout.groups[1].activeTabID, pdfTab)
        XCTAssertNotEqual(layout.groups[1].activeTabID, otherRightTab)
    }

    func testClosingATabActivatesItsRightNeighborThenItsLeft() throws {
        var layout = TabLayout()
        let first = try openHere("A.md", in: &layout)
        let second = layout.addTab(showing: try path("B.md"))
        let third = layout.addTab(showing: try path("C.md"))
        layout.focus(tabID: second)
        layout.closeTab(second)
        XCTAssertEqual(layout.activeTab.id, third)
        layout.closeTab(third)
        XCTAssertEqual(layout.activeTab.id, first)
        layout.closeTab(first)
        XCTAssertEqual(layout.focusedGroup.tabs.count, 1, "The last group keeps one empty tab.")
        XCTAssertNil(layout.activeTab.path)
        XCTAssertEqual(layout.closedPaths.map(\.name), ["B.md", "C.md", "A.md"])
    }

    func testClosingTheLastTabOfASplitGroupClosesTheSplit() throws {
        var layout = TabLayout()
        let leftTab = try openHere("Notes.md", in: &layout)
        let rightTab = layout.tabForOpeningInOtherGroup()
        layout.show(try path("Slides.pdf"), inTab: rightTab, recordsHistory: true)
        layout.closeTab(rightTab)
        XCTAssertFalse(layout.isSplit)
        XCTAssertEqual(layout.activeTab.id, leftTab)
        XCTAssertEqual(layout.popClosedPath(), try path("Slides.pdf"))
        XCTAssertNil(layout.popClosedPath())
    }

    func testReopeningSkipsFilesThatAreOpenAgain() throws {
        var layout = TabLayout()
        let tab = try openHere("A.md", in: &layout)
        layout.addTab(showing: try path("B.md"))
        layout.closeTab(tab)
        _ = try openHere("A.md", in: &layout)
        XCTAssertNil(layout.popClosedPath(), "A.md is open again, so there is nothing to reopen.")
    }

    func testClosingOtherTabsKeepsPinnedTabs() throws {
        var layout = TabLayout()
        let pinned = try openHere("Pinned.md", in: &layout)
        layout.setPinned(true, tabID: pinned)
        layout.addTab(showing: try path("B.md"))
        let kept = layout.addTab(showing: try path("C.md"))
        layout.addTab(showing: try path("D.md"))
        let closed = layout.closeOtherTabs(keeping: kept)
        XCTAssertEqual(closed.count, 2)
        XCTAssertEqual(layout.focusedGroup.tabs.map { tab in tab.path?.name }, ["Pinned.md", "C.md"])
        XCTAssertEqual(layout.activeTab.id, kept)
    }

    func testClosingAGroupReturnsItsTabs() throws {
        var layout = TabLayout()
        _ = try openHere("Notes.md", in: &layout)
        let rightTab = layout.tabForOpeningInOtherGroup()
        layout.show(try path("Slides.pdf"), inTab: rightTab, recordsHistory: true)
        let closed = layout.closeGroup(layout.focusedGroupID)
        XCTAssertEqual(closed, [rightTab])
        XCTAssertFalse(layout.isSplit)
        XCTAssertEqual(layout.activeTab.path?.name, "Notes.md")
        let remaining = layout.closeGroup(layout.focusedGroupID)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNil(layout.activeTab.path, "The last group is left with an empty tab.")
    }

    func testMovingATabToTheOtherGroup() throws {
        var layout = TabLayout()
        let lone = try openHere("Slides.pdf", in: &layout)
        layout.moveTabToOtherGroup(lone)
        XCTAssertTrue(layout.isSplit, "Moving the only tab creates the split.")
        XCTAssertNil(layout.groups[0].activeTab.path, "The group it left keeps an empty tab.")
        XCTAssertEqual(layout.groups[1].tabs.map(\.id), [lone])
        XCTAssertEqual(layout.focusedGroupID, layout.groups[1].id)
        layout.moveTabToOtherGroup(lone)
        XCTAssertFalse(layout.isSplit, "Moving the last tab of a group closes that group.")
        XCTAssertEqual(layout.activeTab.id, lone)
        XCTAssertEqual(layout.focusedGroup.tabs.count, 2)
    }

    func testDraggingATabReordersItsGroup() throws {
        var layout = TabLayout()
        let first = try openHere("A.md", in: &layout)
        let second = layout.addTab(showing: try path("B.md"))
        let third = layout.addTab(showing: try path("C.md"))
        let groupID = layout.focusedGroupID
        layout.moveTab(first, toGroup: groupID, at: 3)
        XCTAssertEqual(layout.focusedGroup.tabs.map(\.id), [second, third, first])
        layout.moveTab(first, toGroup: groupID, at: 0)
        XCTAssertEqual(layout.focusedGroup.tabs.map(\.id), [first, second, third])
        let rightGroup = layout.openOtherGroup()
        layout.moveTab(second, toGroup: rightGroup, at: 0)
        XCTAssertEqual(layout.groups[1].tabs.first?.id, second)
        XCTAssertEqual(layout.groups[0].tabs.map(\.id), [first, third])
    }

    func testNextAndPreviousTabWrapAround() throws {
        var layout = TabLayout()
        let first = try openHere("A.md", in: &layout)
        let second = layout.addTab(showing: try path("B.md"))
        layout.activateNeighborTab(forward: true)
        XCTAssertEqual(layout.activeTab.id, first)
        layout.activateNeighborTab(forward: false)
        XCTAssertEqual(layout.activeTab.id, second)
        layout.activateTab(atPosition: 8)
        XCTAssertEqual(layout.activeTab.id, second, "A position past the end is the last tab.")
        layout.activateTab(atPosition: 0)
        XCTAssertEqual(layout.activeTab.id, first)
    }

    func testEachTabHasItsOwnHistory() throws {
        var layout = TabLayout()
        let leftTab = try openHere("A.md", in: &layout)
        layout.show(try path("B.md"), inTab: leftTab, recordsHistory: true)
        let rightTab = layout.tabForOpeningInOtherGroup()
        layout.show(try path("C.md"), inTab: rightTab, recordsHistory: true)
        XCTAssertNil(layout.historyTarget(ofTab: rightTab, forward: false))
        XCTAssertEqual(layout.historyTarget(ofTab: leftTab, forward: false), try path("A.md"))
        XCTAssertEqual(layout.tab(withID: leftTab)?.history.currentIndex, 1, "Looking does not move.")
        XCTAssertEqual(layout.moveInHistory(ofTab: leftTab, forward: false), try path("A.md"))
        layout.show(try path("A.md"), inTab: leftTab, recordsHistory: false)
        XCTAssertEqual(layout.historyTarget(ofTab: leftTab, forward: true), try path("B.md"))
    }

    func testRenamesAndDeletionsReachEveryTab() throws {
        var layout = TabLayout()
        let leftTab = try openHere("Course/Week 1.md", in: &layout)
        layout.show(try path("Course/Week 2.md"), inTab: leftTab, recordsHistory: true)
        let rightTab = layout.tabForOpeningInOtherGroup()
        layout.show(try path("Course/Slides.pdf"), inTab: rightTab, recordsHistory: true)
        layout.replacePrefix(try path("Course"), with: try path("Signals"))
        XCTAssertEqual(layout.tab(withID: leftTab)?.path, try path("Signals/Week 2.md"))
        XCTAssertEqual(layout.tab(withID: leftTab)?.history.entries, [try path("Signals/Week 1.md"), try path("Signals/Week 2.md")])
        XCTAssertEqual(layout.tab(withID: rightTab)?.path, try path("Signals/Slides.pdf"))

        let removed = layout.removeTabs(inside: try path("Signals/Slides.pdf"))
        XCTAssertEqual(removed, [rightTab])
        XCTAssertFalse(layout.isSplit, "The group left empty closes.")
        XCTAssertTrue(layout.closedPaths.isEmpty, "A deleted file cannot be reopened.")
        layout.removeTabs(inside: try path("Signals"))
        XCTAssertNil(layout.activeTab.path)
        XCTAssertEqual(layout.focusedGroup.tabs.count, 1)
    }

    func testSavedLayoutsRestoreWithoutMissingOrRepeatedFiles() throws {
        var layout = TabLayout()
        let notes = try openHere("Notes.md", in: &layout)
        layout.setPinned(true, tabID: notes)
        layout.addTab(showing: try path("Gone.md"))
        layout.addTab(showing: try path("Kept.md"))
        let rightTab = layout.tabForOpeningInOtherGroup()
        layout.show(try path("Slides.pdf"), inTab: rightTab, recordsHistory: true)
        layout.splitFraction = 0.6
        layout.focus(tabID: notes)
        var saved = layout.saved
        XCTAssertEqual(saved.groups.map { group in group.tabs.map(\.path) }, [["Notes.md", "Gone.md", "Kept.md"], ["Slides.pdf"]])
        saved.groups[0].activeTabIndex = 1
        saved.groups[1].tabs.append(SavedTabLayout.Tab(path: "Notes.md", isPinned: false))

        let data = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(SavedTabLayout.self, from: data)
        let restored = TabLayout(saved: decoded) { path in path.name != "Gone.md" }
        XCTAssertEqual(restored.groups.map { group in group.tabs.map { tab in tab.path?.name } }, [["Notes.md", "Kept.md"], ["Slides.pdf"]])
        XCTAssertEqual(restored.groups[0].activeTab.path?.name, "Notes.md", "The missing active tab's left neighbor becomes active.")
        XCTAssertEqual(restored.groups[0].tabs.first?.isPinned, true)
        XCTAssertEqual(restored.focusedGroupID, restored.groups[0].id)
        XCTAssertEqual(restored.splitFraction, 0.6)
        XCTAssertEqual(restored.groups[0].tabs.first?.history.entries.map(\.name), ["Notes.md"])

        let nothingLeft = TabLayout(saved: decoded) { _ in false }
        XCTAssertEqual(nothingLeft.groups.count, 1)
        XCTAssertNil(nothingLeft.activeTab.path)
    }

    func testTheSplitFractionStaysInRange() {
        var layout = TabLayout()
        layout.splitFraction = 0.95
        XCTAssertEqual(layout.splitFraction, TabLayout.splitFractionRange.upperBound)
        layout.splitFraction = 0.1
        XCTAssertEqual(layout.splitFraction, TabLayout.splitFractionRange.lowerBound)
    }
}
