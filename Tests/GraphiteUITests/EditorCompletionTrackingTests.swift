import XCTest
import GraphiteCore
@testable import GraphiteUI

/// What both editors remember about their suggestions (ED-08): an accepted suggestion's
/// edits move past typing done while they were prepared, are refused when that typing
/// changed their text, and belong to the suggestion accepted last; plugins hear each change
/// and cursor move once.
final class EditorCompletionTrackingTests: XCTestCase {
    /// `[[Op` replaced by `[[Optics]]` in "See [[Op".
    private let linkEdit = MarkdownTextEdit(range: NSRange(location: 6, length: 2), replacement: "Optics]]", selectionAfter: NSRange(location: 14, length: 0))

    private func typed(_ length: Int, at location: Int) -> CharacterEdit {
        CharacterEdit(editedRange: NSRange(location: location, length: length), changeInLength: length)
    }

    /// The list opens at the history's revision and is then accepted: it closed without Escape.
    private func acceptSuggestionFound(at history: CharacterEditHistory, in tracking: inout EditorCompletionTracking) {
        tracking.listDidUpdate(isOpen: true, at: history.revision)
        tracking.recordAcceptedSuggestion(isListOpen: false)
    }

    func testEditsMovePastTypingBeforeWhatTheyReplace() throws {
        var history = CharacterEditHistory()
        var tracking = EditorCompletionTracking()
        acceptSuggestionFound(at: history, in: &tracking)
        history.record(typed(3, at: 0))
        let movedEdits = try XCTUnwrap(tracking.editsMovedPastTyping([linkEdit], history: history))
        let expected = MarkdownTextEdit(range: NSRange(location: 9, length: 2), replacement: "Optics]]", selectionAfter: NSRange(location: 17, length: 0))
        XCTAssertEqual(movedEdits, [expected])
    }

    func testEditsAreRefusedWhenTypingChangedTheTextTheyReplace() {
        var history = CharacterEditHistory()
        var tracking = EditorCompletionTracking()
        acceptSuggestionFound(at: history, in: &tracking)
        history.record(typed(1, at: 7))
        XCTAssertNil(tracking.editsMovedPastTyping([linkEdit], history: history), "A query replaced in the middle of new text would corrupt the note.")
    }

    func testEditsWithoutAnAcceptedSuggestionAreMadeAsGiven() {
        var tracking = EditorCompletionTracking()
        var history = CharacterEditHistory()
        history.record(typed(3, at: 0))
        XCTAssertEqual(tracking.editsMovedPastTyping([linkEdit], history: history), [linkEdit])
    }

    func testEscapeLeavesNothingToMove() {
        var history = CharacterEditHistory()
        var tracking = EditorCompletionTracking()
        tracking.listDidUpdate(isOpen: true, at: history.revision)
        tracking.forgetOpenSuggestions()
        tracking.recordAcceptedSuggestion(isListOpen: false)
        history.record(typed(3, at: 0))
        XCTAssertEqual(tracking.editsMovedPastTyping([linkEdit], history: history), [linkEdit], "A list closed with Escape was not accepted.")
    }

    func testTheSuggestionAcceptedLastDecidesAndTheOlderOnesAreForgotten() throws {
        var history = CharacterEditHistory()
        var tracking = EditorCompletionTracking()
        for _ in 0..<9 {
            acceptSuggestionFound(at: history, in: &tracking)
            history.record(typed(1, at: 0))
        }
        // Only the typing after the ninth suggestion was found moves its edits.
        let movedEdits = try XCTUnwrap(tracking.editsMovedPastTyping([linkEdit], history: history))
        XCTAssertEqual(movedEdits.map(\.range), [NSRange(location: 7, length: 2)])
        history.record(typed(1, at: 0))
        XCTAssertEqual(tracking.editsMovedPastTyping([linkEdit], history: history), [linkEdit], "The revisions were used up.")
    }

    func testALinkIsSuggestedBeforePluginsAreAsked() {
        var tracking = EditorCompletionTracking()
        var pluginQuestions = 0
        let context = tracking.context(in: "See [[Op", cursor: 8, textRevision: 1) { pluginQuestions += 1; return 1 }
        guard case .link = context else { return XCTFail("\(String(describing: context))") }
        XCTAssertEqual(pluginQuestions, 0)
    }

    func testPluginsHearEachChangeAndCursorMoveOnce() {
        var tracking = EditorCompletionTracking()
        var heard: [Int] = []
        let pluginEditorDidChange: () -> Int? = { heard.append(heard.count + 1); return heard.count }
        XCTAssertEqual(tracking.context(in: "Mood :", cursor: 6, textRevision: 1, pluginEditorDidChange: pluginEditorDidChange), .pluginSuggestion(revision: 1))
        XCTAssertEqual(tracking.context(in: "Mood :", cursor: 6, textRevision: 1, pluginEditorDidChange: pluginEditorDidChange), .pluginSuggestion(revision: 1),
                       "Asked again for the same change and cursor, the last answer stands.")
        XCTAssertEqual(tracking.context(in: "Mood :", cursor: 2, textRevision: 1, pluginEditorDidChange: pluginEditorDidChange), .pluginSuggestion(revision: 2))
        XCTAssertEqual(heard, [1, 2])
        XCTAssertNil(tracking.context(in: "Mood :", cursor: 2, textRevision: 2) { nil }, "No plugin suggests for this change.")
    }
}
