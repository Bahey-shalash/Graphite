import XCTest
@testable import GraphiteCore

/// Rewriting Markdown link destinations: the parts CommonMark reads, the style they were
/// written in, and nested links.
final class CoreLinksRewriterTests: XCTestCase {
    func testDestinationsWithParenthesesAreReplacedWhole() {
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[x](Lecture%20(1).md)", isWiki: false, newPathPart: "../Other/Lecture (1).md"),
                       "[x](../Other/Lecture%20%281%29.md)")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "![](Pasted%20image%20(2).png#frag)", isWiki: false, newPathPart: "../Attachments/Pasted image (2).png"),
                       "![](../Attachments/Pasted%20image%20%282%29.png#frag)", "The fragment stays.")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[x](a(b(c)).md)", isWiki: false, newPathPart: "Moved/a(b(c)).md"),
                       "[x](Moved/a%28b%28c%29%29.md)")
    }

    func testTitlesAndCodeSpanLabelsHoldingBracketsAreKept() {
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[x](Target.md \"a](b\")", isWiki: false, newPathPart: "Renamed.md"),
                       "[x](Renamed.md \"a](b\")")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[`a](b`](Target.md)", isWiki: false, newPathPart: "Renamed.md"),
                       "[`a](b`](Renamed.md)")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[![logo](logo.png)](Target.md)", isWiki: false, newPathPart: "Renamed.md"),
                       "[![logo](logo.png)](Renamed.md)", "The link's own destination follows its label, not the image's.")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[a \\] b](Target.md)", isWiki: false, newPathPart: "Renamed.md"),
                       "[a \\] b](Renamed.md)", "An escaped bracket does not end the label.")
    }

    func testReferenceStyleLinksHaveNoDestinationAndDefinitionsDo() {
        XCTAssertNil(LinkRewriter.replacingPath(inLinkText: "[the note][ref]", isWiki: false, newPathPart: "Renamed.md"))
        XCTAssertNil(LinkRewriter.replacingPath(inLinkText: "[![img](i.png)][ref]", isWiki: false, newPathPart: "Renamed.md"),
                     "The image in a reference link's label is not the link's destination.")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[ref]: Target.md", isWiki: false, newPathPart: "Renamed.md"), "[ref]: Renamed.md")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[ref]: <Old name.md>", isWiki: false, newPathPart: "New name.md"), "[ref]: <New name.md>")
    }

    func testLettersBeyondASCIIKeepTheWayTheyWereWritten() {
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[x](Café.md)", isWiki: false, newPathPart: "../Café.md"), "[x](../Café.md)")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[x](Caf%C3%A9.md)", isWiki: false, newPathPart: "../Café.md"), "[x](../Caf%C3%A9.md)")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "[x](Café%20noir.md)", isWiki: false, newPathPart: "Sub/Café noir.md"),
                       "[x](Sub/Café%20noir.md)", "Spaces are still encoded.")
    }

    func testNestedReplacementsMergeInsteadOfCorruptingTheNote() {
        let text = "Badge [![logo](logo.png)](Target.md) done"
        let outer = (range: NSRange(location: 6, length: 30), text: "[![logo](logo.png)](../Notes/Target.md)")
        let inner = (range: NSRange(location: 7, length: 17), text: "![logo](../Notes/logo.png)")
        XCTAssertEqual(LinkRewriter.applying([outer, inner], to: text), "Badge [![logo](../Notes/logo.png)](../Notes/Target.md) done")
        XCTAssertEqual(LinkRewriter.applying([inner, outer], to: text), "Badge [![logo](../Notes/logo.png)](../Notes/Target.md) done", "Order does not matter.")
        XCTAssertEqual(LinkRewriter.applying([inner], to: text), "Badge [![logo](../Notes/logo.png)](Target.md) done")
        let crossing = (range: NSRange(location: 30, length: 11), text: "XXXX")
        XCTAssertEqual(LinkRewriter.applying([outer, crossing], to: text), "Badge [![logo](logo.png)](../Notes/Target.md) done",
                       "A range crossing another's end is left out rather than spliced at a stale offset.")
    }

    func testBareNamesAndAliasesStayAsWrittenWhenTheyStillFindTheTarget() throws {
        let target = try VaultPath("Other/Fourier Transform.md")
        XCTAssertEqual(LinkRewriter.pathPart(linkingTo: target, from: try VaultPath("Elsewhere/Mover.md"), writtenPath: "Fourier", isWiki: true,
                                             previousTarget: target, previousSource: try VaultPath("Notes/Mover.md"), isNameUnique: true), "Fourier")
        XCTAssertEqual(LinkRewriter.pathPart(linkingTo: try VaultPath("B/Target Note.md"), from: try VaultPath("Linker.md"), writtenPath: "target note", isWiki: true,
                                             previousTarget: try VaultPath("A/Target Note.md"), previousSource: try VaultPath("Linker.md"), isNameUnique: true),
                       "target note", "Capitalization stays when only the folder changes.")
        XCTAssertEqual(LinkRewriter.pathPart(linkingTo: try VaultPath("A/Renamed.md"), from: try VaultPath("Linker.md"), writtenPath: "target note", isWiki: true,
                                             previousTarget: try VaultPath("A/Target Note.md"), previousSource: try VaultPath("Linker.md"), isNameUnique: true),
                       "Renamed", "A renamed file gets its new name.")
        XCTAssertEqual(LinkRewriter.pathPart(linkingTo: try VaultPath("B/Target Note.md"), from: try VaultPath("Linker.md"), writtenPath: "Target Note", isWiki: true,
                                             previousTarget: try VaultPath("A/Target Note.md"), previousSource: try VaultPath("Linker.md"), isNameUnique: false),
                       "B/Target Note", "A name that became ambiguous gets a path.")
    }

    func testMarkdownLinksInShortestAndAbsoluteFormatKeepTheirFormat() throws {
        let linker = try VaultPath("Courses/Other/Linker.md")
        let previousTarget = try VaultPath("Courses/Signals/Lecture 3.md")
        let target = try VaultPath("Courses/Signals/Lecture 03.md")
        func rewritten(_ writtenPath: String) -> String {
            LinkRewriter.pathPart(linkingTo: target, from: linker, writtenPath: writtenPath, isWiki: false,
                                  previousTarget: previousTarget, previousSource: linker, isNameUnique: true)
        }
        XCTAssertEqual(rewritten("Lecture 3.md"), "Lecture 03.md")
        XCTAssertEqual(rewritten("Courses/Signals/Lecture 3.md"), "Courses/Signals/Lecture 03.md")
        XCTAssertEqual(rewritten("../Signals/Lecture 3.md"), "../Signals/Lecture 03.md")
        XCTAssertEqual(LinkRewriter.style(of: "Lecture 3.md", isWiki: false, previousTarget: try VaultPath("Courses/Other/Lecture 3.md"), previousSource: linker),
                       .relative(hasDotPrefix: false), "A link that reached a file beside the note stays relative.")
    }
}

