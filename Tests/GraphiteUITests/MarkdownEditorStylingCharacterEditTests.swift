import XCTest
@testable import GraphiteUI

/// Every change to the characters, whichever path made it, is recorded as soon as the text
/// storage has processed it, before the text view's own callbacks run; until the blocks are
/// found again nothing may act on ranges from the older text.
@MainActor
final class MarkdownEditorStylingCharacterEditTests: XCTestCase {
    private func makeStyling() -> MarkdownEditorStyling {
        MarkdownEditorStyling(configuration: EditorConfiguration(), propertiesSource: .afterEditSource(isShown: false), detachedViewsBudgetMegabytes: 1)
    }

    func testACharacterEditIsRecordedAndMarksTheCachesAsDescribingOldText() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: "Hello world")
        styling.observeCharacterEdits(in: textView, settle: {})
        defer { styling.stopObservingCharacterEdits() }
        XCTAssertEqual(styling.textState.history.revision, 0)
        XCTAssertFalse(styling.textState.cachesDescribeOldText)

        textView.styledTextStorage.replaceCharacters(in: NSRange(location: 5, length: 0), with: ",")
        XCTAssertEqual(styling.textState.history.revision, 1)
        XCTAssertTrue(styling.textState.cachesDescribeOldText)
        XCTAssertFalse(styling.canStyle(textView), "Nothing may be styled with ranges from the older text.")
        XCTAssertTrue(styling.concealedEntries(in: textView).isEmpty)
    }

    func testEachCharacterEditRaisesTheRevisionByOneWhateverMadeIt() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: "Hello world")
        styling.observeCharacterEdits(in: textView, settle: {})
        defer { styling.stopObservingCharacterEdits() }
        let textStorage = textView.styledTextStorage

        textStorage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "Howdy")
        XCTAssertEqual(styling.textState.history.revision, 1, "replaceCharacters")
        textStorage.mutableString.insert("!", at: 0)
        XCTAssertEqual(styling.textState.history.revision, 2, "the storage's mutable string")
        textStorage.setAttributedString(NSAttributedString(string: "Whole new text"))
        XCTAssertEqual(styling.textState.history.revision, 3, "setting the whole text")
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "w")
        textStorage.replaceCharacters(in: NSRange(location: 1, length: 1), with: "H")
        textStorage.endEditing()
        XCTAssertEqual(styling.textState.history.revision, 4, "Edits made within one editing session are one change.")
    }

    func testAttributeOnlyChangesAreNotCharacterEdits() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: "Hello world")
        styling.observeCharacterEdits(in: textView, settle: {})
        defer { styling.stopObservingCharacterEdits() }
        textView.styledTextStorage.addAttribute(.foregroundColor, value: PlatformColor.red, range: NSRange(location: 0, length: 5))
        XCTAssertEqual(styling.textState.history.revision, 0)
        XCTAssertFalse(styling.textState.cachesDescribeOldText)
    }

    func testTheEditIsRecordedWithItsRangeAndLengthChange() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: "Hello world")
        styling.observeCharacterEdits(in: textView, settle: {})
        defer { styling.stopObservingCharacterEdits() }
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: 6, length: 5), with: "there, friend")
        let edit = styling.textState.editSinceBlockScan?.edit
        XCTAssertEqual(edit?.editedRange, NSRange(location: 6, length: 13))
        XCTAssertEqual(edit?.changeInLength, 8)
    }

    func testOnlyTheFirstEditSinceTheCachesLastDescribedTheTextSettlesOnTheNextTurn() async {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: "Hello world")
        let settled = expectation(description: "settled")
        var settleCount = 0
        styling.observeCharacterEdits(in: textView, settle: {
            settleCount += 1
            settled.fulfill()
        })
        defer { styling.stopObservingCharacterEdits() }
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "a")
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "b")
        XCTAssertEqual(settleCount, 0, "Settling waits for the next turn of the run loop.")
        await fulfillment(of: [settled], timeout: 5)
        XCTAssertEqual(settleCount, 1)
        XCTAssertEqual(styling.textState.history.revision, 2)
    }

    func testNothingSettlesWhileAnInputMethodIsComposing() async {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: "Hello world")
        textView.isComposingText = true
        var settleCount = 0
        styling.observeCharacterEdits(in: textView, settle: { settleCount += 1 })
        defer { styling.stopObservingCharacterEdits() }
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "a")
        let turnPassed = expectation(description: "next turn")
        DispatchQueue.main.async { turnPassed.fulfill() }
        await fulfillment(of: [turnPassed], timeout: 5)
        XCTAssertEqual(settleCount, 0)
        XCTAssertTrue(styling.textState.cachesDescribeOldText)
    }

    func testFindingTheBlocksAgainEndsTheStaleness() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: "Hello world")
        styling.observeCharacterEdits(in: textView, settle: {})
        defer { styling.stopObservingCharacterEdits() }
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "a")
        XCTAssertTrue(styling.textState.cachesDescribeOldText)
        styling.updateTextState(of: textView)
        XCTAssertFalse(styling.textState.cachesDescribeOldText)
        XCTAssertTrue(styling.canStyle(textView))
        XCTAssertEqual(styling.textState.source as String, "aHello world")
    }

    func testStoppingTheObservationStopsRecording() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: "Hello world")
        styling.observeCharacterEdits(in: textView, settle: {})
        styling.stopObservingCharacterEdits()
        textView.styledTextStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "a")
        XCTAssertEqual(styling.textState.history.revision, 0)
    }
}
