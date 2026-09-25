import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Live Preview's edit tracking, which keeps blocks and styling in step with the text
/// whichever path changed it. These run the same logic the iPad editor runs.
@MainActor
final class UiEditorEditTrackingTests: XCTestCase {
    /// Replaces `range` of `source` and returns the new text and the edit as the text
    /// storage reports it.
    private func edit(_ source: String, replacing range: NSRange, with replacement: String) -> (text: NSString, edit: CharacterEdit) {
        let newText = (source as NSString).replacingCharacters(in: range, with: replacement) as NSString
        let replacementLength = (replacement as NSString).length
        return (newText, CharacterEdit(editedRange: NSRange(location: range.location, length: replacementLength), changeInLength: replacementLength - range.length))
    }

    private func textState(for source: String) -> LivePreviewTextState {
        let textState = LivePreviewTextState()
        textState.update(source: source as NSString, findsBlocks: true, isRendered: { _ in true })
        return textState
    }

    // MARK: Stale blocks during an edit (C1)

    /// Backspace on the line above a table that ends the note used to style the new text
    /// with the table's old range, which runs past the end and raised NSRangeException.
    func testBlocksNeverRunPastTheTextAfterBackspaceAboveATableAtTheEnd() {
        let source = "Intro line\n| a | b |\n| - | - |\n| 1 | 2 |"
        let textState = textState(for: source)
        XCTAssertEqual(textState.blockEntries.map(\.range), [NSRange(location: 11, length: 29)])
        let (newText, backspace) = edit(source, replacing: NSRange(location: 9, length: 1), with: "")
        XCTAssertTrue(textState.recordCharacterEdit(backspace, revealedRange: NSRange(location: 0, length: 11)))
        // Until the blocks are found again, nothing may style with them.
        XCTAssertTrue(textState.cachesDescribeOldText)
        textState.update(source: newText, findsBlocks: true, isRendered: { _ in true })
        XCTAssertFalse(textState.cachesDescribeOldText)
        XCTAssertEqual(textState.blockEntries.map(\.range), [NSRange(location: 10, length: 29)])
        for entry in textState.blockEntries { XCTAssertLessThanOrEqual(NSMaxRange(entry.range), newText.length) }
    }

    /// Only the first edit since the caches last described the text schedules a settle.
    func testOnlyTheFirstEditBeforeASettleReportsItself() {
        let textState = textState(for: "one two")
        XCTAssertTrue(textState.recordCharacterEdit(CharacterEdit(editedRange: NSRange(location: 7, length: 1), changeInLength: 1), revealedRange: nil))
        XCTAssertFalse(textState.recordCharacterEdit(CharacterEdit(editedRange: NSRange(location: 8, length: 1), changeInLength: 1), revealedRange: nil))
        XCTAssertEqual(textState.history.revision, 2)
    }

    /// The cursor right after a block that does not end with a line break is inside it; a
    /// block ending in `\r\n` does end with one.
    func testCursorAfterABlockEndingInCarriageReturnLineFeedIsOutsideIt() {
        let crlfSource = "| a |\r\n| - |\r\nnext" as NSString
        XCTAssertFalse(LivePreviewBlockActivity.isActive(blockRange: NSRange(location: 0, length: 14), selection: NSRange(location: 14, length: 0), in: crlfSource))
        let unterminatedSource = "| a |\n| - |" as NSString
        XCTAssertTrue(LivePreviewBlockActivity.isActive(blockRange: NSRange(location: 0, length: 11), selection: NSRange(location: 11, length: 0), in: unterminatedSource))
        // A block that no longer fits the text is never active, and never read past the end.
        XCTAssertFalse(LivePreviewBlockActivity.isActive(blockRange: NSRange(location: 0, length: 40), selection: NSRange(location: 40, length: 0), in: unterminatedSource))
    }

    // MARK: What an edit restyles (F169, F184, F170)

    func testBackspaceInsideAParagraphRestylesOnlyItsLine() {
        let source = "First paragraph here\n\nSome paragraph text here\n\nLast line"
        let textState = textState(for: source)
        let (newText, backspace) = edit(source, replacing: NSRange(location: 30, length: 1), with: "")
        textState.recordCharacterEdit(backspace, revealedRange: NSRange(location: 22, length: 25))
        textState.update(source: newText, findsBlocks: true, isRendered: { _ in true })
        let revealedRange = newText.lineRange(for: NSRange(location: 29, length: 0))
        XCTAssertEqual(textState.takeRestylePlan(revealedRange: revealedRange), .ranges([NSRange(location: 22, length: 24)]))
    }