/// Links found in a note's text and properties, with ranges a rewrite can replace.
final class CoreLinksScannerTests: XCTestCase {
    func testQuotedPropertyLinksAreEscapedForTheirQuotes() throws {
        let text = "---\naliases: [Linky]\nrelated: '[[Newton]]'\n---\nBody"
        let link = try XCTUnwrap(NoteLinkScanner.links(in: text).first)
        XCTAssertEqual(link.target, "Newton")
        XCTAssertEqual((text as NSString).substring(with: link.range), "'[[Newton]]'")
        let replacement = try XCTUnwrap(LinkRewriter.replacingPath(inLinkText: "'[[Newton]]'", isWiki: true, newPathPart: "Newton's laws"))
        XCTAssertEqual(replacement, "'[[Newton''s laws]]'")
        let updated = LinkRewriter.applying([(link.range, replacement)], to: text)
        XCTAssertEqual(try MarkdownSemantics.parse(updated).aliases, ["Linky"], "The properties still parse.")
        XCTAssertEqual(try NoteLinkScanner.links(in: updated).first?.target, "Newton's laws", "The escaped quote is read back as one.")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "\"[[Old]]\"", isWiki: true, newPathPart: "Say \"hi\""), "\"[[Say \\\"hi\\\"]]\"")
        XCTAssertEqual(LinkRewriter.replacingPath(inLinkText: "'[x](<Old.md>)'", isWiki: false, newPathPart: "It's.md"), "'[x](<It''s.md>)'")
    }

    func testPropertyLinksKeepTheirOwnRangesOutsideQuotesOrBesideOtherLinks() throws {
        let text = "---\nplain: [[One]]\nboth: '[[Two]] and [[Three]]'\nlist:\n  - \"[[Four]]\"\n---\n"
        let links = try NoteLinkScanner.links(in: text)
        XCTAssertEqual(links.map { link in (text as NSString).substring(with: link.range) }, ["[[One]]", "[[Two]]", "[[Three]]", "\"[[Four]]\""])
    }

    func testPropertyMarkdownLinksAreReadWithBalancedParentheses() throws {
        let text = "---\nrelated: \"[x](Lecture%20(1).md)\"\nother: [y](plain.md \"title\")\n---\nBody"
        let links = try NoteLinkScanner.links(in: text)
        XCTAssertEqual(links.map(\.target), ["Lecture%20(1).md", "plain.md"])
        XCTAssertEqual(links.map { link in (text as NSString).substring(with: link.range) }, ["\"[x](Lecture%20(1).md)\"", "[y](plain.md \"title\")"])
    }

    func testReferenceDefinitionsAreReportedWithTheLinksThatUseThem() throws {
        let text = "see [the note][ref] and ![pic][image]\n\n[ref]: Target.md\n> [image]: <My image.png> \"Title\"\n[unused]: Other.md\n"
        let links = try NoteLinkScanner.links(in: text)
        let texts = links.map { link in (text as NSString).substring(with: link.range) }
        XCTAssertTrue(texts.contains("[ref]: Target.md"), "\(texts)")
        XCTAssertTrue(texts.contains("[image]: <My image.png>"), "\(texts)")
        XCTAssertFalse(texts.contains { linkText in linkText.hasPrefix("[unused]") }, "A definition no link uses is not a link.")
        XCTAssertEqual(links.first { link in (text as NSString).substring(with: link.range).hasPrefix("[image]") }?.isEmbed, true)
        let fenced = "```\n[ref]: Target.md\n```\n[x][ref]\n\n[ref]: Target.md\n"
        let definitions = try NoteLinkScanner.links(in: fenced).filter { link in (fenced as NSString).substring(with: link.range).hasPrefix("[ref]:") }
        XCTAssertEqual(definitions.map(\.location), [35], "Text in a code block is not a definition.")
    }
}

