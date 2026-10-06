import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class MarkdownSessionConcurrencyTests: XCTestCase {
    private var vaultDirectory: URL!
    private var noteLocation: URL { vaultDirectory.appendingPathComponent("Note.md") }

    override func setUp() async throws {
        vaultDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MarkdownConcurrency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: noteLocation)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vaultDirectory)
    }

    private func makeSession() async throws -> MarkdownSession {
        let store = VaultStore(root: vaultDirectory)
        let notePath = try VaultPath("Note.md")
        return try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
    }

    func testSavingBeforeTheEditorUpdatesWritesQueuedInsertions() async throws {
        let session = try await makeSession()
        session.isEditorAttached = true
        session.insert(" plus an attachment", at: NSRange(location: 8, length: 0))
        XCTAssertTrue(session.hasUnsavedChanges)
        try await session.save()
        XCTAssertEqual(String(decoding: try Data(contentsOf: noteLocation), as: UTF8.self), "original plus an attachment")
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(session.pendingInsertion)
    }

    func testSaveACopyIncludesQueuedInsertions() async throws {
        let session = try await makeSession()
        session.isEditorAttached = true
        session.insert(" plus an attachment", at: NSRange(location: 8, length: 0))
        session.hasExternalConflict = true
        let copyPath = try await session.saveSeparateCopy()
        XCTAssertEqual(String(decoding: try Data(contentsOf: copyPath.url(in: vaultDirectory)), as: UTF8.self), "original plus an attachment")
        XCTAssertNil(session.pendingInsertion)
    }

    func testExternalChangeDoesNotAdoptOverQueuedInsertions() async throws {
        let session = try await makeSession()
        session.isEditorAttached = true
        session.insert(" plus an attachment", at: NSRange(location: 8, length: 0))
        try Data("external".utf8).write(to: noteLocation)
        await session.checkExternalChange()
        XCTAssertEqual(session.text, "original")
        XCTAssertNotNil(session.pendingInsertion)
        XCTAssertTrue(session.hasExternalConflict)
    }

    func testExplicitReloadDiscardsOldQueuedEditsTogetherWithOldText() async throws {
        let session = try await makeSession()
        session.isEditorAttached = true
        session.insert(" old attachment", at: NSRange(location: 8, length: 0))
        try Data("external".utf8).write(to: noteLocation)
        try await session.reload()
        XCTAssertEqual(session.text, "external")
        XCTAssertNil(session.pendingInsertion, "An edit aimed at the discarded version cannot be applied to the external version")
    }

    func testTypingWhileReloadReadsDoesNotDiscardNewEdits() async throws {
        let session = try await makeSession()
        try Data("external".utf8).write(to: noteLocation)
        let readStarted = expectation(description: "Reload reached its coordinated read")
        let presenter = PausingNotePresenter(location: noteLocation, readStarted: readStarted)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { presenter.resumeRead(); NSFileCoordinator.removeFilePresenter(presenter) }

        let reload = Task { try await session.reload() }
        await fulfillment(of: [readStarted], timeout: 5)
        session.text = "typed while loading"
        presenter.resumeRead()
        do {
            try await reload.value
            XCTFail("A reload must refuse to replace text edited after it began")
        } catch {
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertEqual(session.text, "typed while loading")
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testTypingWhileSaveACopyReloadsRemainsRecoverable() async throws {
        let session = try await makeSession()
        session.text = "my edits"
        session.hasExternalConflict = true
        try Data("external".utf8).write(to: noteLocation)
        let readStarted = expectation(description: "Copy was saved and the original is being read")
        let presenter = PausingNotePresenter(location: noteLocation, readStarted: readStarted)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { presenter.resumeRead(); NSFileCoordinator.removeFilePresenter(presenter) }

        let copying = Task { try await session.saveSeparateCopy() }
        await fulfillment(of: [readStarted], timeout: 5)
        session.text = "my edits plus newer typing"
        presenter.resumeRead()
        let copyPath = try await copying.value

        XCTAssertEqual(String(decoding: try Data(contentsOf: copyPath.url(in: vaultDirectory)), as: UTF8.self), "my edits")
        XCTAssertEqual(session.text, "my edits plus newer typing")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertTrue(session.hasExternalConflict)
    }

    func testQueuedCommandKeepsSelectionInsideItsReplacement() async throws {
        let session = try await makeSession()
        session.text = "abc tail"
        session.isEditorAttached = true
        session.insert(" extra", at: NSRange(location: 3, length: 0))
        let command = try XCTUnwrap(MarkdownEditing.edit(for: .bold, in: session.text as NSString,
                                                        selection: NSRange(location: 0, length: 3), indentUnit: "\t"))
        session.apply(command)
        applyQueuedInsertions(to: session)
        XCTAssertEqual(session.text, "**abc** extra tail")
        XCTAssertEqual(session.selection, NSRange(location: 2, length: 3))
    }

    func testCommandDoesNotOverwriteAnInsertionInsideItsReplacement() async throws {
        let session = try await makeSession()
        session.text = "abc tail"
        session.isEditorAttached = true
        session.insert(" extra", at: NSRange(location: 2, length: 0))
        let command = try XCTUnwrap(MarkdownEditing.edit(for: .bold, in: session.text as NSString,
                                                        selection: NSRange(location: 0, length: 3), indentUnit: "\t"))
        session.apply(command)
        applyQueuedInsertions(to: session)
        XCTAssertEqual(session.text, "ab extrac tail")
        XCTAssertNotNil(session.errorMessage)
    }

    func testQueuedCommandCursorStaysBeforeInsertedClosingMarkers() async throws {
        let session = try await makeSession()
        session.text = "abc"
        session.isEditorAttached = true
        session.insert("!", at: NSRange(location: 3, length: 0))
        let command = try XCTUnwrap(MarkdownEditing.edit(for: .insertWikilink, in: session.text as NSString,
                                                        selection: NSRange(location: 3, length: 0), indentUnit: "\t"))
        session.apply(command)
        applyQueuedInsertions(to: session)
        XCTAssertEqual(session.text, "abc![[]]")
        XCTAssertEqual(session.selection, NSRange(location: 6, length: 0))
    }

    private func applyQueuedInsertions(to session: MarkdownSession) {
        while let insertion = session.pendingInsertion {
            session.text = (session.text as NSString).replacingCharacters(in: insertion.range, with: insertion.text)
            session.selection = insertion.selectionAfter ?? NSRange(location: insertion.range.location + (insertion.text as NSString).length, length: 0)
            session.markInsertionApplied(insertion)
        }
    }
}

/// Immutable coordination objects; the semaphore synchronizes the worker queue with the test.
private final class PausingNotePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let readStarted: XCTestExpectation
    private let readMayContinue = DispatchSemaphore(value: 0)

    init(location: URL, readStarted: XCTestExpectation) {
        presentedItemURL = location.resolvingSymlinksInPath()
        self.readStarted = readStarted
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
    }

    func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        readStarted.fulfill()
        _ = readMayContinue.wait(timeout: .now() + 10)
        reader(nil)
    }

    func resumeRead() { readMayContinue.signal() }
}
