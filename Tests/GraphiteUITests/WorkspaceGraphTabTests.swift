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

    func testOpeningAFileHereWhileTheGraphIsInFrontKeepsTheGraph() async throws {
        let workspace = try await makeWorkspace(files: ["Lecture.md": "Text."])
        workspace.showGraph()
        let graphTab = workspace.layout.activeTab.id
        await workspace.open(try VaultPath("Lecture.md"))
        XCTAssertNotEqual(workspace.layout.activeTab.id, graphTab)
        XCTAssertEqual(workspace.layout.tab(withID: graphTab)?.coreView, .graph)
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