/// What the text before the cursor is in the middle of typing.
final class CoreLinksCompletionTests: XCTestCase {
    func testChoosingInsideAnExistingLinkReplacesTheRestOfIt() throws {
        guard case .link(let query) = LinkCompletion.context(in: "[[Note]] x" as NSString, cursor: 4) else { return XCTFail("Expected a link query") }
        XCTAssertEqual(query.text, "No")
        XCTAssertEqual(query.replacementRange, NSRange(location: 2, length: 6), "Through the closing brackets.")
        XCTAssertTrue(query.hasClosingBrackets)
        XCTAssertNil(query.writtenAlias)
        guard case .link(let aliased) = LinkCompletion.context(in: "[[Note|alias]]" as NSString, cursor: 4) else { return XCTFail("Expected a link query") }
        XCTAssertEqual(aliased.replacementRange, NSRange(location: 2, length: 12))
        XCTAssertEqual(aliased.writtenAlias, "alias")
        guard case .link(let open) = LinkCompletion.context(in: "[[No and [[Other]]" as NSString, cursor: 4) else { return XCTFail("Expected a link query") }
        XCTAssertEqual(open.replacementRange, NSRange(location: 2, length: 2), "A later link's brackets are not this one's.")
        XCTAssertFalse(open.hasClosingBrackets)
        XCTAssertEqual(LinkCompletion.context(in: "#tag more" as NSString, cursor: 3), .tag(query: "ta", replacementRange: NSRange(location: 1, length: 3)))
    }

    func testTagsFollowTheIndexRules() {
        XCTAssertEqual(LinkCompletion.context(in: "Tagged #📚" as NSString, cursor: 10), .tag(query: "📚", replacementRange: NSRange(location: 8, length: 2)))
        XCTAssertEqual(LinkCompletion.context(in: "Tagged #books📚" as NSString, cursor: 15), .tag(query: "books📚", replacementRange: NSRange(location: 8, length: 7)))
        XCTAssertEqual(LinkCompletion.context(in: "(#todo" as NSString, cursor: 6), .tag(query: "todo", replacementRange: NSRange(location: 2, length: 4)))
        XCTAssertNil(LinkCompletion.context(in: "issue#12" as NSString, cursor: 8))
        XCTAssertNil(LinkCompletion.context(in: "Tagged #" as NSString, cursor: 8))
    }

