import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// The whole vault's graph in a tab of the workspace: opened from the palette or the View
/// menu, kept open while notes are opened from it, beside a note in a split.
@MainActor
final class WorkspaceGraphTabTests: XCTestCase {

    func testTheGraphOpensInTheEmptyTabAndAgainInItsOwnTab() async throws {
        let workspace = try await makeWorkspace(files: ["Lecture.md": "See [[Exam]].", "Exam.md": "Friday."])
        let emptyTab = workspace.layout.activeTab.id
        workspace.showGraph()
        XCTAssertEqual(workspace.layout.activeTab.id, emptyTab, "An empty tab shows the graph.")
        XCTAssertEqual(workspace.layout.activeTab.coreView, .graph)
        XCTAssertEqual(workspace.title(ofTab: workspace.layout.activeTab), "Graph View")

        await workspace.open(try VaultPath("Lecture.md"), placement: .newTab)
        workspace.showGraph()
        XCTAssertEqual(workspace.layout.activeTab.id, emptyTab, "The graph's tab comes forward; no second graph opens.")
        XCTAssertEqual(workspace.layout.allTabs.count, 2)
    }

    func testANodeOpensBesideTheGraphWhichStaysOpen() async throws {
        let workspace = try await makeWorkspace(files: ["Lecture.md": "See [[Exam]].", "Exam.md": "Friday."])
        workspace.showGraph()
        let graphTab = workspace.layout.activeTab.id

        await workspace.open(GraphNode.file(try VaultPath("Lecture.md")), fromGraphTab: graphTab)
        XCTAssertEqual(workspace.layout.focusedGroup.tabs.map(\.coreView), [.graph, nil])
        XCTAssertEqual(workspace.selection?.rawValue, "Lecture.md")
        XCTAssertEqual(workspace.markdownSession?.path.rawValue, "Lecture.md")

        await workspace.open(GraphNode.file(try VaultPath("Exam.md")), fromGraphTab: graphTab)
        XCTAssertEqual(workspace.layout.focusedGroup.tabs.map { tab in tab.path?.rawValue ?? tab.coreView?.rawValue }, ["graph", "Exam.md"],
                       "The next note takes the tab beside the graph.")
        XCTAssertEqual(workspace.layout.tab(withID: graphTab)?.coreView, .graph)
    }

    func testSplitANodeOpensOnTheOtherSide() async throws {
        let workspace = try await makeWorkspace(files: ["Lecture.md": "See [[Exam]].", "Exam.md": "Friday."])
        await workspace.open(try VaultPath("Lecture.md"))
        await workspace.open(try VaultPath("Exam.md"), placement: .otherGroup)
        workspace.focusGroup(workspace.layout.groups[0].id)
        workspace.showGraph()
        let graphTab = workspace.layout.activeTab.id
        XCTAssertEqual(workspace.layout.group(containing: graphTab)?.id, workspace.layout.groups[0].id)

        await workspace.open(GraphNode.file(try VaultPath("Lecture.md")), fromGraphTab: graphTab)
        XCTAssertEqual(workspace.layout.activeTab.path?.rawValue, "Lecture.md", "A note open in a tab already comes forward in it, as a file is open in one tab only.")
        XCTAssertEqual(workspace.layout.tab(withID: graphTab)?.coreView, .graph)

        await workspace.closeTab(try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Lecture.md"))))
        await workspace.open(GraphNode.file(try VaultPath("Lecture.md")), fromGraphTab: graphTab)
        XCTAssertEqual(workspace.layout.groups[1].activeTab.path?.rawValue, "Lecture.md", "Split, a note opens on the other side.")
        XCTAssertEqual(workspace.layout.groups[0].activeTab.id, graphTab, "The graph stays in front on its side.")
        XCTAssertEqual(workspace.layout.focusedGroupID, workspace.layout.groups[1].id)
    }

    func testOpeningAFileHereWhileTheGraphIsInFrontKeepsTheGraph() async throws {
        let workspace = try await makeWorkspace(files: ["Lecture.md": "Text."])
        workspace.showGraph()
        let graphTab = workspace.layout.activeTab.id
        await workspace.open(try VaultPath("Lecture.md"))
        XCTAssertNotEqual(workspace.layout.activeTab.id, graphTab)
        XCTAssertEqual(workspace.layout.tab(withID: graphTab)?.coreView, .graph)
    }

    func testTheLocalGraphOpensTheWholeGraphCenteredOnItsNote() async throws {
        let workspace = try await makeWorkspace(files: ["Lecture.md": "See [[Exam]].", "Exam.md": "Friday."])
        await workspace.open(try VaultPath("Lecture.md"))
        workspace.showGraph(centeredOn: try VaultPath("Lecture.md"))
        let graphTab = workspace.layout.activeTab
        XCTAssertEqual(graphTab.coreView, .graph)
        let firstRequest = try XCTUnwrap(workspace.document(for: graphTab.id).graphCenterRequest)
        XCTAssertEqual(firstRequest.identifier, "Lecture.md")

        workspace.activateTab(try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Lecture.md"))))
        workspace.showGraph(centeredOn: try VaultPath("Lecture.md"))
        XCTAssertEqual(workspace.layout.activeTab.id, graphTab.id, "The graph's tab comes forward.")
        let secondRequest = try XCTUnwrap(workspace.document(for: graphTab.id).graphCenterRequest)
        XCTAssertEqual(secondRequest.identifier, "Lecture.md")
        XCTAssertNotEqual(secondRequest, firstRequest, "Asking again centers again, after the person moved the graph.")
    }

    // MARK: Helpers

    private func makeWorkspace(files: [String: String]) async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "GraphTabVault", for: self).root
        for (relativePath, contents) in files {
            try Data(contents.utf8).write(to: vault.appendingPathComponent(relativePath))
        }
        let indexFolder = try TemporaryVault.make(prefix: "GraphTabIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return workspace
    }
}
