import Foundation
import XCTest
@testable import GraphiteCore

/// Regression tests for the editing commands in `MarkdownEditing`: line endings other than
/// LF, characters wider than one UTF-16 unit, and where the cursor goes.
final class CoreEditingFixTests: XCTestCase {
    private func applying(_ edit: MarkdownTextEdit?, to text: String) -> String? {
        edit.map { edit in (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) }
    }

    private func cursor(_ location: Int) -> NSRange { NSRange(location: location, length: 0) }

    private func cursorAtEnd(_ text: String) -> NSRange { cursor((text as NSString).length) }

    private func continuing(_ text: String, at selection: NSRange? = nil, indentUnit: String = "\t", tabSize: Int = 4) -> String? {
        applying(MarkdownEditing.continuingList(in: text as NSString, selection: selection ?? cursorAtEnd(text), indentUnit: indentUnit, tabSize: tabSize), to: text)
    }

    // MARK: Move lines

    func testMovingLinesKeepsCRLFLineEndings() {
        let text = "a\r\nb\r\nc"
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: text as NSString, selection: cursor(3)), to: text), "b\r\na\r\nc")
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: false, in: text as NSString, selection: cursor(0)), to: text), "b\r\na\r\nc")
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: text as NSString, selection: cursor(6)), to: text), "a\r\nc\r\nb",
                       "The last line takes the line break of the line above, which stays CRLF.")
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: false, in: text as NSString, selection: cursor(3)), to: text), "a\r\nc\r\nb")
        let tasks = "- [ ] a\r\n- [ ] b\r\n- [ ] c\r\n"
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: tasks as NSString, selection: cursor(10)), to: tasks), "- [ ] b\r\n- [ ] a\r\n- [ ] c\r\n")
    }

    func testMovingLinesKeepsCarriageReturnAndLineSeparatorEndings() {
        let carriageReturns = "a\rb\rc"
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: carriageReturns as NSString, selection: cursor(2)), to: carriageReturns), "b\ra\rc")
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: carriageReturns as NSString, selection: cursor(4)), to: carriageReturns), "a\rc\rb")
        let separators = "a\nb\u{2028}c"
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: separators as NSString, selection: cursor(2)), to: separators), "b\u{2028}a\nc")
    }

    /// Every way of moving any line of notes with mixed line endings keeps the same lines,
    /// each with a line ending the note already had, and a selection inside the new text.
    func testMovingLinesNeverMergesLinesOrLeavesTheText() {
        let endings = ["\n", "\r\n", "\r", "\u{2028}"]
        for firstEnding in endings {
            for secondEnding in endings {
                for trailing in ["", firstEnding] {
                    // An empty line ending in LF placed after a line ending in a lone CR reads as
                    // one CRLF, whatever the command does, so those two are not mixed here.
                    let lineEndings = [firstEnding, secondEnding, trailing]
                    if lineEndings.contains("\r") && lineEndings.contains("\n") { continue }
                    let text = "one" + firstEnding + "two" + secondEnding + "three" + trailing
                    let length = (text as NSString).length
                    for location in 0...length {
                        for selectionLength in [0, 1, 4] where location + selectionLength <= length {
                            for up in [true, false] {
                                let selection = NSRange(location: location, length: selectionLength)
                                guard let edit = MarkdownEditing.movingLines(up: up, in: text as NSString, selection: selection),
                                      let moved = applying(edit, to: text) else { continue }
                                let context = "\(text.debugDescription) \(selection) up: \(up) -> \(moved.debugDescription)"
                                XCTAssertEqual(lines(of: moved).sorted(), lines(of: text).sorted(), context)
                                XCTAssertEqual((moved as NSString).length, length, context)
                                XCTAssertLessThanOrEqual(NSMaxRange(edit.selectionAfter), (moved as NSString).length, context)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The note's lines, with the empty line after a final line break, which a cursor can
    /// be on and move like any other line.
    private func lines(of text: String) -> [String] {
        let foundationText = text as NSString
        let lines = MarkdownEditing.lineContents(in: foundationText, range: NSRange(location: 0, length: foundationText.length))
        return lines.map(\.content) + (lines.last?.ending.isEmpty == false ? [""] : [])
    }

    func testMovingDownOntoTheLastLineKeepsTheSelectionInTheText() {
        let text = "a\nb"
        let edit = MarkdownEditing.movingLines(up: false, in: text as NSString, selection: NSRange(location: 0, length: 2))
        XCTAssertEqual(applying(edit, to: text), "b\na")
        XCTAssertEqual(edit?.selectionAfter, NSRange(location: 2, length: 1))
        let longer = "[word* [ ] \n\"["
        let longerEdit = MarkdownEditing.movingLines(up: false, in: longer as NSString, selection: NSRange(location: 4, length: 8))
        XCTAssertEqual(applying(longerEdit, to: longer), "\"[\n[word* [ ] ")
        XCTAssertEqual(longerEdit?.selectionAfter, NSRange(location: 7, length: 7))
    }

    // MARK: Tasks and lists

    func testToggleTaskReplacesAnEmojiStatusWhole() {
        XCTAssertEqual(applying(MarkdownEditing.togglingTask(in: "- [🙂] x" as NSString, selection: cursor(7)), to: "- [🙂] x"), "- [ ] x")
        XCTAssertEqual(applying(MarkdownEditing.togglingTask(in: "* [😀] " as NSString, selection: cursor(0)), to: "* [😀] "), "* [ ] ")
    }

    func testToggleTaskOnABareMarkerAddsTheSpace() {
        XCTAssertEqual(applying(MarkdownEditing.togglingTask(in: "-" as NSString, selection: cursor(1)), to: "-"), "- [ ] ")
        XCTAssertEqual(applying(MarkdownEditing.togglingTask(in: "1." as NSString, selection: cursor(2)), to: "1."), "1. [ ] ")
    }

    func testToggleTaskLeavesACursorBeforeTheInsertionInPlace() {
        let listItem = MarkdownEditing.togglingTask(in: "- buy" as NSString, selection: cursor(0))
        XCTAssertEqual(applying(listItem, to: "- buy"), "- [ ] buy")
        XCTAssertEqual(listItem.selectionAfter, cursor(0))
        let indented = MarkdownEditing.togglingTask(in: "  buy" as NSString, selection: cursor(0))
        XCTAssertEqual(applying(indented, to: "  buy"), "  - [ ] buy")
        XCTAssertEqual(indented.selectionAfter, cursor(0))
        let beforeText = MarkdownEditing.togglingTask(in: "- buy" as NSString, selection: cursor(2))
        XCTAssertEqual(beforeText.selectionAfter, cursor(6), "A cursor in front of the text stays in front of it, after the new checkbox.")
        let checked = MarkdownEditing.togglingTask(in: "- [ ] buy" as NSString, selection: cursor(9))
        XCTAssertEqual(checked.selectionAfter, cursor(9))
    }

    func testIndentKeepsACursorBeforeTheQuoteMarker() {
        let edit = MarkdownEditing.indenting(in: "> - a" as NSString, selection: cursor(0), indentUnit: "\t")
        XCTAssertEqual(applying(edit, to: "> - a"), "> \t- a")
        XCTAssertEqual(edit.selectionAfter, cursor(0))
    }

    func testPrefixCommandsKeepACombiningMarkAfterTheMarkerSpace() {
        XCTAssertEqual(applying(MarkdownEditing.indenting(in: "> \u{301}x" as NSString, selection: cursor(4), indentUnit: "\t"), to: "> \u{301}x"), "> \t\u{301}x")
        XCTAssertEqual(applying(MarkdownEditing.togglingList(numbered: true, in: "- \u{301}x" as NSString, selection: cursor(4)), to: "- \u{301}x"), "1. \u{301}x")
        XCTAssertEqual(applying(MarkdownEditing.togglingTask(in: "- \u{301}x" as NSString, selection: cursor(4)), to: "- \u{301}x"), "- [ ] \u{301}x")
        XCTAssertEqual(applying(MarkdownEditing.outdenting(in: "> \t\u{301}x" as NSString, selection: cursor(5), indentUnit: "\t"), to: "> \t\u{301}x"), "> \u{301}x")
        XCTAssertEqual(applying(MarkdownEditing.togglingList(numbered: false, in: "  - \u{301}x" as NSString, selection: cursor(6)), to: "  - \u{301}x"), "  \u{301}x")
    }

    func testOutdentUsesTheTabSizeForSpacesInATabVault() {
        let edit = MarkdownEditing.outdenting(in: "    - a" as NSString, selection: cursor(7), indentUnit: "\t", tabSize: 2)
        XCTAssertEqual(applying(edit, to: "    - a"), "  - a")
        XCTAssertEqual(continuing("    - ", indentUnit: "\t", tabSize: 2), "  - ")
        XCTAssertEqual(applying(MarkdownEditing.outdenting(in: "    - a" as NSString, selection: cursor(7), indentUnit: "\t"), to: "    - a"), "- a",
                       "Four spaces are one level with the default tab size.")
    }

    // MARK: List lines

    func testListLineReadsWhatTheLineHas() {
        XCTAssertEqual(MarkdownEditing.listLine("-")?.spacing, "", "No space is invented after a marker that ends the line.")
        XCTAssertEqual(MarkdownEditing.listLine("- [ ]")?.prefixLength, 5)
        XCTAssertEqual(MarkdownEditing.listLine("- [ ] a")?.prefixLength, 6)
        XCTAssertNil(MarkdownEditing.listLine("- - -"), "A thematic break is not a list item.")
        XCTAssertNil(MarkdownEditing.listLine("* * *"))
        XCTAssertEqual(MarkdownEditing.listLine("> - - -")?.isListItem, false)
        XCTAssertEqual(MarkdownEditing.listLine("- - a")?.isListItem, true)
        XCTAssertNil(MarkdownEditing.listLine("\u{661}. a"), "Only ASCII digits number a list.")
        XCTAssertTrue(MarkdownEditing.isThematicBreak("- - -"))
        XCTAssertTrue(MarkdownEditing.isThematicBreak("***"))
        XCTAssertFalse(MarkdownEditing.isThematicBreak("- - a"))
    }

    func testReturnOnAnEmptyTaskWithoutTrailingSpaceEndsTheList() {
        XCTAssertEqual(continuing("- a\n- [ ]"), "- a\n")
        XCTAssertEqual(continuing("- [ ] a"), "- [ ] a\n- [ ] ")
    }

    func testReturnAfterABareMarkerOrThematicBreakIsAPlainLineBreak() {
        XCTAssertNil(continuing("-"))
        XCTAssertNil(continuing("1."))
        XCTAssertNil(continuing("- - -"))
        XCTAssertNil(continuing("\u{661}. a"))
    }

    func testReturnDoesNotContinueListsInCodeOrFrontmatter() {
        XCTAssertNil(continuing("```yaml\n- name: x"))
        XCTAssertNil(continuing("~~~\n> prompt"))
        XCTAssertNil(continuing("---\ntags:\n  - a\n---\n", at: cursor(15)))
        XCTAssertEqual(continuing("```\ncode\n```\n- a"), "```\ncode\n```\n- a\n- ", "A closed fence does not affect the list after it.")
        XCTAssertEqual(continuing("---\n- a"), "---\n- a\n- ", "An opening `---` without a closing line is a thematic break.")
        XCTAssertNil(continuing("---\n```\n- a"), "Fences after an unclosed `---` still count.")
        XCTAssertEqual(continuing("---\ntitle: x\n---\n```\ncode\n```\n- a"), "---\ntitle: x\n---\n```\ncode\n```\n- a\n- ")
    }

    func testReturnUsesTheNoteLineBreak() {
        XCTAssertEqual(continuing("- a\r\n- b", at: cursor(3)), "- a\r\n- \r\n- b")
        XCTAssertEqual(continuing("- a\r\n- b"), "- a\r\n- b\r\n- ", "The last line uses the line break of the line above.")
        XCTAssertEqual(continuing("- a"), "- a\n- ")
    }

    func testReturnRenumbersTheItemsThatFollow() {
        XCTAssertEqual(continuing("1. a\n2. b", at: cursor(4)), "1. a\n2. \n3. b")
        XCTAssertEqual(continuing("1. a\n   more\n2. b\n\t1. nested\n3. c\n\nafter", at: cursor(4)),
                       "1. a\n2. \n   more\n3. b\n\t1. nested\n4. c\n\nafter")
        XCTAssertEqual(continuing("1. a\n1. b", at: cursor(4)), "1. a\n2. \n1. b", "Numbering that does not count up is left alone.")
        XCTAssertEqual(continuing("1) a\n2. b", at: cursor(4)), "1) a\n2) \n2. b", "Another delimiter is another list.")
        XCTAssertEqual(continuing("1. a\n2. b\nplain\n3. c", at: cursor(4)), "1. a\n2. \n3. b\nplain\n3. c")
        let edit = MarkdownEditing.continuingList(in: "1. ab\n2. c" as NSString, selection: cursor(4), indentUnit: "\t")
        XCTAssertEqual(applying(edit, to: "1. ab\n2. c"), "1. a\n2. b\n3. c")
        XCTAssertEqual(edit?.selectionAfter, cursor(8))
    }

    func testReturnOnAnEmptyNestedNumberedItemContinuesTheParentNumbering() {
        XCTAssertEqual(continuing("1. a\n\t1. "), "1. a\n2. ")
        XCTAssertEqual(continuing("1. a\n\t1. x\n\t2. "), "1. a\n\t1. x\n2. ")
        XCTAssertEqual(continuing("- a\n\t1. "), "- a\n1. ", "Under a bullet the number stays.")
        let followed = "1. a\n\t1. \n2. b\n3. c\n\tnested"
        let edit = MarkdownEditing.continuingList(in: followed as NSString, selection: cursor(9), indentUnit: "\t")
        XCTAssertEqual(applying(edit, to: followed), "1. a\n2. \n3. b\n4. c\n\tnested", "The items that follow count on after the moved item.")
        XCTAssertEqual(edit?.selectionAfter, cursor(8))
    }

    /// Every line command, from every cursor and short selection, leaves a selection inside
    /// the edited text that does not split a character written with two UTF-16 units.
    func testLineCommandsKeepTheSelectionInsideTheText() {
        let samples = ["- [🙂] x\r\n> - a", "1. a\n\t2. 😀\n", "> \u{301}x\n- \u{301}y", "-\n1.\n- - -", "  buy\r\n  - [x] done"]
        for sample in samples {
            let text = sample as NSString
            for location in 0...text.length {
                for selectionLength in [0, 1, 3] where location + selectionLength <= text.length {
                    let selection = NSRange(location: location, length: selectionLength)
                    // The editor never puts a selection inside a character.
                    guard [location, NSMaxRange(selection)].allSatisfy({ position in !splitsCharacter(at: position, in: text) }) else { continue }
                    let edits: [MarkdownTextEdit?] = [
                        MarkdownEditing.indenting(in: text, selection: selection, indentUnit: "\t"),
                        MarkdownEditing.outdenting(in: text, selection: selection, indentUnit: "  ", tabSize: 2),
                        MarkdownEditing.togglingTask(in: text, selection: selection),
                        MarkdownEditing.togglingList(numbered: true, in: text, selection: selection),
                        MarkdownEditing.togglingList(numbered: false, in: text, selection: selection),
                        MarkdownEditing.settingHeading(level: 2, in: text, selection: selection),
                        MarkdownEditing.continuingList(in: text, selection: selection, indentUnit: "\t"),
                    ]
                    for case let edit? in edits {
                        guard let edited = applying(edit, to: sample) else { continue }
                        let editedText = edited as NSString
                        let context = "\(sample.debugDescription) \(selection) -> \(edited.debugDescription) \(edit.selectionAfter)"
                        XCTAssertLessThanOrEqual(NSMaxRange(edit.selectionAfter), editedText.length, context)
                        for position in [edit.selectionAfter.location, NSMaxRange(edit.selectionAfter)] {
                            XCTAssertFalse(splitsCharacter(at: position, in: editedText), context)
                        }
                    }
                }
            }
        }
    }

    /// Whether `position` falls between the halves of a surrogate pair or of a CRLF.
    private func splitsCharacter(at position: Int, in text: NSString) -> Bool {
        guard position > 0, position < text.length else { return false }
        let previous = text.character(at: position - 1), next = text.character(at: position)
        return UTF16.isTrailSurrogate(next) || (previous == 13 && next == 10)
    }

    // MARK: Headings and inline markup

    func testHeadingSkipsBlankLinesInASelection() {
        let headings = "## a\n\n## b"
        let removed = MarkdownEditing.settingHeading(level: 2, in: headings as NSString, selection: NSRange(location: 0, length: 10))
        XCTAssertEqual(applying(removed, to: headings), "a\n\nb")
        let paragraphs = "a\n\nb"
        let added = MarkdownEditing.settingHeading(level: 2, in: paragraphs as NSString, selection: NSRange(location: 0, length: 4))
        XCTAssertEqual(applying(added, to: paragraphs), "## a\n\n## b")
        XCTAssertEqual(applying(MarkdownEditing.settingHeading(level: 2, in: "a\n\n" as NSString, selection: cursor(2)), to: "a\n\n"), "a\n## \n",
                       "A cursor on an empty line still makes it a heading.")
    }

    func testItalicInsideBoldAddsItalic() {
        let text = "x **word** y"
        let selected = MarkdownEditing.togglingWrap("*", in: text as NSString, selection: NSRange(location: 4, length: 4))
        XCTAssertEqual(applying(selected, to: text), "x ***word*** y")
        XCTAssertEqual(selected.selectionAfter, NSRange(location: 5, length: 4))
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("*", in: text as NSString, selection: cursor(6)), to: text), "x ***word*** y")
        let both = "x ***word*** y"
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("*", in: both as NSString, selection: cursor(7)), to: both), "x **word** y")
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("**", in: both as NSString, selection: cursor(7)), to: both), "x *word* y")
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("**", in: "*word*" as NSString, selection: cursor(3)), to: "*word*"), "***word***")
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("*", in: "x *word* y" as NSString, selection: cursor(5)), to: "x *word* y"), "x word y")
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("*", in: "**word**" as NSString, selection: NSRange(location: 1, length: 6)), to: "**word**"), "***word***")
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("**", in: "**word**" as NSString, selection: NSRange(location: 0, length: 8)), to: "**word**"), "word")
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("~~", in: "a ~~~~ b" as NSString, selection: cursor(4)), to: "a ~~~~ b"), "a  b",
                       "An empty pair is removed again.")
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("**", in: "a **** b" as NSString, selection: NSRange(location: 2, length: 4)), to: "a **** b"), "a  b",
                       "A selected empty pair is removed too.")
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("*", in: "a ** b" as NSString, selection: NSRange(location: 2, length: 2)), to: "a ** b"), "a  b")
    }
}