    func testNoSuggestionsWhereObsidianReadsText() {
        XCTAssertNil(LinkCompletion.context(in: "> ```\n> [[Note" as NSString, cursor: 14), "A fence in a block quote.")
        XCTAssertNotNil(LinkCompletion.context(in: "> ```\nplain [[Note" as NSString, cursor: 18), "The quote, and its fence, ended.")
        XCTAssertNil(LinkCompletion.context(in: "```\n> ```\n[[Note" as NSString, cursor: 16), "A quoted line inside a fence does not close it.")
        XCTAssertNil(LinkCompletion.context(in: "\\[[Not" as NSString, cursor: 6), "An escaped bracket.")
        XCTAssertNotNil(LinkCompletion.context(in: "\\\\[[Not" as NSString, cursor: 7), "An escaped backslash.")
        XCTAssertNil(LinkCompletion.context(in: "`a\n[[x` b" as NSString, cursor: 6), "A code span across lines.")
        XCTAssertNotNil(LinkCompletion.context(in: "`a\n\n[[x` b" as NSString, cursor: 7), "A blank line ends the paragraph and the span.")
        XCTAssertNil(LinkCompletion.context(in: "<!-- note\n[[x" as NSString, cursor: 13), "An HTML comment.")
        XCTAssertNil(LinkCompletion.context(in: "text <!-- [[x" as NSString, cursor: 13))
        XCTAssertNotNil(LinkCompletion.context(in: "<!-- c -->\n[[x" as NSString, cursor: 14))
        XCTAssertNotNil(LinkCompletion.context(in: "`<!--` code\n[[x" as NSString, cursor: 15), "A comment marker in code is text.")
        XCTAssertNil(LinkCompletion.context(in: "a\r\n```\r\n[[x" as NSString, cursor: 11), "Windows line endings.")
        XCTAssertNotNil(LinkCompletion.context(in: "```\r\ncode\r\n```\r\n[[x" as NSString, cursor: 19))
        XCTAssertNil(LinkCompletion.context(in: "~~~~\n```\n[[x" as NSString, cursor: 12), "A shorter fence of another kind does not close it.")
    }

    func testAnEmptyLastLineHasNoContext() {
        XCTAssertNil(LinkCompletion.context(in: "Some text\n" as NSString, cursor: 10), "The cursor after the final line ending.")
        XCTAssertNil(LinkCompletion.context(in: "Some text\r\n" as NSString, cursor: 11))
        XCTAssertNil(LinkCompletion.context(in: "\n" as NSString, cursor: 1))
        let longLine = String(repeating: "word ", count: 100) + "[[Lec"
        guard case .link(let query) = LinkCompletion.context(in: longLine as NSString, cursor: (longLine as NSString).length) else {
            return XCTFail("Expected a link query at the end of a long line")
        }
        XCTAssertEqual(query.text, "Lec")
    }

    func testContextIsCheapWhenNothingIsBeingTyped() {
        let paragraph = "Some prose with `code` and a [[Link]] in a long note.\n```swift\nlet value = 1\n```\n"
        let text = String(repeating: paragraph, count: 4_500) as NSString
        XCTAssertLessThan(text.length, LinkCompletion.maximumScannedLengthForFences)
        XCTAssertNil(LinkCompletion.context(in: (text as String + "plain words") as NSString, cursor: text.length + 11))
        XCTAssertNotNil(LinkCompletion.context(in: (text as String + "[[Lec") as NSString, cursor: text.length + 5))
        XCTAssertNil(LinkCompletion.context(in: (text as String + "```\n[[Lec") as NSString, cursor: text.length + 9))
    }
}

final class CoreLinksFuzzyMatcherTests: XCTestCase {
    func testCharactersThatFoldIntoSeveralStillMatch() throws {
        XCTAssertEqual(try XCTUnwrap(FuzzyMatcher.match("Straße", in: "Straße")).matchedRanges, [0..<6])
        XCTAssertEqual(try XCTUnwrap(FuzzyMatcher.match("strasse", in: "Straße")).matchedRanges, [0..<6])
        XCTAssertNotNil(FuzzyMatcher.match("ﬁle", in: "ﬁle notes"))
        XCTAssertNotNil(FuzzyMatcher.match("file", in: "ﬁle notes"))
    }

    func testSkippingToAWordStartNeverLosesAMatch() {
        XCTAssertNotNil(FuzzyMatcher.match("dan", in: "Drank a lot"))
        XCTAssertNotNil(FuzzyMatcher.match("cat", in: "cxats a"))
        XCTAssertNotNil(FuzzyMatcher.match("rdm", in: "Random delta"))
        XCTAssertEqual(FuzzyMatcher.match("ln", in: "Lecture notes")?.matchedRanges, [0..<1, 8..<9], "Word starts are still preferred.")
    }

    func testTheASCIIPathAgreesWithTheGeneralPath() throws {
        var names = ["Lecture notes", "Balance sheet", "Collection of lectures", "Courses/Course 1/Lecture 3.md", "camelCaseName", "x_y-z.v2",
                     "Line\r\nBreak", "tab\there", "UPPER lower", "a", "", "12 Angry Men", "Drank a lot", "cxats a", "Random delta"]
        let vault = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("test_vault")
        if let enumerator = FileManager.default.enumerator(atPath: vault.path) {
            for case let path as String in enumerator { names.append(path) }
        }
        let queries = ["l", "ln", "LN", "lec", "lecture notes", "c1/", "cc", "2", "x y", "dan", "Courses/Course 1/", "é", "a"]
        for query in queries {
            for name in names {
                XCTAssertEqual(FuzzyMatcher.match(query, in: name), FuzzyMatcher.matchWithoutASCIIPath(query, in: name), "\(query) in \(name)")
            }
        }
    }
}
