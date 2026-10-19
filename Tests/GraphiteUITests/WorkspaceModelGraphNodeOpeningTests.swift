import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Opening a node of the graph view: a tag node searches `tag:#name`, in the search field.
@MainActor
final class WorkspaceModelGraphNodeOpeningTests: XCTestCase {
    func testOpeningATagNodeSearchesForItsNotesAndFocusesTheSearchField() async throws {
        let workspace = WorkspaceModel()
        let focusRequestsBefore = workspace.searchFocusRequest

        await workspace.open(GraphNode(id: "#physics/optics", kind: .tag), from: nil)

        XCTAssertEqual(workspace.searchQuery, "tag:#physics/optics")
        XCTAssertEqual(workspace.searchFocusRequest, focusRequestsBefore + 1)
    }

    func testOpeningTheSameTagNodeAgainAsksForFocusAgain() async throws {
        let workspace = WorkspaceModel()
        let tagNode = GraphNode(id: "#exam", kind: .tag)
        await workspace.open(tagNode, from: nil)
        let focusRequestsAfterFirst = workspace.searchFocusRequest
        await workspace.open(tagNode, from: try VaultPath("Notes/Today.md"))
        XCTAssertEqual(workspace.searchQuery, "tag:#exam")
        XCTAssertEqual(workspace.searchFocusRequest, focusRequestsAfterFirst + 1, "The source note does not matter to a tag.")
    }
}