    func testReturnAndTypingOnAnAliasedLinkLineDoNotRestyleEverything() {
        let source = "Intro\n\nSee [[Note|alias]] here\n\nEnd"
        let textState = textState(for: source)
        let (typedText, typing) = edit(source, replacing: NSRange(location: 29, length: 0), with: "s")
        textState.recordCharacterEdit(typing, revealedRange: nil)
        textState.update(source: typedText, findsBlocks: true, isRendered: { _ in true })
        guard case .ranges = textState.takeRestylePlan(revealedRange: nil) else { return XCTFail("Typing on a link line restyled the whole note") }

        let (returnText, newLine) = edit(typedText as String, replacing: NSRange(location: 30, length: 0), with: "\n")
        textState.recordCharacterEdit(newLine, revealedRange: nil)
        textState.update(source: returnText, findsBlocks: true, isRendered: { _ in true })
        guard case .ranges = textState.takeRestylePlan(revealedRange: nil) else { return XCTFail("Return restyled the whole note") }
    }

    /// Typing `>` at the start of the line after a callout extends the callout; the whole
    /// callout is restyled, not only the typed line, so none of it stays concealed.
    func testExtendingACalloutRestylesTheWholeCallout() {
        let source = "> [!note] Title\n> body line\nnext"
        let textState = textState(for: source)
        XCTAssertEqual(textState.blockEntries.map(\.range), [NSRange(location: 0, length: 28)])
        let (newText, typing) = edit(source, replacing: NSRange(location: 28, length: 0), with: ">")
        textState.recordCharacterEdit(typing, revealedRange: NSRange(location: 28, length: 4))
        textState.update(source: newText, findsBlocks: true, isRendered: { _ in true })
        XCTAssertEqual(textState.blockEntries.map(\.range), [NSRange(location: 0, length: 33)])
        guard case .ranges(let ranges) = textState.takeRestylePlan(revealedRange: newText.lineRange(for: NSRange(location: 29, length: 0))) else {
            return XCTFail("Expected a partial restyle")
        }
        XCTAssertTrue(ranges.contains { range in NSIntersectionRange(range, NSRange(location: 0, length: 33)) == NSRange(location: 0, length: 33) })
    }

    func testOpeningACodeFenceRestylesEverything() {
        let source = "``\nlet value = 1\n"
        let textState = textState(for: source)
        let (newText, typing) = edit(source, replacing: NSRange(location: 2, length: 0), with: "`")
        textState.recordCharacterEdit(typing, revealedRange: nil)
        textState.update(source: newText, findsBlocks: true, isRendered: { _ in true })
        XCTAssertEqual(textState.takeRestylePlan(revealedRange: nil), .everything)
    }

    /// Undo moves the cursor far from where it was; the lines revealed before the edit are
    /// restyled with it, so their markup does not stay showing.
    func testLinesRevealedBeforeAnEditAreRestyledWithIt() {
        let source = "line one\nline two\nline three\nline four\n"
        let textState = textState(for: source)
        let (newText, undo) = edit(source, replacing: NSRange(location: 0, length: 0), with: "x")
        textState.recordCharacterEdit(undo, revealedRange: NSRange(location: 29, length: 10))
        textState.update(source: newText, findsBlocks: true, isRendered: { _ in true })
        guard case .ranges(let ranges) = textState.takeRestylePlan(revealedRange: NSRange(location: 0, length: 10)) else { return XCTFail("Expected a partial restyle") }
        XCTAssertTrue(ranges.contains(NSRange(location: 30, length: 10)), "\(ranges)")
    }

