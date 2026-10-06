#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Live Preview showing markup one element at a time, in the hosted workspace's own text
/// view: what shows under the cursor, typing and composing text, taps, and how little a
/// cursor move restyles.
@MainActor
final class LivePreviewRevealTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectory = nil
    }

    private static let note = """
    # Heading with **bold** words

    Plain text with **bold text**, a [[Target|link]], ==highlight==, `code` and $x^2$ here.

    - item with **bold** and [[Target]]
    - [ ] task with ==mark==

    **bold with _italic_ and [[Target]]** end

    مرحبا **غامق** 👍🏽 ==مميز== [[Target|رابط]]

    """

    // MARK: What shows

    func testOnlyTheElementUnderTheCursorShowsItsMarkup() async throws {
        let (editor, _) = try await openNote(Self.note)
        let source = editor.text as NSString
        XCTAssertEqual(shownMarkup(in: editor), [], "Nothing shows while the note is only being read.")
        attachScreenshot(named: "1 Reading, no markup")

        try await startEditing(editor, at: source.range(of: "Plain").location + 2)
        XCTAssertEqual(shownMarkup(in: editor), [], "The cursor's line stays rendered away from the cursor.")
        attachScreenshot(named: "2 Cursor in plain text")

        moveCursor(to: source.range(of: "bold text").location + 3, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["**", "**"])
        attachScreenshot(named: "3 Cursor in bold text")

        moveCursor(to: source.range(of: "|link").location + 3, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["[[Target|", "]]"])
        attachScreenshot(named: "4 Cursor in an aliased link")

        moveCursor(to: source.range(of: "$x^2$").location + 2, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["$x^2$"])
        attachScreenshot(named: "5 Cursor in a formula")

        moveCursor(to: source.range(of: "==highlight==").location, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["==", "=="], "The edge of an element counts as inside it.")
        moveCursor(to: source.range(of: "`code`").location + 3, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["`", "`"])

        moveCursor(to: source.range(of: "Heading").location + 2, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["# "])
        attachScreenshot(named: "6 Cursor on a heading")
        moveCursor(to: source.range(of: "**bold** words").location + 4, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["# ", "**", "**"])

        moveCursor(to: source.range(of: "item").location + 2, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["-"])
        attachScreenshot(named: "7 Cursor in a list item")
        moveCursor(to: source.range(of: "task").location + 2, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["-", "[ ]"])

        moveCursor(to: source.range(of: "_italic_").location + 3, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["**", "**", "_", "_"])
        attachScreenshot(named: "8 Cursor in italic inside bold")
        moveCursor(to: source.range(of: "[[Target]]** end").location + 4, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["[[", "]]", "**", "**"])

        moveCursor(to: source.range(of: "غامق").location + 2, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["**", "**"])
        attachScreenshot(named: "9 Cursor in right-to-left bold text")
        moveCursor(to: source.range(of: "رابط").location + 2, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["[[Target|", "]]"])

        // A selection from the bold text to the highlight shows each element it touches.
        let selectionStart = source.range(of: "bold text").location + 2
        select(NSRange(location: selectionStart, length: source.range(of: "==highlight==").location + 4 - selectionStart), in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["[[Target|", "]]", "**", "**", "==", "=="])
        attachScreenshot(named: "10 Selection over three elements")

        editor.resignFirstResponder()
        try await waitUntil { !editor.isFirstResponder }
        XCTAssertEqual(shownMarkup(in: editor), [])
    }

    /// The caret is drawn at the height of its line wherever it is put: it never sits
    /// against hidden markup, whose characters are a hundredth of a point tall.
    func testCursorKeepsItsPlaceAndItsHeightWhereverItGoes() async throws {
        let (editor, _) = try await openNote(Self.note)
        let source = editor.text as NSString
        try await startEditing(editor, at: 0)
        var checkedLocations = 0
        for lineText in ["Plain text", "- item with", "**bold with _italic_", "مرحبا"] {
            let lineRange = source.lineRange(for: NSRange(location: source.range(of: lineText).location, length: 0))
            for location in lineRange.location..<NSMaxRange(lineRange) where source.rangeOfComposedCharacterSequence(at: location).location == location {
                moveCursor(to: location, in: editor)
                XCTAssertEqual(editor.selectedRange, NSRange(location: location, length: 0), "The cursor moved when markup showed or hid.")
                editor.layoutIfNeeded()
                let caret = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.start))
                XCTAssertGreaterThan(caret.height, 12, "The caret at \(location) of \(lineText) is as small as hidden markup.")
                assertShownMarkupMatchesSelection(in: editor)
                checkedLocations += 1
            }
        }
        XCTAssertGreaterThan(checkedLocations, 150)
    }

    // MARK: Typing

    func testTypingDeletingUndoAndRedoKeepTheMarkupOfTheElementBeingEdited() async throws {
        let (editor, session) = try await openNote(Self.note)
        let source = editor.text as NSString
        let bold = source.range(of: "**bold text**")
        func boldMarkers() -> [NSRange] {
            let currentBold = (editor.text as NSString).range(of: "\\*\\*bold text[a-z!]*\\*\\*", options: .regularExpression)
            return [NSRange(location: currentBold.location, length: 2), NSRange(location: NSMaxRange(currentBold) - 2, length: 2)]
        }

        // At the end of the bold words, before the closing `**`.
        try await startEditing(editor, at: NSMaxRange(bold) - 2)
        typeAsKeyboard("s", in: editor)
        try await waitUntil { session.text.contains("**bold texts**") }
        XCTAssertEqual(editor.selectedRange, NSRange(location: NSMaxRange(bold) - 1, length: 0))
        XCTAssertTrue(boldMarkers().allSatisfy { marker in isShownAsWritten(marker, in: editor) })
        assertShownMarkupMatchesSelection(in: editor)

        // After the closing `**`: still the element's edge, so its markup stays in view.
        moveCursor(to: NSMaxRange(bold) + 1, in: editor)
        XCTAssertTrue(boldMarkers().allSatisfy { marker in isShownAsWritten(marker, in: editor) })
        attachScreenshot(named: "Cursor right after the closing markup")
        typeAsKeyboard("!", in: editor)
        try await waitUntil { session.text.contains("**bold texts**!") }
        XCTAssertEqual(editor.selectedRange, NSRange(location: NSMaxRange(bold) + 2, length: 0))
        XCTAssertFalse(boldMarkers().contains { marker in isShownAsWritten(marker, in: editor) }, "A character typed after bold text separates the cursor from it.")
        assertShownMarkupMatchesSelection(in: editor)

        pressBackspace(in: editor)
        try await waitUntil { !session.text.contains("**bold texts**!") }
        XCTAssertEqual(editor.selectedRange, NSRange(location: NSMaxRange(bold) + 1, length: 0))
        XCTAssertTrue(boldMarkers().allSatisfy { marker in isShownAsWritten(marker, in: editor) })
        assertShownMarkupMatchesSelection(in: editor)

        // Undo and redo from elsewhere in the note move the cursor to the change.
        try await Task.sleep(for: .milliseconds(50))
        moveCursor(to: source.range(of: "task").location, in: editor)
        assertShownMarkupMatchesSelection(in: editor)
        let undoManager = try XCTUnwrap(editor.undoManager)
        var undoCount = 0
        while undoManager.canUndo, undoCount < 8 {
            undoManager.undo()
            undoCount += 1
            try await settle(editor, session)
            assertShownMarkupMatchesSelection(in: editor)
        }
        XCTAssertEqual(session.text, Self.note)
        while undoManager.canRedo {
            undoManager.redo()
            try await settle(editor, session)
            assertShownMarkupMatchesSelection(in: editor)
        }
        XCTAssertTrue(session.text.contains("**bold texts**"))
    }

    /// Text being composed by an input method is left alone until it is committed, and the
    /// element it is typed into keeps its markup.
    func testComposingTextInsideBoldTextIsNotDisturbed() async throws {
        let (editor, session) = try await openNote(Self.note)
        let source = editor.text as NSString
        let bold = source.range(of: "**bold text**")
        try await startEditing(editor, at: NSMaxRange(bold) - 2)
        editor.setMarkedText("にほ", selectedRange: NSRange(location: 2, length: 0))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNotNil(editor.markedTextRange, "Styling ended the composition.")
        XCTAssertTrue(editor.text.contains("**bold textにほ**"))
        editor.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNotNil(editor.markedTextRange)
        editor.unmarkText()
        try await waitUntil { session.text.contains("**bold text日本**") }
        try await settle(editor, session)
        XCTAssertNil(editor.markedTextRange)
        XCTAssertEqual(editor.selectedRange, NSRange(location: NSMaxRange(bold), length: 0), "The cursor stays after the composed text.")
        let committedBold = (editor.text as NSString).range(of: "**bold text日本**")
        XCTAssertTrue(isShownAsWritten(NSRange(location: NSMaxRange(committedBold) - 2, length: 2), in: editor))
        assertShownMarkupMatchesSelection(in: editor)
        attachScreenshot(named: "After composing text inside bold text")

        // A word replaced as autocorrection replaces it.
        let word = (editor.text as NSString).range(of: "highlight")
        let wordStart = try XCTUnwrap(editor.position(from: editor.beginningOfDocument, offset: word.location))
        let wordEnd = try XCTUnwrap(editor.position(from: wordStart, offset: word.length))
        editor.replace(try XCTUnwrap(editor.textRange(from: wordStart, to: wordEnd)), withText: "highlighted")
        try await waitUntil { session.text.contains("==highlighted==") }
        try await settle(editor, session)
        assertShownMarkupMatchesSelection(in: editor)
    }

    /// Obsidian's typing helpers: pairs, wrapping a selection, lists that continue, and
    /// the keyboard toolbar's commands.
    func testPairingListsAndToolbarCommandsKeepWorking() async throws {
        let (editor, session) = try await openNote("First line\n\n- item one\n\nword to wrap\n")
        let source = editor.text as NSString

        // A selected word wrapped by typing `*` twice becomes bold, and stays selected.
        try await startEditing(editor, at: 0)
        select(source.range(of: "wrap"), in: editor)
        typeAsKeyboard("**", in: editor)
        try await waitUntil { session.text.contains("to **wrap**") }
        XCTAssertEqual((editor.text as NSString).substring(with: editor.selectedRange), "wrap")
        XCTAssertEqual(shownMarkup(in: editor), ["**", "**"])
        assertShownMarkupMatchesSelection(in: editor)

        // Return at the end of a list item continues the list; its text stays rendered.
        moveCursor(to: NSMaxRange((editor.text as NSString).range(of: "- item one")), in: editor)
        typeAsKeyboard("\n", in: editor)
        try await waitUntil { session.text.contains("- item one\n- \n") }
        typeAsKeyboard("two `code`", in: editor)
        try await waitUntil { session.text.contains("- two `code`") }
        assertShownMarkupMatchesSelection(in: editor)
        XCTAssertTrue(shownMarkup(in: editor).contains("`"), "The code the cursor has just typed shows its backticks.")

        // Brackets typed in pairs leave the cursor inside the link being written.
        moveCursor(to: "First line".utf16.count, in: editor)
        typeAsKeyboard(" [[", in: editor)
        try await waitUntil { session.text.hasPrefix("First line [[]]") }
        XCTAssertEqual(editor.selectedRange, NSRange(location: "First line [[".utf16.count, length: 0))
        typeAsKeyboard("Tar", in: editor)
        try await waitUntil { session.text.hasPrefix("First line [[Tar]]") }
        XCTAssertEqual(shownMarkup(in: editor), ["[[", "]]"])
        assertShownMarkupMatchesSelection(in: editor)
        // Backspace between an empty pair removes both halves.
        for _ in 0..<3 { pressBackspace(in: editor) }
        pressBackspace(in: editor)
        try await waitUntil { session.text.hasPrefix("First line []") }

        // The toolbar's Highlight command wraps the selection.
        select((editor.text as NSString).range(of: "word"), in: editor)
        editor.runCommand?(.highlight)
        try await waitUntil { session.text.contains("==word==") }
        try await settle(editor, session)
        assertShownMarkupMatchesSelection(in: editor)
        XCTAssertTrue(shownMarkup(in: editor).contains("=="))
        attachScreenshot(named: "After pairing, a list and toolbar commands")
    }

    func testChosenLinkSuggestionIsInsertedWithTheCursorAfterIt() async throws {
        let (editor, session) = try await openNote("See \n\nnext **bold** line\n", otherNotes: ["Target note.md": "Target.\n"])
        try await startEditing(editor, at: 4)
        typeAsKeyboard("[[Targ", in: editor)
        try await waitUntil { session.text.hasPrefix("See [[Targ]]") }
        try await waitUntil { session.completion.isVisible }
        XCTAssertEqual(shownMarkup(in: editor), ["[[", "]]"])
        attachScreenshot(named: "Link suggestions while typing a link")
        session.completion.accept()
        try await waitUntil { session.text.hasPrefix("See [[Target note]]") }
        try await settle(editor, session)
        XCTAssertEqual(editor.selectedRange, NSRange(location: "See [[Target note]]".utf16.count, length: 0))
        XCTAssertEqual(shownMarkup(in: editor), ["[[", "]]"], "The cursor is at the link's edge right after it is inserted.")
        assertShownMarkupMatchesSelection(in: editor)
        moveCursor(to: 2, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), [])
    }

    // MARK: Taps

    /// A tap lands where UIKit's closest position to the touch is. On rendered text that
    /// is the touched character, with nothing visible between it and the cursor, however
    /// much hidden markup lies around it.
    func testTappingRenderedTextPlacesTheCursorAtTheTouchedCharacter() async throws {
        let (editor, _) = try await openNote(Self.note)
        let source = editor.text as NSString
        // The cursor is on another line, so the paragraph is fully rendered.
        try await startEditing(editor, at: source.range(of: "Heading").location)
        editor.layoutIfNeeded()
        var checkedCharacters = 0
        for lineText in ["Plain text", "- item with", "**bold with _italic_"] {
            let lineRange = source.lineRange(for: NSRange(location: source.range(of: lineText).location, length: 0))
            let lineEnd = NSMaxRange(lineRange) - 1
            for location in lineRange.location..<lineEnd where isShownAsWritten(NSRange(location: location, length: 1), in: editor) {
                let glyphRect = try firstRect(of: NSRange(location: location, length: 1), in: editor)
                guard glyphRect.width > 1 else { continue }
                let tappedPosition = try XCTUnwrap(editor.closestPosition(to: CGPoint(x: glyphRect.midX, y: glyphRect.midY)))
                let cursorLocation = editor.offset(from: editor.beginningOfDocument, to: tappedPosition)
                // The cursor may be anywhere in the hidden markup right around the character.
                var lowestLocation = location
                while lowestLocation > lineRange.location, !isShownAsWritten(NSRange(location: lowestLocation - 1, length: 1), in: editor) { lowestLocation -= 1 }
                var highestLocation = location + 1
                while highestLocation < lineEnd, !isShownAsWritten(NSRange(location: highestLocation, length: 1), in: editor) { highestLocation += 1 }
                XCTAssertTrue((lowestLocation...highestLocation).contains(cursorLocation),
                              "A tap on \(source.substring(with: NSRange(location: location, length: 1)).debugDescription) at \(location) put the cursor at \(cursorLocation).")
                checkedCharacters += 1
            }
        }
        XCTAssertGreaterThan(checkedCharacters, 80)

        // A tap on the drawn formula reaches its source, which then shows.
        let formula = source.range(of: "$x^2$")
        let formulaEnd = try firstRect(of: NSRange(location: NSMaxRange(formula) - 1, length: 1), in: editor)
        let tappedPosition = try XCTUnwrap(editor.closestPosition(to: CGPoint(x: formulaEnd.midX, y: formulaEnd.midY)))
        let cursorLocation = editor.offset(from: editor.beginningOfDocument, to: tappedPosition)
        XCTAssertTrue((formula.location...NSMaxRange(formula)).contains(cursorLocation))
        moveCursor(to: cursorLocation, in: editor)
        XCTAssertEqual(shownMarkup(in: editor), ["$x^2$"])
    }

    /// Graphite takes a tap itself only on a link whose markup is hidden, which it
    /// follows, or on a drawn checkbox; everywhere else the tap places the cursor.
    func testOnlyRenderedLinksAndCheckboxesTakeTheTapFromTheCursor() async throws {
        let (editor, _) = try await openNote(Self.note)
        let source = editor.text as NSString
        let coordinator = try XCTUnwrap(editor.delegate as? NativeMarkdownEditor.Coordinator)
        let touch = TouchAtPoint()
        editor.addGestureRecognizer(touch)
        defer { editor.removeGestureRecognizer(touch) }
        func takesTap(onCharacterAt location: Int) throws -> Bool {
            editor.layoutIfNeeded()
            let glyphRect = try firstRect(of: NSRange(location: location, length: 1), in: editor)
            touch.point = CGPoint(x: glyphRect.midX, y: glyphRect.midY)
            return coordinator.gestureRecognizerShouldBegin(touch)
        }
        let paragraphLink = source.range(of: "|link").location + 2
        let listLink = source.range(of: "[[Target]]\n").location + 4
        let boldWord = source.range(of: "bold text").location + 2
        let checkbox = source.range(of: "[ ]").location + 1

        try await startEditing(editor, at: source.range(of: "Plain").location)
        XCTAssertTrue(try takesTap(onCharacterAt: paragraphLink), "A rendered link on the cursor's own line is followed.")
        XCTAssertTrue(try takesTap(onCharacterAt: listLink))
        XCTAssertFalse(try takesTap(onCharacterAt: boldWord), "Bold text with hidden markup takes the cursor.")
        XCTAssertFalse(try takesTap(onCharacterAt: source.range(of: "Plain").location + 1))
        XCTAssertTrue(try takesTap(onCharacterAt: checkbox))

        // With the cursor in the link, its markup shows and a tap there edits it.
        moveCursor(to: paragraphLink, in: editor)
        XCTAssertFalse(try takesTap(onCharacterAt: paragraphLink))
        XCTAssertTrue(try takesTap(onCharacterAt: listLink))
        // On the task's line the checkbox shows as `[ ]`.
        moveCursor(to: source.range(of: "task").location, in: editor)
        XCTAssertFalse(try takesTap(onCharacterAt: checkbox))
        XCTAssertTrue(try takesTap(onCharacterAt: paragraphLink))
    }

    // MARK: Rendered blocks

    func testTableShowsItsSourceOnlyWhileTheCursorIsInItAndIsLeftAloneOtherwise() async throws {
        let (editor, _) = try await openNote("Intro **bold** and [[Target]] here\n\n| a | b |\n| - | - |\n| 1 | 2 |\n\nAfter ==mark== text\n")
        let source = editor.text as NSString
        let table = NSRange(location: source.range(of: "| a").location, length: source.range(of: "\nAfter").location - source.range(of: "| a").location)
        func isTableConcealed() -> Bool { !isShownAsWritten(NSRange(location: table.location, length: 5), in: editor) }
        XCTAssertTrue(isTableConcealed())

        try await startEditing(editor, at: 2)
        let sentinel = NSAttributedString.Key("LivePreviewRevealTestsSentinel")
        editor.textStorage.addAttribute(sentinel, value: true, range: table)
        // Moving along the line above the table, element to element, never restyles it.
        for location in [source.range(of: "bold").location + 1, source.range(of: "Target").location + 2, NSMaxRange(source.range(of: "here"))] {
            moveCursor(to: location, in: editor)
            assertShownMarkupMatchesSelection(in: editor, skipping: table)
        }
        var sentinelRange = NSRange(location: NSNotFound, length: 0)
        XCTAssertNotNil(editor.textStorage.attribute(sentinel, at: table.location, longestEffectiveRange: &sentinelRange, in: table))
        XCTAssertEqual(sentinelRange, table, "A cursor moving beside a rendered table restyled it.")
        XCTAssertTrue(isTableConcealed())

        moveCursor(to: table.location + 3, in: editor)
        XCTAssertFalse(isTableConcealed(), "The cursor in the table shows its source.")
        attachScreenshot(named: "Cursor in a table shows its source")
        moveCursor(to: source.range(of: "mark").location + 1, in: editor)
        XCTAssertTrue(isTableConcealed())
        XCTAssertTrue(isShownAsWritten(source.range(of: "=="), in: editor))
        try await Task.sleep(for: .milliseconds(300))
        attachScreenshot(named: "Table rendered again, cursor in a highlight")
    }

    // MARK: Long notes

    /// In the editor itself, a cursor jumping between two bold words of a long note
    /// changes the attributes of their four markers and of nothing else.
    func testMovingTheCursorInALongNoteRestylesOnlyTheMarkersInvolved() async throws {
        let lineCount = 3_000
        let text = (0..<lineCount).map { index in "Paragraph \(index) with **bold \(index)** text, a [[Note \(index)|link]], ==mark== and more words in a line." }
            .joined(separator: "\n\n")
        let (editor, _) = try await openNote(text)
        let source = editor.text as NSString
        let sentinel = NSAttributedString.Key("LivePreviewRevealTestsSentinel")
        func cursorLocation(inBoldOfLine index: Int) -> Int { source.range(of: "**bold \(index)**").location + 4 }
        try await startEditing(editor, at: cursorLocation(inBoldOfLine: 5))
        XCTAssertEqual(shownMarkup(in: editor, within: source.lineRange(for: NSRange(location: cursorLocation(inBoldOfLine: 5), length: 0))), ["**", "**"])

        editor.textStorage.addAttribute(sentinel, value: true, range: NSRange(location: 0, length: source.length))
        moveCursor(to: cursorLocation(inBoldOfLine: 2_900), in: editor)
        let firstBold = source.range(of: "**bold 5**")
        let farBold = source.range(of: "**bold 2900**")
        let markers = [firstBold, farBold].flatMap { bold in [NSRange(location: bold.location, length: 2), NSRange(location: NSMaxRange(bold) - 2, length: 2)] }
        XCTAssertEqual(rangesWithout(sentinel, in: editor), markers, "A far jump restyled more than the four markers.")
        XCTAssertTrue(isShownAsWritten(markers[2], in: editor) && !isShownAsWritten(markers[0], in: editor))

        // Along one line: into plain text, into the link, and on within the link.
        editor.textStorage.addAttribute(sentinel, value: true, range: NSRange(location: 0, length: source.length))
        let farLine = source.lineRange(for: NSRange(location: farBold.location, length: 0))
        moveCursor(to: farLine.location + 3, in: editor)
        XCTAssertEqual(rangesWithout(sentinel, in: editor), [markers[2], markers[3]])
        editor.textStorage.addAttribute(sentinel, value: true, range: NSRange(location: 0, length: source.length))
        moveCursor(to: farLine.location + 5, in: editor)
        XCTAssertEqual(rangesWithout(sentinel, in: editor), [], "A move inside plain text restyled something.")

        // The editor's own work for each move along the line, timed apart from UIKit's:
        // setting a selection in code far down a long note costs UIKit itself tens of
        // milliseconds in the simulator, with no delegate to tell.
        let coordinator = try XCTUnwrap(editor.delegate)
        let moveCount = 200
        var uikitSeconds: TimeInterval = 0
        var editorSeconds: TimeInterval = 0
        for move in 0..<moveCount {
            editor.delegate = nil
            let uikitStart = ProcessInfo.processInfo.systemUptime
            editor.selectedRange = NSRange(location: farLine.location + (move * 3) % (farLine.length - 1), length: 0)
            uikitSeconds += ProcessInfo.processInfo.systemUptime - uikitStart
            editor.delegate = coordinator
            let editorStart = ProcessInfo.processInfo.systemUptime
            coordinator.textViewDidChangeSelection?(editor)
            editorSeconds += ProcessInfo.processInfo.systemUptime - editorStart
        }
        let editorMillisecondsPerMove = editorSeconds * 1_000 / Double(moveCount)
        print("Live Preview cursor move in the hosted editor, \(source.length)-unit note: Graphite \(String(format: "%.3f", editorMillisecondsPerMove)) ms, "
              + "UIKit setting the selection \(String(format: "%.3f", uikitSeconds * 1_000 / Double(moveCount))) ms each")
        XCTAssertLessThan(editorMillisecondsPerMove, 4)
        assertShownMarkupMatchesSelection(in: editor, within: farLine)
    }

    // MARK: Helpers

    /// Opens a vault holding the note in Live Preview and returns its text view.
    private func openNote(_ text: String, otherNotes: [String: String] = ["Target.md": "Target.\n"]) async throws -> (MarkdownTextView, MarkdownSession) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LivePreviewReveal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        try Data(text.utf8).write(to: directory.appendingPathComponent("Reveal.md"))
        for (name, otherText) in otherNotes { try Data(otherText.utf8).write(to: directory.appendingPathComponent(name)) }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Reveal.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .livePreview
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        try await waitUntil { self.editors(in: controller).contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        let editor = try XCTUnwrap(editors(in: controller).first { editor in editor.text == session.text })
        editor.layoutIfNeeded()
        return (editor, session)
    }

    private func editors(in controller: UIViewController) -> [MarkdownTextView] {
        descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    /// Puts the cursor in the note as a tap does: the text view starts editing, and the
    /// markup at the cursor is revealed on the next turn of the run loop.
    private func startEditing(_ editor: MarkdownTextView, at location: Int) async throws {
        editor.beginEditing()
        try await waitUntil { editor.isFirstResponder }
        moveCursor(to: location, in: editor)
        try await Task.sleep(for: .milliseconds(80))
    }

    private func moveCursor(to location: Int, in editor: MarkdownTextView) {
        select(NSRange(location: location, length: 0), in: editor)
    }

    private func select(_ range: NSRange, in editor: MarkdownTextView) {
        editor.selectedRange = range
        // UIKit reports a selection it changed itself; a selection set in code is reported here.
        editor.delegate?.textViewDidChangeSelection?(editor)
    }

    /// Types as the keyboard does: the editor is asked about each character first, which
    /// is where pairs, lists and suggestions act.
    private func typeAsKeyboard(_ text: String, in editor: MarkdownTextView) {
        for character in text {
            let typedText = String(character)
            if editor.delegate?.textView?(editor, shouldChangeTextIn: editor.selectedRange, replacementText: typedText) != false {
                editor.insertText(typedText)
            }
        }
    }

    private func pressBackspace(in editor: MarkdownTextView) {
        let selection = editor.selectedRange
        guard selection.length > 0 || selection.location > 0 else { return }
        let deletedRange = selection.length > 0 ? selection : NSRange(location: selection.location - 1, length: 1)
        if editor.delegate?.textView?(editor, shouldChangeTextIn: deletedRange, replacementText: "") != false {
            editor.deleteBackward()
        }
    }

    /// Waits for an edit to reach the session and for its styling to follow.
    private func settle(_ editor: MarkdownTextView, _ session: MarkdownSession) async throws {
        try await waitUntil { session.text == editor.text }
        try await Task.sleep(for: .milliseconds(50))
    }

    private func firstRect(of range: NSRange, in editor: MarkdownTextView) throws -> CGRect {
        let start = try XCTUnwrap(editor.position(from: editor.beginningOfDocument, offset: range.location))
        let end = try XCTUnwrap(editor.position(from: start, offset: range.length))
        return editor.firstRect(for: try XCTUnwrap(editor.textRange(from: start, to: end)))
    }

    /// Whether the characters of `range` are drawn as written: not shrunk to nothing, not
    /// clear, and not standing in for a drawn bullet, checkbox, bar, separator or formula.
    private func isShownAsWritten(_ range: NSRange, in editor: MarkdownTextView) -> Bool {
        var isShown = true
        editor.textStorage.enumerateAttributes(in: range) { attributes, _, _ in
            if let font = attributes[.font] as? UIFont, font.pointSize < 1 { isShown = false }
            if let color = attributes[.foregroundColor] as? UIColor, color.cgColor.alpha == 0 { isShown = false }
            if attributes[ConcealedReplacement.attributeKey] != nil { isShown = false }
        }
        return isShown
    }

    /// The spans whose markup Live Preview hides or draws over away from the selection.
    private func markupSpans(in editor: MarkdownTextView, within range: NSRange? = nil) -> [MarkdownStyleSpan] {
        let source = NSString(string: editor.text)
        let drawnStyles: Set<MarkdownStyle> = [.concealableMarker, .subpathSeparator, .taskMarker]
        return MarkdownStyleScanner.spans(in: source, range: range ?? NSRange(location: 0, length: source.length)).filter { span in
            let spanText = source.substring(with: span.range)
            return drawnStyles.contains(span.style) || (span.style == .math && span.inlineElementRange != nil)
                || (span.style == .listMarker && ["-", "*", "+"].contains(spanText)) || (span.style == .syntaxMarker && spanText.hasPrefix(">"))
        }
    }

    /// The markup shown as written, in the scanner's order.
    private func shownMarkup(in editor: MarkdownTextView, within range: NSRange? = nil) -> [String] {
        let source = NSString(string: editor.text)
        return markupSpans(in: editor, within: range).filter { span in isShownAsWritten(span.range, in: editor) }.map { span in source.substring(with: span.range) }
    }

    /// Every piece of markup shows exactly when the selection touches its element or is
    /// on its line, so nothing an earlier selection or edit showed is left over.
    private func assertShownMarkupMatchesSelection(in editor: MarkdownTextView, within range: NSRange? = nil, skipping skippedRange: NSRange? = nil,
                                                   file: StaticString = #filePath, line: UInt = #line) {
        let source = NSString(string: editor.text)
        let revealedMarkup = editor.isFirstResponder ? RevealedMarkup(selection: editor.selectedRange, in: source) : nil
        for span in markupSpans(in: editor, within: range) where skippedRange.map({ skipped in NSIntersectionRange(skipped, span.range).length == 0 }) ?? true {
            XCTAssertEqual(isShownAsWritten(span.range, in: editor), revealedMarkup?.shows(span) ?? false,
                           "\(source.substring(with: span.range).debugDescription) at \(span.range) with the selection at \(editor.selectedRange)", file: file, line: line)
        }
    }

    /// The ranges of the note that no longer carry `sentinel`, which every restyle removes.
    private func rangesWithout(_ sentinel: NSAttributedString.Key, in editor: MarkdownTextView) -> [NSRange] {
        var ranges: [NSRange] = []
        editor.textStorage.enumerateAttribute(sentinel, in: NSRange(location: 0, length: editor.textStorage.length)) { value, range, _ in
            if value == nil { ranges.append(range) }
        }
        return ranges
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted editor did not reach the expected state.")
    }
}

/// A tap recognizer that reports a touch at a chosen point, to ask the editor what it
/// would do with a tap there.
private final class TouchAtPoint: UITapGestureRecognizer {
    var point = CGPoint.zero

    override func location(in view: UIView?) -> CGPoint { point }
}
#endif
