import XCTest
@testable import GraphiteCore

final class CoreSearchQueryFixTests: XCTestCase {
    private func word(_ text: String) -> SearchExpression { .term(SearchTerm(text: text, kind: .word)) }

    private func matches(_ query: String, path: String = "Notes/Note.md", content: String?, tags: [String] = [], properties: [BaseFrontmatterEntry] = [],
                         file: StaticString = #filePath, line: UInt = #line) throws -> Bool {
        let expression = try XCTUnwrap(SearchQueryParser.parse(query), file: file, line: line)
        var matcher = SearchMatcher(expression: expression)
        return matcher.matches(SearchableFile(path: try VaultPath(path), content: content, tags: tags, properties: properties))
    }

    private func highlightedTexts(_ query: String, in content: String) throws -> [String] {
        let expression = try XCTUnwrap(SearchQueryParser.parse(query))
        return SearchExcerpts.matches(of: expression, in: content, limit: 5).matches.flatMap { match in
            match.highlightedRanges.map { range in (match.excerpt as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count)) }
        }
    }

    /// How deeply an expression nests, which is how deeply everything walking it recurses.
    private func depth(of expression: SearchExpression) -> Int {
        switch expression {
        case .all(let items), .any(let items): 1 + (items.map(depth(of:)).max() ?? 0)
        case .not(let item), .scoped(_, let item): 1 + depth(of: item)
        case .property(_, let value): 1 + (value.map(depth(of:)) ?? 0)
        case .term: 1
        }
    }

    // MARK: Words fold as the index folds them

    func testWordsKeepTheLettersTheIndexKeeps() {
        XCTAssertEqual(SearchTextTokens.queryTokens(of: "Мой новый Ёлка"), ["мой", "новый", "ёлка"])
        XCTAssertEqual(SearchTextTokens.queryTokens(of: "ΆΛΦΑ λόγος"), ["άλφα", "λόγοσ"])
        XCTAssertEqual(SearchTextTokens.queryTokens(of: "Straße ẞ"), ["straße", "ß"])
        XCTAssertEqual(SearchTextTokens.queryTokens(of: "ﬁrst"), ["ﬁrst"], "The index keeps ligatures as they are.")
        XCTAssertEqual(SearchTextTokens.queryTokens(of: "Café cafe\u{301} İstanbul Ǆ"), ["cafe", "cafe", "istanbul", "ǆ"])
        XCTAssertEqual(SearchTextTokens.queryTokens(of: "Café", foldsCase: false), ["Cafe"])
    }

    func testRussianGreekAndGermanWordsAreFound() throws {
        XCTAssertTrue(try matches("мой", content: "Это мой новый дом"))
        XCTAssertTrue(try matches("МОЙ", content: "Это мой новый дом"))
        XCTAssertFalse(try matches("мои", content: "Это мой новый дом"), "й is its own letter in the index, not и with an accent.")
        XCTAssertTrue(try matches("άλφα", content: "Το άλφα και το ωμέγα"))
        XCTAssertTrue(try matches("Straße", content: "Die Straße"))
        XCTAssertFalse(try matches("-Straße", content: "Die Straße"))
    }

    // MARK: Chinese, Japanese, and Korean

    func testChineseAndJapaneseWordsAreFoundInsideARun() throws {
        XCTAssertTrue(try matches("北京", content: "我今天去北京玩"))
        XCTAssertTrue(try matches("\"北京\"", content: "我今天去北京玩"))
        XCTAssertTrue(try matches("line:北京", content: "第一行\n我今天去北京玩"))
        XCTAssertTrue(try matches("タワー", content: "東京タワーに行きました"))
        XCTAssertTrue(try matches("서울", content: "나는서울에서 만나요"))
        XCTAssertFalse(try matches("上海", content: "我今天去北京玩"))
        XCTAssertFalse(try matches("search", content: "unsearchable"), "Other words still match only at their start.")
        XCTAssertEqual(try highlightedTexts("北京", in: "我今天去北京玩"), ["北京"])
        XCTAssertEqual(try highlightedTexts("東京", in: "Tokyo東京タワー and more"), ["東京"])
        XCTAssertEqual(SearchTextTokens.literalFragments(of: "tokyo東京 タワー"), ["東京", "タワー"])
        XCTAssertEqual(SearchTextTokens.literalFragments(of: "plain words"), [])
    }

    // MARK: Emoji

    func testEmojiAreFoundAsWrittenAndVariationSelectorsAreNotWords() throws {
        XCTAssertEqual(SearchTextTokens.queryTokens(of: "❤️"), [], "U+FE0F separates words in the index, as other marks do.")
        XCTAssertEqual(SearchTextTokens.literalSymbols(of: "❤️"), "❤")
        XCTAssertNil(SearchTextTokens.literalSymbols(of: "-"))
        XCTAssertTrue(try matches("❤️", content: "I ❤️ this"))
        XCTAssertTrue(try matches("❤️", content: "I ❤ this"))
        XCTAssertFalse(try matches("❤️", content: "☺️ happy"))
        XCTAssertTrue(try matches("-❤️ happy", content: "☺️ happy"))
        XCTAssertTrue(try matches("-line:❤️", content: "☺️ happy"), "Excluding a heart keeps a note without one.")
        XCTAssertEqual(try highlightedTexts("❤️", in: "I ❤️ this"), ["❤"])
    }

    // MARK: Tags inside lines and tasks

    func testATagInsideALineOrTaskMustBeWrittenThere() throws {
        let tasks = "- [ ] buy milk\n- [x] finished report #work"
        XCTAssertFalse(try matches("task-todo:#work", content: tasks, tags: ["work"]))
        XCTAssertTrue(try matches("task-done:#work", content: tasks, tags: ["work"]))
        XCTAssertTrue(try matches("task-todo:#work", content: "- [ ] plan #work/project", tags: ["work/project"]), "Nested tags count, as elsewhere.")
        let frontmatterTagged = "---\ntags: [urgent]\n---\nplain line about nothing"
        XCTAssertFalse(try matches("line:(#urgent nothing)", content: frontmatterTagged, tags: ["urgent"]))
        XCTAssertTrue(try matches("line:(#urgent nothing)", content: "#urgent nothing today", tags: ["urgent"]))
        XCTAssertTrue(try matches("#urgent", content: frontmatterTagged, tags: ["urgent"]), "Outside a line, the file's tags count.")
        let tagsProperty = [BaseFrontmatterEntry(key: "tags", node: .sequence([.scalar(text: "work", isPlain: true)]))]
        XCTAssertTrue(try matches("[tags:#work]", content: "", tags: ["work"], properties: tagsProperty))
    }

    func testAnOperatorInsideALineOrSectionReadsThatPart() throws {
        let content = "# Home\n- [ ] fix sink\n- [x] paint #work\n# Office\n- [ ] call client #work"
        XCTAssertTrue(try matches("section:(Office task-todo:#work)", content: content, tags: ["work"]))
        XCTAssertFalse(try matches("section:(Home task-todo:#work)", content: content, tags: ["work"]), "The open #work task is in another section.")
        XCTAssertTrue(try matches("section:(Home task-done:paint)", content: content))
        XCTAssertFalse(try matches("line:(sink line:client)", content: content), "Both words must be on the same line.")
        XCTAssertTrue(try matches("line:(call line:client)", content: content))
    }

    func testNestedLineOperatorsOverALongNoteFinishQuickly() throws {
        let content = (1...2_000).map { number in "line number \(number)" }.joined(separator: "\n")
        let deeplyNested = String(repeating: "line:", count: 40) + "zzz"
        XCTAssertFalse(try matches(deeplyNested, content: content))
        XCTAssertTrue(try matches("-" + deeplyNested, content: content))
        XCTAssertTrue(try matches(String(repeating: "block:line:", count: 20) + "\"number 1999\"", content: content))
    }

    // MARK: Windows line endings

    func testBlocksKeepTheirLinesTogetherWithWindowsLineEndings() throws {
        let content = "alpha line one\r\nbeta line two\r\n\r\nother paragraph"
        XCTAssertEqual(SearchContentParts.parts(of: content, scope: .block), ["alpha line one\nbeta line two", "other paragraph"])
        XCTAssertEqual(SearchContentParts.parts(of: content, scope: .line), ["alpha line one", "beta line two", "", "other paragraph"])
        XCTAssertTrue(try matches("block:(alpha beta)", content: content))
        XCTAssertFalse(try matches("block:(alpha other)", content: content))
        XCTAssertEqual(SearchContentParts.parts(of: "# One\r\ntext\r\n# Two\r\nmore", scope: .section), ["# One\ntext", "# Two\nmore"])
    }

    // MARK: Parsing

    func testDeepNestingIsReadFlatInsteadOfExhaustingTheStack() throws {
        let deepGroups = try XCTUnwrap(SearchQueryParser.parse(String(repeating: "(", count: 5_000) + "foo"))
        XCTAssertEqual(deepGroups, word("foo"))
        XCTAssertEqual(SearchQueryParser.parse(String(repeating: "-", count: 5_000) + "foo"), word("foo"))
        XCTAssertEqual(SearchQueryParser.parse(String(repeating: "-", count: 5_001) + "foo"), .not(word("foo")))
        let scopes = try XCTUnwrap(SearchQueryParser.parse(String(repeating: "line:", count: 5_000) + "foo"))
        XCTAssertLessThanOrEqual(depth(of: scopes), SearchQueryParser.maximumNestingDepth + 1)
        let mixed = try XCTUnwrap(SearchQueryParser.parse(String(repeating: "(a -", count: 2_000) + "foo"))
        XCTAssertLessThanOrEqual(depth(of: mixed), 3 * SearchQueryParser.maximumNestingDepth + 2)
        let properties = try XCTUnwrap(SearchQueryParser.parse(String(repeating: "[a:", count: 200) + "x" + String(repeating: "]", count: 200)))
        XCTAssertLessThanOrEqual(depth(of: properties), SearchQueryParser.maximumNestingDepth + 2)
        var matcher = SearchMatcher(expression: mixed)
        _ = matcher.matches(SearchableFile(path: try VaultPath("Note.md"), content: "a foo", tags: [], properties: []))
        XCTAssertEqual(SearchQueryParser.parse("((a OR b) c)"), .all([.any([word("a"), word("b")]), word("c")]), "Ordinary nesting is unchanged.")
        // Past the limit, the ignored `(` and operators keep the exclusion before them.
        XCTAssertEqual(SearchQueryParser.parse("-" + String(repeating: "(", count: 100) + "foo"), .not(word("foo")))
        let nestedLines = (0..<SearchQueryParser.maximumNestingDepth).reduce(word("foo")) { operand, _ in .scoped(.line, operand) }
        XCTAssertEqual(SearchQueryParser.parse("-" + String(repeating: "line:", count: 100) + "foo"), .not(nestedLines))
    }

    func testAnOperatorOrExclusionWithoutOperandLeavesOrAndParenthesesInPlace() {
        XCTAssertEqual(SearchQueryParser.parse("foo -OR bar"), .any([word("foo"), word("bar")]))
        XCTAssertEqual(SearchQueryParser.parse("foo path: OR bar"), .any([word("foo"), word("bar")]))
        XCTAssertEqual(SearchQueryParser.parse("(a OR path:) -b"), .all([word("a"), .not(word("b"))]))
        XCTAssertEqual(SearchQueryParser.parse("--foo"), word("foo"), "Two exclusions cancel.")
        XCTAssertEqual(SearchQueryParser.parse("---foo"), .not(word("foo")))
    }

    func testRegularExpressionsMayHoldASlashInAClassAndInvalidOnesAreReported() {
        XCTAssertEqual(SearchQueryParser.parse("/a[/]b/"), .term(SearchTerm(text: "a[/]b", kind: .regularExpression)))
        XCTAssertEqual(SearchQueryParser.parse("/a\\/b/ c"), .all([.term(SearchTerm(text: "a\\/b", kind: .regularExpression)), word("c")]))
        XCTAssertEqual(SearchQueryParser.parse("/a[b/"), .term(SearchTerm(text: "a[b", kind: .regularExpression)), "An unclosed class ends at the first slash.")
        XCTAssertEqual(SearchQueryParser.parse("/(foo/")?.invalidRegularExpressionPatterns, ["(foo"])
        XCTAssertEqual(SearchQueryParser.parse("-/(foo/ bar")?.invalidRegularExpressionPatterns, ["(foo"])
        XCTAssertEqual(SearchQueryParser.parse("[status:/(draft/]")?.invalidRegularExpressionPatterns, ["(draft"])
        XCTAssertEqual(SearchQueryParser.parse("/a[/]b/ line:/\\d+/")?.invalidRegularExpressionPatterns, [])
    }

    // MARK: File extensions

    func testANotesExtensionAloneDoesNotMatchEveryNote() throws {
        XCTAssertFalse(try matches("md", path: "Notes/Alpha.md", content: "nothing here"))
        XCTAssertFalse(try matches(".md", path: "Notes/Alpha.md", content: "nothing here"))
        XCTAssertTrue(try matches("-md", path: "Notes/Alpha.md", content: "nothing here"))
        XCTAssertTrue(try matches("Alpha.md", path: "Notes/Alpha.md", content: "nothing here"), "A name typed with its extension still finds the note.")
        XCTAssertTrue(try matches("md", path: "Notes/cmd tricks.md", content: "nothing here"))
        XCTAssertTrue(try matches("md", path: "Notes/Alpha.md", content: "Written in md"))
        XCTAssertTrue(try matches("pdf", path: "Papers/Report.pdf", content: nil), "Other files show their extension, so it is searched.")
        XCTAssertTrue(try matches("file:.md", path: "Notes/Alpha.md", content: "nothing here"), "`file:` still reads the whole name.")
        XCTAssertFalse(try matches("\"Alpha md\"", path: "Notes/Alpha.md", content: "nothing here"), "The path's words end before the extension.")
        for term in ["md", ".md", "MD", "mark", "Alpha md", "Alpha.md"] {
            XCTAssertTrue(SearchMatcher.mayMatchNoteExtension(SearchTerm(text: term, kind: term.contains(" ") ? .phrase : .word)), term)
        }
        for term in ["Alpha", "cmd tricks", "model"] {
            XCTAssertFalse(SearchMatcher.mayMatchNoteExtension(SearchTerm(text: term, kind: .word)), term)
        }
    }

    // MARK: Excerpts

    func testHighlightsFollowTrimmedWhitespaceWhateverItIs() throws {
        let longLine = String(repeating: "word ", count: 20) + "abc target end"
        XCTAssertEqual(try highlightedTexts("target", in: longLine), ["target"])
        XCTAssertEqual(try highlightedTexts("target", in: "\u{3000}Japanese target line"), ["target"])
        XCTAssertEqual(try highlightedTexts("target", in: "xxxxx" + String(repeating: " ", count: 80) + "target"), ["target"])
        XCTAssertEqual(try highlightedTexts("target", in: "\t  target at the start"), ["target"])
        let shortLine = try XCTUnwrap(SearchExcerpts.matches(of: word("target"), in: "  a target", limit: 1).matches.first)
        XCTAssertEqual(shortLine.excerpt, "a target")
    }
}
