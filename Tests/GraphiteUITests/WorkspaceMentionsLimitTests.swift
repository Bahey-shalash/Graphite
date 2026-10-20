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

    /// BUG-READING-04: the mention left the list although no link was written.
    func testLinkingAMentionReportsWhetherTheLinkWasWritten() async throws {
        let workspace = try await makeWorkspace(noteCount: 2, noteText: "I wrote Target here without a link.")
        let target = try VaultPath("Target.md")
        let groups = await workspace.unlinkedMentions(of: target, names: ["Target"])
        let changedGroup = try XCTUnwrap(groups.first { group in group.path.rawValue == "Mention 000.md" })
        let unchangedGroup = try XCTUnwrap(groups.first { group in group.path.rawValue == "Mention 001.md" })
        try Data("A different sentence altogether.".utf8).write(to: vault.appendingPathComponent("Mention 000.md"))

        let linkedChangedNote = await workspace.linkMention(try XCTUnwrap(changedGroup.matches.first), in: changedGroup.path, to: target)
        let linkedUnchangedNote = await workspace.linkMention(try XCTUnwrap(unchangedGroup.matches.first), in: unchangedGroup.path, to: target)

        XCTAssertFalse(linkedChangedNote, "The note changed after it was listed, so no link was written.")
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Mention 000.md"), encoding: .utf8), "A different sentence altogether.")
        XCTAssertTrue(linkedUnchangedNote)
        XCTAssertTrue(try String(contentsOf: vault.appendingPathComponent("Mention 001.md"), encoding: .utf8).contains("[[Target]]"))
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
