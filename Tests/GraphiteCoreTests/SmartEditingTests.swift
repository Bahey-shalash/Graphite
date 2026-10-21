import GraphiteTestSupport
import XCTest
@testable import GraphiteCore

final class SmartEditingTests: XCTestCase {
    private func applying(_ edit: MarkdownTextEdit?, to text: String) -> String? {
        edit.map { edit in (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) }
    }

    private func cursorAtEnd(_ text: String) -> NSRange { NSRange(location: (text as NSString).length, length: 0) }

    func testReturnContinuesListsTasksNumbersAndQuotes() {
        for (text, expected) in [("- item", "- item\n- "), ("  * item", "  * item\n  * "), ("9. item", "9. item\n10. "),
                                 ("- [x] done", "- [x] done\n- [ ] "), ("> quoted", "> quoted\n> "), ("> - in quote", "> - in quote\n> - "),
                                 ("1) paren", "1) paren\n2) ")] {
            XCTAssertEqual(applying(MarkdownEditing.continuingList(in: text as NSString, selection: cursorAtEnd(text), indentUnit: "\t"), to: text), expected, text)
        }
        XCTAssertNil(MarkdownEditing.continuingList(in: "plain" as NSString, selection: NSRange(location: 5, length: 0), indentUnit: "\t"))
        XCTAssertNil(MarkdownEditing.continuingList(in: "- item" as NSString, selection: NSRange(location: 1, length: 0), indentUnit: "\t"),
                     "Inside the marker, Return is an ordinary line break.")
        let middle = "- first second"
        XCTAssertEqual(applying(MarkdownEditing.continuingList(in: middle as NSString, selection: NSRange(location: 8, length: 0), indentUnit: "\t"), to: middle), "- first \n- second")
    }

    func testReturnOnAnEmptyItemEndsOrOutdentsIt() {
        XCTAssertEqual(applying(MarkdownEditing.continuingList(in: "- a\n- " as NSString, selection: cursorAtEnd("- a\n- "), indentUnit: "\t"), to: "- a\n- "), "- a\n")
        XCTAssertEqual(applying(MarkdownEditing.continuingList(in: "\t- " as NSString, selection: cursorAtEnd("\t- "), indentUnit: "\t"), to: "\t- "), "- ")
        XCTAssertEqual(applying(MarkdownEditing.continuingList(in: "    - [ ] " as NSString, selection: cursorAtEnd("    - [ ] "), indentUnit: "    "), to: "    - [ ] "), "- [ ] ")
        XCTAssertEqual(applying(MarkdownEditing.continuingList(in: "> " as NSString, selection: cursorAtEnd("> "), indentUnit: "\t"), to: "> "), "")
    }

    func testIndentAndOutdentKeepQuotesAndTheCursor() {
        let text = "- a\n- b"
        let indented = MarkdownEditing.indenting(in: text as NSString, selection: NSRange(location: 5, length: 0), indentUnit: "\t")
        XCTAssertEqual(applying(indented, to: text), "- a\n\t- b")
        XCTAssertEqual(indented.selectionAfter.location, 6)
        XCTAssertEqual(applying(MarkdownEditing.outdenting(in: "> \t- b" as NSString, selection: NSRange(location: 4, length: 0), indentUnit: "\t"), to: "> \t- b"), "> - b")
        XCTAssertEqual(applying(MarkdownEditing.outdenting(in: "      - b" as NSString, selection: NSRange(location: 8, length: 0), indentUnit: "    "), to: "      - b"), "  - b")
    }

