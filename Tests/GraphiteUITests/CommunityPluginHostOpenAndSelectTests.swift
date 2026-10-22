import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// What Advanced URI needs to append to a note and leave the cursor at its end: a plugin's
/// `openFile` and `openLinkText` answered by `CommunityPluginHost` with the document Graphite
/// then has focused, so the plugin's next step works in the note it opened rather than the
/// one open before, and a plugin's cursor move without a change to the text reaching the editor.
@MainActor
final class CommunityPluginHostOpenAndSelectTests: XCTestCase {

    func testOpeningANoteAnswersWithThatNotesEditor() async throws {
        let workspace = try await makeWorkspace(files: ["Welcome.md": "# Welcome\n", "Log.md": "# Log\n\nFirst entry.\n"])
        await workspace.open(try VaultPath("Welcome.md"), placement: .currentTab)

        let answer = await workspace.communityPlugins.answer(["operation": "workspace.openFile", "path": "Log.md", "placement": "currentTab"])

        let activeDocument = try XCTUnwrap((answer as? [String: Any])?["activeDocument"] as? [String: Any], "\(answer)")
        XCTAssertEqual(activeDocument["path"] as? String, "Log.md")
        let editorSnapshot = try XCTUnwrap(activeDocument["editorSnapshot"] as? [String: Any])
        XCTAssertEqual(editorSnapshot["path"] as? String, "Log.md")
        XCTAssertEqual(editorSnapshot["text"] as? String, "# Log\n\nFirst entry.\n")
    }

    func testFollowingALinkAnswersWithTheNoteItLeadsTo() async throws {
        let workspace = try await makeWorkspace(files: ["Welcome.md": "# Welcome\n", "Log.md": "# Log\n"])
        await workspace.open(try VaultPath("Welcome.md"), placement: .currentTab)

        let answer = await workspace.communityPlugins.answer([
            "operation": "workspace.openLinkText", "linktext": "Log", "sourcePath": "Welcome.md", "placement": "currentTab",
        ])

        let activeDocument = try XCTUnwrap((answer as? [String: Any])?["activeDocument"] as? [String: Any], "\(answer)")
        XCTAssertEqual(activeDocument["path"] as? String, "Log.md")
        XCTAssertEqual((activeDocument["editorSnapshot"] as? [String: Any])?["text"] as? String, "# Log\n")
    }

    func testAPluginThatOnlyMovesTheCursorMovesTheEditors() async throws {
        let workspace = try await makeWorkspace(files: ["Log.md": "# Log\n\nFirst entry.\n"])
        await workspace.open(try VaultPath("Log.md"), placement: .currentTab)
        let session = try XCTUnwrap(workspace.markdownSession)
        let description = try XCTUnwrap(workspace.communityPlugins.activeDocumentDescription(includingEditor: true) as? [String: Any])
        let snapshot = try XCTUnwrap(description["editorSnapshot"] as? [String: Any])

        let answer = await workspace.communityPlugins.answer([
            "operation": "editor.apply", "path": "Log.md", "snapshotIdentifier": snapshot["snapshotIdentifier"] as? String ?? "",
            "text": "# Log\n\nFirst entry.\n", "selectionAnchor": 20, "selectionHead": 20,
        ])

        XCTAssertNil((answer as? [String: Any])?["failure"], "\(answer)")
        XCTAssertEqual(session.text, "# Log\n\nFirst entry.\n", "Nothing was edited.")
        XCTAssertEqual(session.selectionRequest, NSRange(location: 20, length: 0), "The editor on screen is asked to move its cursor.")
        XCTAssertEqual(session.selection, NSRange(location: 20, length: 0), "An editor made later starts there.")
    }

    // MARK: Helpers

    private func makeWorkspace(files: [String: String]) async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "PluginOpenFileVault", for: self).root
        for (relativePath, contents) in files {
            try Data(contents.utf8).write(to: vault.appendingPathComponent(relativePath))
        }
        let indexFolder = try TemporaryVault.make(prefix: "PluginOpenFileIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        workspace.communityPlugins.vaultDidOpen(workspace)
        return workspace
    }
}
