import XCTest
@testable import GraphiteCore

/// Markdown edge cases that were read differently from Obsidian and CommonMark.
final class MarkdownEdgeCaseRegressionTests: XCTestCase {
    private func styles(in text: String) -> [(text: String, style: MarkdownStyle)] {
        let source = text as NSString
        return MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length)).map { span in
            (source.substring(with: span.range), span.style)
        }
    }

    /// `*note_` opens with one character and closes with another: no emphasis.
    func testEmphasisOpensAndClosesWithTheSameCharacter() {
        XCTAssertFalse(styles(in: "a *note_ b").contains { found in found.style == .emphasis })
        XCTAssertTrue(styles(in: "a *note* b").contains { found in found.style == .emphasis })
        XCTAssertTrue(styles(in: "a _note_ b").contains { found in found.style == .emphasis })
    }

    /// Any one-character status is a task, as in reading view and Obsidian.
    func testCustomTaskStatusesAreTasks() {
        for status in [">", "!", "?", "x", " "] {
            XCTAssertTrue(styles(in: "- [\(status)] item").contains { found in found.style == .taskMarker && found.text == "[\(status)]" }, status)
        }
    }

    /// Indented four spaces, a rule is code; ten digits are no list marker.
    func testRulesAndListMarkersFollowCommonMark() {
        XCTAssertFalse(styles(in: "    ***").contains { found in found.style == .horizontalRule })
        XCTAssertTrue(styles(in: "   ***").contains { found in found.style == .horizontalRule })
        XCTAssertFalse(styles(in: "1234567890. item").contains { found in found.style == .listMarker })
        XCTAssertTrue(styles(in: "123456789. item").contains { found in found.style == .listMarker })
        XCTAssertFalse(styles(in: "١. item").contains { found in found.style == .listMarker })
    }

    /// Return on item 999999999 ends the list rather than writing a ten-digit marker.
    func testAListAtNineDigitsEndsInsteadOfOverflowing() {
        let text = "999999999. last" as NSString
        XCTAssertNil(MarkdownEditing.continuingList(in: text, selection: NSRange(location: text.length, length: 0), indentUnit: "\t"))
        let shorter = "8. next" as NSString
        XCTAssertNotNil(MarkdownEditing.continuingList(in: shorter, selection: NSRange(location: shorter.length, length: 0), indentUnit: "\t"))
    }

    /// The frontmatter is read as the rest of the app reads it: an indented `  ---` inside
    /// a block scalar does not close it, so Return there is not a list continuation.
    func testListContinuationReadsFrontmatterAsTheAppDoes() {
        let text = "---\nnotes: |\n  ---\n- a\n---\n- item" as NSString
        let insideYAML = (text.range(of: "- a")).location + 3
        XCTAssertNil(MarkdownEditing.continuingList(in: text, selection: NSRange(location: insideYAML, length: 0), indentUnit: "\t"))
        XCTAssertNotNil(MarkdownEditing.continuingList(in: text, selection: NSRange(location: text.length, length: 0), indentUnit: "\t"))
    }

    /// A letter outside the Basic Multilingual Plane is two UTF-16 units; ⌘B wrapped only
    /// the rest of the word, and a quote after one was paired.
    func testWordsWithLettersOutsideTheBasicPlaneAreWholeWords() {
        let text = "𠮷野家 here" as NSString
        XCTAssertEqual(MarkdownEditing.wordRange(at: 1, in: text), NSRange(location: 0, length: 4))
        let afterLetter = "𝐀" as NSString
        XCTAssertNil(MarkdownEditing.pairing(typed: "\"", in: afterLetter, selection: NSRange(location: afterLetter.length, length: 0), pairsBrackets: true, pairsMarkdown: true))
    }

    /// An image whose name has `(1)` in it is an image block, as `EmbedLocator` reads it.
    func testAStandaloneImageWithParenthesesInItsNameIsABlock() {
        let blocks = LivePreviewBlockScanner.blocks(in: "Intro\n\n![](photo (1).png)\n\nAfter\n" as NSString)
        XCTAssertTrue(blocks.contains { block in block.markdown.contains("photo (1).png") }, "\(blocks.map(\.kind))")
    }

    /// A table may leave out its outer pipes, in Live Preview and for block identifiers.
    func testATableWithoutOuterPipesIsATable() {
        let text = "Intro\n\na | b\n--|--\n1 | 2\n3 | 4\n\nAfter\n"
        let blocks = LivePreviewBlockScanner.blocks(in: text as NSString)
        let table = blocks.first { block in block.kind == .table }
        XCTAssertEqual(table?.markdown.trimmingCharacters(in: .newlines), "a | b\n--|--\n1 | 2\n3 | 4")
        XCTAssertTrue(NoteBlocks.blocks(in: text).contains { block in block.kind == .table })
        // Text over a rule stays text over a rule.
        XCTAssertFalse(LivePreviewBlockScanner.blocks(in: "a | b\n---\n" as NSString).contains { block in block.kind == .table })
    }

    /// Lines of a note saved with lone carriage returns are counted, so a plugin's block
    /// is on its own line rather than line 0.
    func testPluginBlockLinesCountLoneCarriageReturns() throws {
        let text = "one\rtwo\r```dataview\rLIST\r```\rafter"
        let place = try XCTUnwrap(LivePreviewBlockScanner.onlyPluginCodeBlock(language: "dataview", code: "LIST", in: text))
        XCTAssertEqual(place.firstLine, 2)
    }

    /// Only the `\` of a table's escaped `\|` leaves an embed's target.
    func testAnEmbedKeepsTheBackslashesInItsName() {
        let text = "![[a\\b.png]] and ![[c.png\\|300]]" as NSString
        XCTAssertEqual(EmbedLocator.embed(at: 3, in: text)?.target, "a\\b.png")
        XCTAssertEqual(EmbedLocator.embed(at: text.range(of: "c.png").location, in: text)?.target, "c.png")
    }

    /// `...` closes frontmatter, so typing it is no plain-text edit that moves folds only.
    func testTypingTheFrontmatterEndRescansFolds() {
        let before = "---\ntitle: a\n..\n# Heading\ntext\n" as NSString
        let after = "---\ntitle: a\n...\n# Heading\ntext\n" as NSString
        let regions = NoteFolding.regions(in: before as String)
        let editLocation = before.range(of: "..").location + 2
        XCTAssertNil(NoteFolding.regions(regions, across: NSRange(location: editLocation, length: 0), replacementLength: 1, before: before, after: after))
    }

    /// A task with digits of another script is no task, as the editor reads it.
    func testReadingTasksNeedASCIIDigits() {
        func isTask(_ line: String) -> Bool {
            ReadingTasks.pattern?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
        }
        XCTAssertFalse(isTask("١. [ ] x"))
        XCTAssertTrue(isTask("1. [ ] y"))
    }
}
