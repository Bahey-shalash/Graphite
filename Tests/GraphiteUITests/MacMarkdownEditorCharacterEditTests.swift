#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

/// Whatever path changes the Mac note's characters (typing, undo and redo, find and replace,
/// setting the whole text) is recorded in the editor's edit tracking as one edit.
@MainActor
final class MacMarkdownEditorCharacterEditTests: XCTestCase {
    private var fixture: MacMarkdownEditorFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    private func makeFixture(text: String = "Hello world") async throws -> MacMarkdownEditorFixture {
        let fixture = try await MacMarkdownEditorFixture(text: text)
        self.fixture = fixture
        return fixture
    }

    /// Replaces `range` the way a text view's own editing paths do: asked, replaced in the
    /// storage, reported.
    private func replaceThroughTheTextView(_ range: NSRange, with replacement: String, in fixture: MacMarkdownEditorFixture) throws {
        XCTAssertTrue(fixture.textView.shouldChangeText(in: range, replacementString: replacement))
        try XCTUnwrap(fixture.textView.textStorage).replaceCharacters(in: range, with: replacement)
        fixture.textView.didChangeText()
    }

    func testTypingRaisesTheRevisionByOne() async throws {
        let fixture = try await makeFixture()
        let textState = fixture.coordinator.styling.textState
        let revisionBefore = textState.history.revision
        fixture.textView.insertText("!", replacementRange: NSRange(location: 11, length: 0))
        XCTAssertEqual(fixture.textView.string, "Hello world!")
        XCTAssertEqual(textState.history.revision, revisionBefore + 1)
    }

    func testUndoAndRedoEachRaiseTheRevisionByOne() async throws {
        let fixture = try await makeFixture()
        let textState = fixture.coordinator.styling.textState
        fixture.textView.insertText("!", replacementRange: NSRange(location: 11, length: 0))
        let revisionBeforeUndo = textState.history.revision

        fixture.coordinator.noteUndoManager.undo()
        XCTAssertEqual(fixture.textView.string, "Hello world")
        XCTAssertEqual(textState.history.revision, revisionBeforeUndo + 1)

        fixture.coordinator.noteUndoManager.redo()
        XCTAssertEqual(fixture.textView.string, "Hello world!")
        XCTAssertEqual(textState.history.revision, revisionBeforeUndo + 2)
    }

    func testFindAndReplaceRaisesTheRevisionByOne() async throws {
        let fixture = try await makeFixture()
        let textState = fixture.coordinator.styling.textState
        let revisionBefore = textState.history.revision
        try replaceThroughTheTextView(NSRange(location: 6, length: 5), with: "there", in: fixture)
        XCTAssertEqual(fixture.textView.string, "Hello there")
        XCTAssertEqual(textState.history.revision, revisionBefore + 1)
    }

    func testSettingTheWholeTextRaisesTheRevisionByOne() async throws {
        let fixture = try await makeFixture()
        let textState = fixture.coordinator.styling.textState
        let revisionBefore = textState.history.revision
        fixture.textView.string = "Something else entirely"
        XCTAssertEqual(textState.history.revision, revisionBefore + 1)
    }

    func testTheEditIsRecordedBeforeTheCachesAreFoundAgain() async throws {
        let fixture = try await makeFixture()
        let textState = fixture.coordinator.styling.textState
        // The storage reports the edit before any text view callback runs, so a callback
        // that runs during the change already finds the caches marked as describing old text.
        var cachesDescribedOldTextDuringTheChange: Bool?
        let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                                                              object: fixture.textView.textStorage, queue: nil) { _ in
            MainActor.assumeIsolated { cachesDescribedOldTextDuringTheChange = textState.cachesDescribeOldText }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        fixture.textView.string = "Replaced"
        // Observers run in the order they were added: the editor's came first.
        XCTAssertEqual(cachesDescribedOldTextDuringTheChange, true)
    }
}
#endif
