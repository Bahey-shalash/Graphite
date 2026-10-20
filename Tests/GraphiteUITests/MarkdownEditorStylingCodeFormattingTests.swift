import XCTest
import GraphiteCore
@testable import GraphiteUI

/// A fenced code block is formatted only when its code changed while the selection was in
/// it, and only once the selection leaves it or editing ends. A block only read, scrolled or
/// moved through is never rewritten; quoted code and languages Graphite does not format never are.
@MainActor
final class MarkdownEditorStylingCodeFormattingTests: XCTestCase {
    private static let unformattedNote = "Intro\n```c\nint main(){\nreturn 0;\n}\n```\nAfter\n"

    private func makeStyling(formatsCodeBlocks: Bool = true) -> MarkdownEditorStyling {
        var configuration = EditorConfiguration()
        configuration.formatsCodeBlocks = formatsCodeBlocks
        return MarkdownEditorStyling(configuration: configuration, propertiesSource: .afterEditSource(isShown: false), detachedViewsBudgetMegabytes: 1)
    }

    private func location(of fragment: String, in text: String) -> Int {
        (text as NSString).range(of: fragment).location
    }

    /// Moves the selection to `fragment` and reports the move as the text view does.
    private func select(_ fragment: String, in textView: StubStyledTextView, _ styling: MarkdownEditorStyling, editingEnded: Bool = false) -> MarkdownTextEdit? {
        textView.moveSelection(to: NSRange(location: location(of: fragment, in: textView.styledTextStorage.string), length: 0))
        return styling.codeFormattingEdit(afterSelectionChangeIn: textView, editingEnded: editingEnded)
    }

    func testMovingTheCursorThroughAnUnformattedBlockWithoutTypingFormatsNothing() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: Self.unformattedNote)
        XCTAssertNil(select("Intro", in: textView, styling))
        XCTAssertNil(select("return", in: textView, styling), "Entering the block")
        XCTAssertNil(select("int main", in: textView, styling), "Moving inside it")
        XCTAssertNil(select("After", in: textView, styling), "Leaving it")
        XCTAssertNil(select("int main", in: textView, styling, editingEnded: true), "Editing ending inside it")
        XCTAssertEqual(textView.styledTextStorage.string, Self.unformattedNote)
    }

    func testCodeChangedWhileTheSelectionWasInTheBlockIsFormattedWhenTheSelectionLeaves() throws {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: Self.unformattedNote)
        XCTAssertNil(select("return", in: textView, styling))
        // Typing a space in the code.
        let insertionPoint = location(of: "return 0;", in: Self.unformattedNote)
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: insertionPoint, length: 0), with: " ")
        let editedNote = textView.styledTextStorage.string
        XCTAssertNil(select("return", in: textView, styling), "Still inside the block")
        let edit = try XCTUnwrap(select("After", in: textView, styling))
        let codeRange = (editedNote as NSString).range(of: "int main(){\n return 0;\n}\n")
        XCTAssertEqual(edit.range, codeRange)
        XCTAssertEqual(edit.replacement, "int main() {\n    return 0;\n}\n")
    }

    func testCodeChangedWhileTheSelectionWasInTheBlockIsFormattedWhenEditingEnds() throws {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: Self.unformattedNote)
        XCTAssertNil(select("return", in: textView, styling))
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: location(of: "return 0;", in: Self.unformattedNote), length: 0), with: " ")
        let edit = try XCTUnwrap(select("return", in: textView, styling, editingEnded: true))
        XCTAssertEqual(edit.replacement, "int main() {\n    return 0;\n}\n")
    }

    func testABlockIsFormattedOnlyOnceForOneVisit() throws {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: Self.unformattedNote)
        XCTAssertNil(select("return", in: textView, styling))
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: location(of: "return 0;", in: Self.unformattedNote), length: 0), with: " ")
        XCTAssertNotNil(select("After", in: textView, styling))
        XCTAssertNil(select("Intro", in: textView, styling), "The visit ended with the first leaving.")
    }

    func testCodeAlreadyFormattedAfterTheChangeNeedsNoEdit() {
        let formattedNote = "Intro\n```c\nint main() {\n    return 0;\n}\n```\nAfter\n"
        let styling = makeStyling()
        let textView = StubStyledTextView(text: formattedNote)
        XCTAssertNil(select("return", in: textView, styling))
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: location(of: "0;", in: formattedNote), length: 1), with: "1")
        XCTAssertNil(select("After", in: textView, styling))
    }

    func testQuotedCodeIsNeverFormatted() {
        let quotedNote = "> ```c\n> int main(){\n> return 0;\n> }\n> ```\nAfter\n"
        let styling = makeStyling()
        let textView = StubStyledTextView(text: quotedNote)
        XCTAssertNil(select("return", in: textView, styling))
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: location(of: "return 0;", in: quotedNote), length: 0), with: " ")
        XCTAssertNil(select("After", in: textView, styling))
        XCTAssertNil(select("return", in: textView, styling, editingEnded: true))
    }

    func testALanguageGraphiteDoesNotFormatIsNeverFormatted() {
        let note = "```notalanguage\nint main(){\nreturn 0;\n}\n```\nAfter\n"
        let styling = makeStyling()
        let textView = StubStyledTextView(text: note)
        XCTAssertNil(select("return", in: textView, styling))
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: location(of: "return 0;", in: note), length: 0), with: " ")
        XCTAssertNil(select("After", in: textView, styling))
        XCTAssertNil(select("return", in: textView, styling, editingEnded: true))
    }

    func testNothingIsFormattedWhenTheSettingIsOff() {
        let styling = makeStyling(formatsCodeBlocks: false)
        let textView = StubStyledTextView(text: Self.unformattedNote)
        XCTAssertNil(select("return", in: textView, styling))
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: location(of: "return 0;", in: Self.unformattedNote), length: 0), with: " ")
        XCTAssertNil(select("After", in: textView, styling))
        XCTAssertNil(select("return", in: textView, styling, editingEnded: true))
    }

    func testNothingIsFormattedWhileAnInputMethodComposesOrTheCachesAreStale() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: Self.unformattedNote)
        XCTAssertNil(select("return", in: textView, styling))
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: location(of: "return 0;", in: Self.unformattedNote), length: 0), with: " ")
        textView.isComposingText = true
        XCTAssertNil(select("After", in: textView, styling), "Composing text is not disturbed.")
        textView.isComposingText = false
        XCTAssertNotNil(select("After", in: textView, styling), "Once the composition ends, the visit is still open.")
    }
}