    /// Markup that starts right after the revealed lines shows too, so when an edit moves
    /// the revealed lines away, the line after the old ones is restyled to hide it again.
    func testLineAfterTheLinesRevealedBeforeAnEditIsRestyledWithThem() {
        let source = "line one\nline two\nline three\n**bold** four\nline five\n"
        let textState = textState(for: source)
        let (newText, undo) = edit(source, replacing: NSRange(location: 0, length: 0), with: "x")
        textState.recordCharacterEdit(undo, revealedRange: NSRange(location: 18, length: 11))
        textState.update(source: newText, findsBlocks: true, isRendered: { _ in true })
        guard case .ranges(let ranges) = textState.takeRestylePlan(revealedRange: NSRange(location: 0, length: 10)) else { return XCTFail("Expected a partial restyle") }
        let followingLine = newText.range(of: "**bold** four\n")
        XCTAssertTrue(ranges.contains { range in NSIntersectionRange(range, followingLine) == followingLine }, "\(ranges)")
    }

    // MARK: Moving blocks instead of scanning again (F275)

    func testTypingInAParagraphMovesBlocksWithoutFindingThemAgain() {
        let source = "Paragraph\n\n| a |\n| - |\n\nMore"
        let textState = textState(for: source)
        let tableKey = textState.blockEntries.first?.key
        let (newText, typing) = edit(source, replacing: NSRange(location: 4, length: 0), with: "xyz")
        textState.recordCharacterEdit(typing, revealedRange: nil)
        textState.update(source: newText, findsBlocks: true, isRendered: { _ in true })
        // The moved range is exactly where a new scan finds the table.
        let scannedRanges = LivePreviewBlockScanner.blocks(in: newText).map(\.range)
        XCTAssertEqual(scannedRanges.count, 1)
        XCTAssertEqual(scannedRanges.first?.location, 14)
        XCTAssertEqual(textState.blockEntries.map(\.range), scannedRanges)
        XCTAssertEqual(textState.blockEntries.first?.key, tableKey)
    }

    func testTypingBlockSyntaxFindsBlocksAgain() {
        let source = "Paragraph\n\nrule\n"
        let textState = textState(for: source)
        XCTAssertTrue(textState.blockEntries.isEmpty)
        let (newText, typing) = edit(source, replacing: NSRange(location: 11, length: 4), with: "---")
        textState.recordCharacterEdit(typing, revealedRange: nil)
        textState.update(source: newText, findsBlocks: true, isRendered: { _ in true })
        XCTAssertEqual(textState.blockEntries.map(\.block.kind), [.horizontalRule])
    }

    // MARK: Taps (F185, F172)

    func testQuotedTaskCheckboxCanBeTapped() {
        let source = "> - [ ] quoted task\n" as NSString
        XCTAssertEqual(LivePreviewTapTargets.taskCheckboxRange(at: 5, in: source), NSRange(location: 4, length: 3))
    }

    func testTaskAndLinkInsideCodeAreText() {
        let source = "```\n- [ ] example [[Note]]\n```\nInline `[[Other]]` code\n" as NSString
        XCTAssertNil(LivePreviewTapTargets.taskCheckboxRange(at: 7, in: source))
        XCTAssertTrue(LivePreviewTapTargets.isInsideCode(20, in: source))
        XCTAssertTrue(LivePreviewTapTargets.isInsideCode(42, in: source))
        XCTAssertFalse(LivePreviewTapTargets.isInsideCode(2, in: "a [[Note]]" as NSString))
    }

    // MARK: Drops onto a selection (F667)

    /// Two images dropped onto a selected word: the first replaces the word and the
    /// second goes after the first, instead of replacing part of its embed.
    func testSecondDroppedItemGoesAfterTheFirst() {
        var history = CharacterEditHistory()
        let selection = NSRange(location: 6, length: 5)
        let request = (range: selection, revision: history.revision)
        let firstEmbed = "![[Pasted image 1.png]]" as NSString
        history.record(CharacterEdit(editedRange: NSRange(location: 6, length: firstEmbed.length), changeInLength: firstEmbed.length - 5))
        XCTAssertEqual(history.insertionTarget(request.range, requestedAt: request.revision), NSRange(location: 6 + firstEmbed.length, length: 0))
    }