    func testToggleTaskAndListsAndMoveLines() {
        XCTAssertEqual(applying(MarkdownEditing.togglingTask(in: "buy milk" as NSString, selection: NSRange(location: 3, length: 0)), to: "buy milk"), "- [ ] buy milk")
        XCTAssertEqual(applying(MarkdownEditing.togglingTask(in: "- buy" as NSString, selection: NSRange(location: 3, length: 0)), to: "- buy"), "- [ ] buy")
        XCTAssertEqual(applying(MarkdownEditing.togglingTask(in: "- [ ] buy" as NSString, selection: NSRange(location: 7, length: 0)), to: "- [ ] buy"), "- [x] buy")
        XCTAssertEqual(applying(MarkdownEditing.togglingTask(in: "- [x] buy" as NSString, selection: NSRange(location: 7, length: 0)), to: "- [x] buy"), "- [ ] buy")
        let lines = "one\ntwo\n\nthree"
        XCTAssertEqual(applying(MarkdownEditing.togglingList(numbered: true, in: lines as NSString, selection: NSRange(location: 0, length: 14)), to: lines), "1. one\n2. two\n\n3. three")
        XCTAssertEqual(applying(MarkdownEditing.togglingList(numbered: false, in: "- a\n- b" as NSString, selection: NSRange(location: 0, length: 7)), to: "- a\n- b"), "a\nb")
        XCTAssertEqual(applying(MarkdownEditing.togglingList(numbered: false, in: "1. a" as NSString, selection: NSRange(location: 3, length: 0)), to: "1. a"), "- a")
        let moving = "a\nb\nc"
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: true, in: moving as NSString, selection: NSRange(location: 4, length: 0)), to: moving), "a\nc\nb")
        XCTAssertEqual(applying(MarkdownEditing.movingLines(up: false, in: moving as NSString, selection: NSRange(location: 0, length: 0)), to: moving), "b\na\nc")
        XCTAssertNil(MarkdownEditing.movingLines(up: true, in: moving as NSString, selection: NSRange(location: 0, length: 0)))
        XCTAssertEqual(MarkdownEditing.movingLines(up: true, in: moving as NSString, selection: NSRange(location: 4, length: 0))?.selectionAfter.location, 2)
    }

    func testWrapTogglesAroundSelectionOrWord() {
        let text = "make this bold"
        let wrapped = MarkdownEditing.togglingWrap("**", in: text as NSString, selection: NSRange(location: 5, length: 4))
        XCTAssertEqual(applying(wrapped, to: text), "make **this** bold")
        XCTAssertEqual(wrapped.selectionAfter, NSRange(location: 7, length: 4))
        let unwrapped = MarkdownEditing.togglingWrap("**", in: "make **this** bold" as NSString, selection: NSRange(location: 7, length: 4))
        XCTAssertEqual(applying(unwrapped, to: "make **this** bold"), "make this bold")
        XCTAssertEqual(applying(MarkdownEditing.togglingWrap("==", in: text as NSString, selection: NSRange(location: 11, length: 0)), to: text), "make this ==bold==")
        let empty = MarkdownEditing.togglingWrap("*", in: "a  b" as NSString, selection: NSRange(location: 2, length: 0))
        XCTAssertEqual(applying(empty, to: "a  b"), "a ** b")
        XCTAssertEqual(empty.selectionAfter.location, 3)
    }

    func testBracketsPairAndStepOverAndDeleteTogether() {
        func typing(_ typed: String, in text: String, at location: Int, length: Int = 0) -> String? {
            applying(MarkdownEditing.pairing(typed: typed, in: text as NSString, selection: NSRange(location: location, length: length), pairsBrackets: true, pairsMarkdown: true), to: text)
        }
        XCTAssertEqual(typing("(", in: "f", at: 1), "f()")
        XCTAssertEqual(typing("[", in: "[]", at: 1), "[[]]", "Two [ make a Wikilink.")
        XCTAssertEqual(typing(")", in: "()", at: 1), "()")
        XCTAssertNil(typing("\"", in: "it", at: 2), "A quote after a letter is typed alone.")
        XCTAssertNil(typing("`", in: "``", at: 2), "A third backtick makes a fence.")
        XCTAssertNil(typing("(", in: "word", at: 0), "Before a word, a bracket is typed alone.")
        XCTAssertEqual(typing("*", in: "bold me", at: 0, length: 4), "*bold* me")
        XCTAssertEqual(typing("[", in: "link", at: 0, length: 4), "[link]")
        XCTAssertNil(MarkdownEditing.pairing(typed: "*", in: "a" as NSString, selection: NSRange(location: 1, length: 0), pairsBrackets: true, pairsMarkdown: true))
        XCTAssertEqual(applying(MarkdownEditing.deletingPair(in: "f()" as NSString, selection: NSRange(location: 2, length: 0)), to: "f()"), "f")
        XCTAssertNil(MarkdownEditing.deletingPair(in: "f(x)" as NSString, selection: NSRange(location: 2, length: 0)))
    }
}
