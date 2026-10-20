import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// Pointing a note's embeds of an image at the drawing made on it, while the note may change.
@MainActor
final class WorkspaceModelImageEmbedReplacementTests: XCTestCase {
    private func makeWorkspace(noteText: String) async throws -> (WorkspaceModel, MarkdownSession) {
        let vault = try TemporaryVault.make(prefix: "EmbedReplacementVault", for: self).root
        try Data(noteText.utf8).write(to: vault.appendingPathComponent("Note.md"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: vault.appendingPathComponent("Diagram.png"))
        let indexFolder = try TemporaryVault.make(prefix: "EmbedReplacementIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let store = VaultStore(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = store
        workspace.index = index
        // A complete scan makes the name check wait on the index, after the text is read.
        workspace.hasCompletedIndexScan = true
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        return (workspace, session)
    }

    /// BUG-INK-04: a note that changed meanwhile was reported as no longer embedding the image.
    func testEmbedsArePointedAtTheDrawingWhenTheNoteChangesWhileItsLinksAreResolved() async throws {
        let (workspace, session) = try await makeWorkspace(noteText: "![[Diagram.png]]\n")
        let imagePath = try VaultPath("Diagram.png")
        let drawingPath = try VaultPath("Diagram annotated.png")
        // Both run on the main actor in the order they are made: the typing runs while the
        // replacement waits on the index, after it read the text.
        let replacement = Task { @MainActor in await workspace.replaceEmbeds(of: imagePath, with: drawingPath, in: session) }
        let typing = Task { @MainActor in session.text = "Typed meanwhile.\n![[Diagram.png]]\n" }
        await typing.value
        let outcome = await replacement.value
        XCTAssertEqual(outcome, .replaced(count: 1), "The embed is still there, so it is pointed at the drawing.")
        XCTAssertEqual(session.text, "Typed meanwhile.\n![[Diagram annotated.png]]\n")
    }

    func testANoteWithoutTheImageSaysSoRatherThanThatItChanged() async throws {
        let (workspace, session) = try await makeWorkspace(noteText: "No picture here.\n")
        let outcome = await workspace.replaceEmbeds(of: try VaultPath("Diagram.png"), with: try VaultPath("Diagram annotated.png"), in: session)
        XCTAssertEqual(outcome, .noEmbed)
        XCTAssertEqual(session.text, "No picture here.\n")
    }
}
