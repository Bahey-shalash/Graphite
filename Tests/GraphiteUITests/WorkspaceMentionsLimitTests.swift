import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// The Backlinks panel lists at most 200 notes in each of its two lists of mentions.
@MainActor
final class WorkspaceMentionsLimitTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = try TemporaryVault.make(prefix: "WorkspaceMentionsLimitTests", for: self).root
    }

    /// A workspace over a vault holding `Target.md` and `noteCount` notes written with `noteText`.
    private func makeWorkspace(noteCount: Int, noteText: String) async throws -> WorkspaceModel {
        try Data("The note the others mention.".utf8).write(to: vault.appendingPathComponent("Target.md"))
        for number in 0..<noteCount {
            try Data(noteText.utf8).write(to: vault.appendingPathComponent(String(format: "Mention %03d.md", number)))
        }
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.index = index
        workspace.store = VaultStore(root: vault)
        return workspace
    }

    func testTheLinkedMentionsListShowsAtMost200OfTheNotesThatLinkToTheNote() async throws {
        let workspace = try await makeWorkspace(noteCount: 201, noteText: "See [[Target]] for more.")

        let groups = await workspace.linkedMentions(of: try VaultPath("Target.md"), names: ["Target"])

        XCTAssertEqual(groups.count, 200)
    }

    func testTheUnlinkedMentionsListShowsAtMost200OfTheNotesThatWriteTheNotesName() async throws {
        let workspace = try await makeWorkspace(noteCount: 201, noteText: "I wrote Target here without a link.")

        let groups = await workspace.unlinkedMentions(of: try VaultPath("Target.md"), names: ["Target"])

        XCTAssertEqual(groups.count, 200)
    }

    func testBothListsShowEveryNoteWhenThereAreFewerThan200() async throws {
        let linkedWorkspace = try await makeWorkspace(noteCount: 3, noteText: "See [[Target]] for more.")

        let linked = await linkedWorkspace.linkedMentions(of: try VaultPath("Target.md"), names: ["Target"])

        XCTAssertEqual(linked.count, 3)
    }
}
