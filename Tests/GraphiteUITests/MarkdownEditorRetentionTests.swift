import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The policy that decides which hidden note editors, with their undo history, are kept.
@MainActor
final class MarkdownEditorRetentionTests: XCTestCase {
    private final class RecordingEditor: RetainableMarkdownEditor {
        let editedSession: MarkdownSession
        let retainedTextLength: Int
        private(set) var isDiscarded = false

        init(session: MarkdownSession, textLength: Int = 10) {
            editedSession = session
            retainedTextLength = textLength
        }

        func discardRetainedEditor() { isDiscarded = true }
    }

    private var vault: URL!
    private var store: VaultStore!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("Retention-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        store = VaultStore(root: vault)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func openNote(_ name: String) async throws -> (TabDocument, MarkdownSession) {
        let path = try VaultPath(name)
        try Data("\(name)\n".utf8).write(to: vault.appendingPathComponent(name))
        let session = try MarkdownSession(path: path, snapshot: try await store.read(path), store: store, didSave: { _ in })
        let document = TabDocument()
        document.markdownSession = session
        document.loadedPath = path
        return (document, session)
    }

    func testKeepsTheMostRecentlyHiddenEditorsWithinTheCount() async throws {
        let retention = MarkdownEditorRetention(limits: .init(maximumHiddenEditorCount: 2, maximumHiddenTextLength: 1_000))
        var notes: [(document: TabDocument, editor: RecordingEditor)] = []
        for number in 1...3 {
            let (document, session) = try await openNote("Note \(number).md")
            let editor = RecordingEditor(session: session)
            retention.editorDidAttach(editor)
            XCTAssertTrue(retention.keepHiddenEditor(editor, owner: document))
            notes.append((document, editor))
        }
        XCTAssertEqual(retention.hiddenEditorCount, 2)
        XCTAssertTrue(notes[0].editor.isDiscarded, "The editor hidden longest goes first.")
        XCTAssertFalse(notes[1].editor.isDiscarded)
        XCTAssertFalse(notes[2].editor.isDiscarded)
        XCTAssertNil(retention.takeEditor(for: notes[0].editor.editedSession, owner: notes[0].document))
        XCTAssertTrue(retention.takeEditor(for: notes[1].editor.editedSession, owner: notes[1].document) === notes[1].editor)
        XCTAssertEqual(retention.hiddenEditorCount, 1, "A taken editor is on screen again, not hidden.")
    }

    func testTextBudgetDiscardsOlderEditorsAndRefusesAnOversizedNote() async throws {
        let retention = MarkdownEditorRetention(limits: .init(maximumHiddenEditorCount: 5, maximumHiddenTextLength: 100))
        let (firstDocument, firstSession) = try await openNote("First.md")
        let (secondDocument, secondSession) = try await openNote("Second.md")
        let (largeDocument, largeSession) = try await openNote("Large.md")
        let first = RecordingEditor(session: firstSession, textLength: 60)
        let second = RecordingEditor(session: secondSession, textLength: 60)
        XCTAssertTrue(retention.keepHiddenEditor(first, owner: firstDocument))
        XCTAssertTrue(retention.keepHiddenEditor(second, owner: secondDocument))
        XCTAssertTrue(first.isDiscarded, "Together they exceed the budget, so the older one goes.")
        XCTAssertFalse(second.isDiscarded)
        let large = RecordingEditor(session: largeSession, textLength: 101)
        XCTAssertFalse(retention.keepHiddenEditor(large, owner: largeDocument), "A note larger than the whole budget is not kept.")
        XCTAssertFalse(large.isDiscarded, "The caller tears down an editor that was not kept.")
        XCTAssertEqual(retention.hiddenEditorCount, 1)
    }

    func testClosedTabOrReplacedNoteIsNeverShownAgain() async throws {
        let retention = MarkdownEditorRetention()
        let (document, session) = try await openNote("Replaced.md")
        let editor = RecordingEditor(session: session)
        XCTAssertTrue(retention.keepHiddenEditor(editor, owner: document))
        // The tab now shows another note: its old editor is stale.
        let (_, otherSession) = try await openNote("Other.md")
        document.markdownSession = otherSession
        XCTAssertNil(retention.takeEditor(for: session, owner: document))
        XCTAssertTrue(editor.isDiscarded)
        XCTAssertEqual(retention.hiddenEditorCount, 0)

        let (_, closingSession) = try await openNote("Closing.md")
        let closingEditor = RecordingEditor(session: closingSession)
        var closingDocument: TabDocument? = TabDocument()
        closingDocument?.markdownSession = closingSession
        XCTAssertTrue(retention.keepHiddenEditor(closingEditor, owner: closingDocument))
        XCTAssertFalse(retention.keepHiddenEditor(RecordingEditor(session: closingSession), owner: nil), "An editor without a tab is not kept.")
        // Closing the tab releases its document.
        closingDocument = nil
        retention.discardStaleEditors()
        XCTAssertTrue(closingEditor.isDiscarded, "Once its tab is gone, the kept editor is let go of.")
    }

    func testAnEditorOnScreenMovesToANewViewOfItsNote() async throws {
        let retention = MarkdownEditorRetention()
        let (document, session) = try await openNote("Moving.md")
        let editor = RecordingEditor(session: session)
        retention.editorDidAttach(editor)
        // The view on the other side is created before the old one is dismantled.
        XCTAssertTrue(retention.takeEditor(for: session, owner: document) === editor)
        XCTAssertEqual(retention.hiddenEditorCount, 0)
        XCTAssertFalse(editor.isDiscarded)
    }

    func testANewerEditorOfTheSameNoteReplacesAKeptOne() async throws {
        let retention = MarkdownEditorRetention()
        let (document, session) = try await openNote("Twice.md")
        let older = RecordingEditor(session: session)
        XCTAssertTrue(retention.keepHiddenEditor(older, owner: document))
        let newer = RecordingEditor(session: session)
        retention.editorDidAttach(newer)
        XCTAssertTrue(older.isDiscarded, "One note never has two histories.")
        XCTAssertEqual(retention.hiddenEditorCount, 0)
        XCTAssertTrue(retention.keepHiddenEditor(newer, owner: document))
        XCTAssertTrue(retention.takeEditor(for: session, owner: document) === newer)
    }

    func testDiscardingHiddenEditorsReleasesEveryOne() async throws {
        let retention = MarkdownEditorRetention()
        var editors: [RecordingEditor] = []
        for number in 1...3 {
            let (document, session) = try await openNote("Vault note \(number).md")
            let editor = RecordingEditor(session: session)
            retention.keepHiddenEditor(editor, owner: document)
            editors.append(editor)
        }
        retention.discardHiddenEditors()
        XCTAssertEqual(retention.hiddenEditorCount, 0)
        XCTAssertTrue(editors.allSatisfy(\.isDiscarded))
    }
}