    /// Two files dropped at one point, with no selection: the second goes after the first,
    /// not before it, even though typing at that point would stay after both.
    func testItemsDroppedAtAPointKeepTheirOrder() throws {
        var history = CharacterEditHistory()
        var pendingRequests = PendingInsertionRequests()
        let dropRequest = InsertionRequest(range: NSRange(location: 6, length: 0), revision: history.revision)
        pendingRequests.remember(dropRequest)
        pendingRequests.remember(dropRequest)

        let firstRequest = try XCTUnwrap(pendingRequests.take(preparedFor: dropRequest.range))
        XCTAssertEqual(firstRequest.currentTarget(in: history), dropRequest.range)
        let firstEmbed = "![[First.png]]\n" as NSString
        history.record(CharacterEdit(editedRange: NSRange(location: 6, length: firstEmbed.length), changeInLength: firstEmbed.length))
        pendingRequests.placeRemainingItems(of: firstRequest, after: 6 + firstEmbed.length, at: history.revision)

        // Typing before both moves the second item with the text.
        history.record(CharacterEdit(editedRange: NSRange(location: 0, length: 2), changeInLength: 2))
        let secondRequest = try XCTUnwrap(pendingRequests.take(preparedFor: dropRequest.range))
        XCTAssertEqual(secondRequest.currentTarget(in: history), NSRange(location: 8 + firstEmbed.length, length: 0))
        XCTAssertNil(pendingRequests.take(preparedFor: dropRequest.range))
    }

    /// An insertion that answers no paste or drop, such as a command, is made as prepared,
    /// and the oldest requests go once too many wait.
    func testPendingInsertionRequestsMatchOnlyTheirOwnRangeAndStayBounded() {
        var pendingRequests = PendingInsertionRequests()
        pendingRequests.remember(InsertionRequest(range: NSRange(location: 3, length: 0), revision: 0))
        XCTAssertNil(pendingRequests.take(preparedFor: NSRange(location: 4, length: 0)))
        for requestNumber in 0..<(PendingInsertionRequests.maximumCount + 5) {
            pendingRequests.remember(InsertionRequest(range: NSRange(location: 100 + requestNumber, length: 0), revision: 0))
        }
        XCTAssertEqual(pendingRequests.count, PendingInsertionRequests.maximumCount)
        XCTAssertNil(pendingRequests.take(preparedFor: NSRange(location: 3, length: 0)))
    }

    func testDropTargetMovesPastTypingBeforeIt() {
        var history = CharacterEditHistory()
        let requestRevision = history.revision
        history.record(CharacterEdit(editedRange: NSRange(location: 2, length: 3), changeInLength: 3))
        XCTAssertEqual(history.insertionTarget(NSRange(location: 10, length: 0), requestedAt: requestRevision), NSRange(location: 13, length: 0))
        // Typing inside a range a completion was going to replace cancels the replacement.
        XCTAssertNil(history.replacedRange(NSRange(location: 1, length: 4), computedAt: requestRevision))
        XCTAssertEqual(history.replacedRange(NSRange(location: 5, length: 2), computedAt: requestRevision), NSRange(location: 8, length: 2))
    }

    // MARK: Replacing the text in place (F171)

    func testTextDifferenceReplacesOnlyTheChangedFrontmatter() throws {
        let oldText = "---\ntags: a\n---\nBody typed here\n" as NSString
        let newText = "---\ntags: a, b\n---\nBody typed here\n" as NSString
        let (replacedRange, replacementRange) = try XCTUnwrap(TextDifference.changedRanges(from: oldText, to: newText))
        XCTAssertEqual(oldText.replacingCharacters(in: replacedRange, with: newText.substring(with: replacementRange)), newText as String)
        XCTAssertLessThanOrEqual(replacedRange.length, 1)
        XCTAssertLessThanOrEqual(NSMaxRange(replacedRange), 12)
        XCTAssertNil(TextDifference.changedRanges(from: oldText, to: oldText))
    }

    func testTextDifferenceNeverSplitsAComposedCharacter() throws {
        let oldText = "a👍🏽b" as NSString
        let newText = "a👍🏿b" as NSString
        let (replacedRange, replacementRange) = try XCTUnwrap(TextDifference.changedRanges(from: oldText, to: newText))
        XCTAssertEqual(oldText.substring(with: replacedRange), "👍🏽")
        XCTAssertEqual(newText.substring(with: replacementRange), "👍🏿")
    }

    func testCursorAfterAFrontmatterChangeStaysOnTheSameCharacter() {
        let edit = CharacterEdit(editedRange: NSRange(location: 10, length: 4), changeInLength: 3)
        XCTAssertEqual(TextRangeMapping.insertionTarget(NSRange(location: 25, length: 0), through: edit), NSRange(location: 28, length: 0))
    }
}
