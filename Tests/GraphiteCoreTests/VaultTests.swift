import XCTest
@testable import GraphiteCore

final class VaultTests: XCTestCase {
    func testPathEscapeAndSymbolicLinkAreRejected() throws {
        XCTAssertThrowsError(try VaultPath("../../secret"))
        XCTAssertThrowsError(try VaultPath("/outside"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("escape"), withDestinationURL: directory.deletingLastPathComponent())
        XCTAssertThrowsError(try VaultPath("escape/secret").url(in: directory))
    }

    func testPathsAreAlwaysInComposedForm() throws {
        let decomposed = "Library/L'E\u{301}tranger.md"
        let composed = "Library/L'\u{C9}tranger.md"
        XCTAssertEqual(Array(try VaultPath(decomposed).rawValue.utf8), Array(composed.utf8), "A file URL's É becomes the typed one.")
        XCTAssertEqual(try VaultPath(decomposed).name, "L'\u{C9}tranger.md")
        let stored = try JSONEncoder().encode(["path": decomposed])
        let decoded = try JSONDecoder().decode([String: String].self, from: stored)
        XCTAssertEqual(try VaultPath(decoded["path"] ?? "").rawValue.utf8.count, composed.utf8.count)
        // A path saved before normalization, such as in a tab layout, comes back composed.
        let savedPath = try JSONDecoder().decode(VaultPath.self, from: Data(#"{"rawValue":"Library/L'E\u0301tranger.md"}"#.utf8))
        XCTAssertEqual(Array(savedPath.rawValue.utf8), Array(composed.utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(VaultPath.self, from: Data(#"{"rawValue":"../outside.md"}"#.utf8)), "Stored paths are checked too.")
    }

    func testHiddenPaths() throws {
        XCTAssertTrue(try VaultPath(".obsidian/bookmarks.json").isHidden)
        XCTAssertTrue(try VaultPath("Course/.trash/Old.md").isHidden)
        XCTAssertFalse(try VaultPath("Course/Lecture.md").isHidden)
        XCTAssertFalse(try VaultPath("Notes/v1.2 draft.md").isHidden)
    }

    func testAtomicWriteDetectsSameSizeExternalEditAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("Lecture µ.md")
        let writer = AtomicFileWriter()
        let revision = try writer.write(Data("first".utf8), to: location, expecting: .absent)
        try Data("other".utf8).write(to: location)
        XCTAssertThrowsError(try writer.write(Data("mine".utf8), to: location, expecting: .revision(revision)))
        XCTAssertEqual(try String(contentsOf: location, encoding: .utf8), "other")
        XCTAssertThrowsError(try writer.write(Data(), to: location, expecting: .absent))
        try FileManager.default.removeItem(at: location)
        XCTAssertThrowsError(try writer.write(Data("mine".utf8), to: location, expecting: .revision(revision)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
    }

    func testSuccessfulReplacementPreservesExactBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("note.md")
        let writer = AtomicFileWriter()
        let original = Data("---\r\naliases: [µ]\r\n---\r\n# Hello  \r\n".utf8)
        let revision = try writer.write(original, to: location, expecting: .absent)
        XCTAssertEqual(try writer.read(location).data, original)
        let changed = original + Data("Content".utf8)
        let nextRevision = try writer.write(changed, to: location, expecting: .revision(revision))
        XCTAssertEqual(try writer.read(location).data, changed)
        XCTAssertNotEqual(revision, nextRevision)
    }

    func testMarkdownSemanticsExcludeCodeAndPreserveSourceRanges() throws {
        let source = "---\naliases: [ADC, '转换']\ntags: [course]\n---\n# Sampling\n\n🙂 [[Quantization|Noise]] ![[Slide deck.pdf]] #signals\n\n`[[ignored]]`\n\n```swift\n[[also ignored]]\n```\n\n[Normal](../normal.md)\n"
        let semantics = try MarkdownSemantics.parse(source)
        XCTAssertEqual(semantics.headings, ["Sampling"])
        XCTAssertEqual(semantics.aliases, ["ADC", "转换"])
        XCTAssertEqual(semantics.tags, ["course", "signals"])
        XCTAssertEqual(semantics.links.map(\.target), ["Quantization", "Slide deck.pdf", "../normal.md"])
        guard semantics.links.count == 3 else { return }
        XCTAssertEqual((source as NSString).substring(with: semantics.links[0].range), "[[Quantization|Noise]]")
        XCTAssertTrue(semantics.links[1].isEmbed)
        XCTAssertFalse(semantics.links[2].isWiki)
    }

    func testFrontmatterWithWindowsLineEndingsKeepsAliasesAndTags() throws {
        let semantics = try MarkdownSemantics.parse("---\r\naliases: [ADC]\r\ntags: [course]\r\n---\r\n# Title\r\n")
        XCTAssertEqual(semantics.aliases, ["ADC"])
        XCTAssertEqual(semantics.tags, ["course"])
        XCTAssertEqual(semantics.headings, ["Title"])
    }

    func testTableEscapedPipeIsNotPartOfTheLinkTarget() throws {
        let semantics = try MarkdownSemantics.parse("| a | [[Lecture 3\\|third]] | [[Plain|alias]] |")
        XCTAssertEqual(semantics.links.map(\.target), ["Lecture 3", "Plain"])
        XCTAssertEqual(semantics.links.map(\.label), ["third", "alias"])
    }

    func testTagsFollowObsidianRules() throws {
        let semantics = try MarkdownSemantics.parse("#2026-exam #1984 #y1984 #inbox/to-read #📚 [[#Heading]] a#b `#code` https://x.org/#anchor #über")
        XCTAssertEqual(semantics.tags, ["2026-exam", "inbox/to-read", "y1984", "über", "📚"].sorted())
        XCTAssertTrue(TagSyntax.isValidTag("2026-exam"))
        XCTAssertFalse(TagSyntax.isValidTag("1984"))
        XCTAssertFalse(TagSyntax.isValidTag("two words"))
        XCTAssertTrue(TagSyntax.tag("Inbox/To-read", isWithin: "inbox"))
        XCTAssertFalse(TagSyntax.tag("myjob/inbox", isWithin: "inbox"))
        XCTAssertFalse(TagSyntax.tag("inboxes", isWithin: "inbox"))
    }

    func testFrontmatterTagsWithNumbersAndCommaSeparatedText() throws {
        XCTAssertEqual(try MarkdownSemantics.parse("---\ntags: [fiction, 2024, \"#classic\"]\n---\n").tags, ["2024", "classic", "fiction"])
        XCTAssertEqual(try MarkdownSemantics.parse("---\ntags: fiction, classic\n---\n").tags, ["classic", "fiction"])
        XCTAssertEqual(try MarkdownSemantics.parse("---\ntags: single\n---\n").tags, ["single"])
    }

    func testEmptyFrontmatterIsNotBody() throws {
        let semantics = try MarkdownSemantics.parse("---\n---\n# Title\n")
        XCTAssertEqual(semantics.frontmatter, "")
        XCTAssertEqual(semantics.body, "# Title\n")
    }

    func testCoordinateTransformWithNonzeroCropOrigin() throws {
        for size in [CGSize(width: 595, height: 842), CGSize(width: 1200, height: 600)] {
            let coordinates = try PageCoordinates(cropBox: CGRect(x: 31, y: 72, width: size.width, height: size.height), overlaySize: CGSize(width: size.width * 2, height: size.height * 2))
            let point = CGPoint(x: 145, y: 200)
            let restored = coordinates.overlayPoint(fromPDF: coordinates.pdfPoint(fromOverlay: point))
            XCTAssertEqual(restored.x, point.x, accuracy: 0.0001)
            XCTAssertEqual(restored.y, point.y, accuracy: 0.0001)
        }
    }

    /// An interior point and different horizontal and vertical scales, so swapped width
    /// and height ratios give a different answer.
    func testCoordinateTransformOfAnInteriorPointWithUnequalScales() throws {
        let coordinates = try PageCoordinates(cropBox: CGRect(x: 31, y: 72, width: 600, height: 800), overlaySize: CGSize(width: 300, height: 1600))
        let pdfPoint = CGPoint(x: 131, y: 272)
        let overlayPoint = CGPoint(x: 50, y: 1200)
        func assertPoint(_ actual: CGPoint, equals expected: CGPoint, _ message: String, line: UInt = #line) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001, message, line: line)
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, message, line: line)
        }
        assertPoint(coordinates.overlayPoint(fromPDF: pdfPoint), equals: overlayPoint, "PDF to overlay")
        assertPoint(coordinates.pdfPoint(fromOverlay: overlayPoint), equals: pdfPoint, "Overlay to PDF")
    }
}

final class MarkdownEditingTests: XCTestCase {
    private func applying(_ edit: MarkdownTextEdit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testHeadingReplacesTheLineStartNotTheCursor() {
        let text = "Intro\nSome words here\nAfter"
        let cursor = NSRange(location: 11, length: 0)
        let edit = MarkdownEditing.settingHeading(level: 2, in: text as NSString, selection: cursor)
        XCTAssertEqual(applying(edit, to: text), "Intro\n## Some words here\nAfter")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 14, length: 0))
    }

    func testHeadingChangesLevelAndTogglesOff() {
        let text = "### Title\r\nnext"
        let changed = MarkdownEditing.settingHeading(level: 1, in: text as NSString, selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(applying(changed, to: text), "# Title\r\nnext")
        let removed = MarkdownEditing.settingHeading(level: 3, in: text as NSString, selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(applying(removed, to: text), "Title\r\nnext")
        XCTAssertEqual(removed.selectionAfter.location, 1)
    }

    func testHeadingOnEverySelectedLineAndAnEmptyNote() {
        let text = "one\ntwo\nthree"
        let edit = MarkdownEditing.settingHeading(level: 4, in: text as NSString, selection: NSRange(location: 1, length: 5))
        XCTAssertEqual(applying(edit, to: text), "#### one\n#### two\nthree")
        XCTAssertEqual(applying(MarkdownEditing.settingHeading(level: 1, in: "", selection: NSRange(location: 0, length: 0)), to: ""), "# ")
        XCTAssertNil(MarkdownEditing.headingLevel(of: "#hashtag"))
        XCTAssertEqual(MarkdownEditing.headingLevel(of: "  ## x"), 2)
    }
}

final class SearchQueryParserTests: XCTestCase {
    func testParsesObsidianSearchSyntax() {
        XCTAssertEqual(SearchQueryParser.parse("meeting -work"),
                       .all([.term(SearchTerm(text: "meeting", kind: .word)), .not(.term(SearchTerm(text: "work", kind: .word)))]))
        XCTAssertEqual(SearchQueryParser.parse("a b OR c"),
                       .any([.all([.term(SearchTerm(text: "a", kind: .word)), .term(SearchTerm(text: "b", kind: .word))]), .term(SearchTerm(text: "c", kind: .word))]))
        XCTAssertEqual(SearchQueryParser.parse("path:\"Daily notes/2022\" -(x y)"),
                       .all([.scoped(.path, .term(SearchTerm(text: "Daily notes/2022", kind: .phrase))),
                             .not(.all([.term(SearchTerm(text: "x", kind: .word)), .term(SearchTerm(text: "y", kind: .word))]))]))
        XCTAssertEqual(SearchQueryParser.parse("[status:draft OR done]"),
                       .property(name: "status", value: .any([.term(SearchTerm(text: "draft", kind: .word)), .term(SearchTerm(text: "done", kind: .word))])))
        XCTAssertEqual(SearchQueryParser.parse("/\\d{4}-\\d{2}/"), .term(SearchTerm(text: "\\d{4}-\\d{2}", kind: .regularExpression)))
        XCTAssertEqual(SearchQueryParser.parse("\"say \\\"hi\\\"\""), .term(SearchTerm(text: "say \"hi\"", kind: .phrase)))
        XCTAssertEqual(SearchQueryParser.parse("file:\u{201C}14 Review\u{201D}"), .scoped(.file, .term(SearchTerm(text: "14 Review", kind: .phrase))),
                       "Curly quotes from the iPad keyboard quote a phrase.")
    }

    func testForgivesUnbalancedInput() {
        XCTAssertEqual(SearchQueryParser.parse("(a OR b"), .any([.term(SearchTerm(text: "a", kind: .word)), .term(SearchTerm(text: "b", kind: .word))]))
        XCTAssertEqual(SearchQueryParser.parse("a) b"), .all([.term(SearchTerm(text: "a", kind: .word)), .term(SearchTerm(text: "b", kind: .word))]))
        XCTAssertNil(SearchQueryParser.parse("   "))
        XCTAssertNil(SearchQueryParser.parse("OR"))
        XCTAssertEqual(SearchQueryParser.parse("\"unclosed phrase"), .term(SearchTerm(text: "unclosed phrase", kind: .phrase)))
        XCTAssertEqual(SearchQueryParser.parse("e-mail"), .term(SearchTerm(text: "e-mail", kind: .word)), "A hyphen inside a word does not exclude.")
    }
}

final class LinkLocatorTests: XCTestCase {
    func testFindsTheLinkAroundACharacter() throws {
        let line = "See [[Lab notebook#Result|the result]] and [the slides](Slides.pdf#page=3), or ![[Diagram.png]] and [a site](https://example.com)."
        let source = line as NSString
        let wikilinkStart = source.range(of: "[[Lab").location
        XCTAssertEqual(LinkLocator.link(in: line, at: wikilinkStart + 5, includesEnd: false), .note(target: "Lab notebook#Result", isWiki: true),
                       "The alias is not part of the target.")
        let markdownStart = source.range(of: "[the slides]").location
        XCTAssertEqual(LinkLocator.link(in: line, at: markdownStart + 2, includesEnd: false), .note(target: "Slides.pdf#page=3", isWiki: false))
        XCTAssertNil(LinkLocator.link(in: line, at: source.range(of: "Diagram").location, includesEnd: false), "An embed is not a link to follow.")
        XCTAssertEqual(LinkLocator.link(in: line, at: source.range(of: "a site").location, includesEnd: false), .web(try XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertNil(LinkLocator.link(in: line, at: 1, includesEnd: false))
    }

    func testTheCursorRightAfterALinkCountsOnlyWhenAsked() {
        let line = "Read [[Zebra note]]"
        let end = (line as NSString).length
        XCTAssertNil(LinkLocator.link(in: line, at: end, includesEnd: false))
        XCTAssertEqual(LinkLocator.link(in: line, at: end, includesEnd: true), .note(target: "Zebra note", isWiki: true))
    }
}

final class PDFCitationTests: XCTestCase {
    func testPageLinksNameTheFileAndPage() {
        XCTAssertEqual(PDFCitation.pageLink(linkTarget: "Signals.pdf", displayName: "Signals", pageNumber: 3, usesWikilinks: true),
                       "[[Signals.pdf#page=3|Signals, p.3]]")
        XCTAssertEqual(PDFCitation.pageLink(linkTarget: "Course/Week 1 [draft].pdf", displayName: "Week 1 [draft]", pageNumber: 12, usesWikilinks: false),
                       "[Week 1 \\[draft\\], p.12](Course/Week%201%20%5Bdraft%5D.pdf#page=12)")
    }

    func testQuotesJoinBrokenLinesAndHyphenatedWords() {
        let selected = "The quick brown fox jum-\nps over the lazy dog, then\nrests.\n\nA second para-\ngraph with Hyphen-\nated Names."
        XCTAssertEqual(PDFCitation.quote(selected, link: "[[Book.pdf#page=4|Book, p.4]]"), """
            > The quick brown fox jumps over the lazy dog, then rests.
            >
            > A second paragraph with Hyphenated Names.

            [[Book.pdf#page=4|Book, p.4]]
            """)
    }

    func testQuotesAreSeparatedFromTheTextAround() {
        let quote = "> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]"
        func inserted(into source: String, at location: Int) -> String {
            let insertion = MarkdownBlockInsertion.text(inserting: quote, into: source as NSString, replacing: NSRange(location: location, length: 0),
                                                        separatedByBlankLines: true)
            return (source as NSString).replacingCharacters(in: NSRange(location: location, length: 0), with: insertion)
        }
        XCTAssertEqual(inserted(into: "# Title\nText\n", at: 0), "> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]\n\n# Title\nText\n")
        XCTAssertEqual(inserted(into: "Line one\nLine two", at: 8), "Line one\n\n> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]\n\nLine two",
                       "In the middle, blank lines on both sides.")
        XCTAssertEqual(inserted(into: "# Notes\n\n", at: 9), "# Notes\n\n> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]\n",
                       "At the end, after a blank line already there.")
        XCTAssertEqual(inserted(into: "# Notes", at: 7), "# Notes\n\n> Quoted\n\n[[Book.pdf#page=1|Book, p.1]]\n")
    }

    func testQuotesKeepHyphensBeforeDigitsAndCapitals() {
        XCTAssertEqual(PDFCitation.readableParagraphs(of: "from 1990-\n2000 in the Mid-\nAtlantic\r\nend"), ["from 1990-2000 in the Mid-Atlantic end"])
        XCTAssertEqual(PDFCitation.readableParagraphs(of: "a well-\nknown result"), ["a wellknown result"], "Indistinguishable from hyphenation.")
        XCTAssertEqual(PDFCitation.readableParagraphs(of: "  spaced   out \u{00A0} text  "), ["spaced out text"])
    }
}

final class NavigationTests: XCTestCase {
    func testFuzzyMatchingPrefersWordStartsAndRuns() throws {
        XCTAssertNil(FuzzyMatcher.match("xyz", in: "Lecture notes"))
        let wordStarts = try XCTUnwrap(FuzzyMatcher.match("ln", in: "Lecture notes"))
        let scattered = try XCTUnwrap(FuzzyMatcher.match("ln", in: "Balance sheet"))
        XCTAssertGreaterThan(wordStarts.score, scattered.score)
        XCTAssertEqual(wordStarts.matchedRanges, [0..<1, 8..<9])
        let prefix = try XCTUnwrap(FuzzyMatcher.match("lec", in: "Lecture 3"))
        let inside = try XCTUnwrap(FuzzyMatcher.match("lec", in: "Collection of lectures"))
        XCTAssertGreaterThan(prefix.score, inside.score)
        XCTAssertNotNil(FuzzyMatcher.match("ubung", in: "Übungsblatt 2"), "Accents are ignored.")
        XCTAssertEqual(FuzzyMatcher.match("💡i", in: "💡 Ideas")?.matchedRanges, [0..<2, 3..<4])
    }

    func testHistoryGoesBackAndForwardLikeABrowser() throws {
        var history = NavigationHistory()
        let first = try VaultPath("A.md"), second = try VaultPath("B.md"), third = try VaultPath("C.md")
        history.visit(first); history.visit(second); history.visit(third)
        XCTAssertEqual(history.goBack(), second)
        XCTAssertEqual(history.goBack(), first)
        XCTAssertFalse(history.canGoBack)
        XCTAssertEqual(history.goForward(), second)
        history.visit(try VaultPath("D.md"))
        XCTAssertFalse(history.canGoForward, "Visiting drops what was ahead.")
        XCTAssertEqual(history.entries.map(\.name), ["A.md", "B.md", "D.md"])
        history.replacePrefix(second, with: try VaultPath("Folder/B2.md"))
        XCTAssertEqual(history.entries.map(\.rawValue), ["A.md", "Folder/B2.md", "D.md"])
        history.remove(inside: try VaultPath("D.md"))
        XCTAssertEqual(history.current?.rawValue, "Folder/B2.md")
        history.visit(first)
        history.remove(inside: try VaultPath("Folder"))
        XCTAssertEqual(history.entries.map(\.name), ["A.md"], "A.md, then A.md again once B2 is gone, is one step.")
    }

    func testRecentFilesKeepNewestFirstWithoutRepeats() throws {
        var recent = RecentFiles()
        for name in ["A.md", "B.md", "A.md"] { recent.record(try VaultPath(name)) }
        XCTAssertEqual(recent.paths.map(\.name), ["A.md", "B.md"])
        recent.replacePrefix(try VaultPath("B.md"), with: try VaultPath("A.md"))
        XCTAssertEqual(recent.paths.map(\.name), ["A.md"])
    }
}

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

final class LinkCompletionTests: XCTestCase {
    func testLinkQueriesSplitIntoNoteHeadingAndBlock() throws {
        let text = "See [[Lect]] and more" as NSString
        guard case .link(let query) = LinkCompletion.context(in: text, cursor: 10) else { return XCTFail("Expected a link query") }
        XCTAssertEqual(query.text, "Lect")
        XCTAssertTrue(query.hasClosingBrackets)
        XCTAssertEqual(query.replacementRange, NSRange(location: 6, length: 6), "The closing ]] is replaced too.")
        guard case .link(let heading) = LinkCompletion.context(in: "[[Note#Intro" as NSString, cursor: 12) else { return XCTFail("Expected a heading query") }
        XCTAssertEqual(heading.notePart, "Note")
        XCTAssertEqual(heading.headingQuery, "Intro")
        guard case .link(let block) = LinkCompletion.context(in: "![[Note#^ab" as NSString, cursor: 11) else { return XCTFail("Expected a block query") }
        XCTAssertEqual(block.blockQuery, "ab")
        XCTAssertTrue(block.isEmbed)
        XCTAssertNil(LinkCompletion.context(in: "[[Note|alias" as NSString, cursor: 12), "The alias is not completed.")
        XCTAssertNil(LinkCompletion.context(in: "[[Done]] after" as NSString, cursor: 14))
        XCTAssertNil(LinkCompletion.context(in: "`[[code`" as NSString, cursor: 7))
        XCTAssertNil(LinkCompletion.context(in: "```\n[[in fence" as NSString, cursor: 14))
    }

    func testTagQueriesStartAfterSpaceOrLineStart() {
        XCTAssertEqual(LinkCompletion.context(in: "Tagged #lec" as NSString, cursor: 11), .tag(query: "lec", replacementRange: NSRange(location: 8, length: 3)))
        XCTAssertEqual(LinkCompletion.context(in: "#inbox/to" as NSString, cursor: 9), .tag(query: "inbox/to", replacementRange: NSRange(location: 1, length: 8)))
        XCTAssertNil(LinkCompletion.context(in: "issue#12" as NSString, cursor: 8))
        XCTAssertEqual(LinkCompletion.context(in: "#202" as NSString, cursor: 4), .tag(query: "202", replacementRange: NSRange(location: 1, length: 3)))
        XCTAssertNil(LinkCompletion.context(in: "# Heading" as NSString, cursor: 9))
    }

    func testLinkTargetsFollowTheLinkFormat() throws {
        let path = try VaultPath("Courses/Signals/Lecture 3.md")
        let note = try VaultPath("Courses/Overview.md")
        XCTAssertEqual(LinkCompletion.linkTarget(for: path, from: note, settings: ObsidianSettings(linkFormat: .shortest), isNameUnique: true), "Lecture 3")
        XCTAssertEqual(LinkCompletion.linkTarget(for: path, from: note, settings: ObsidianSettings(linkFormat: .shortest), isNameUnique: false), "Courses/Signals/Lecture 3")
        XCTAssertEqual(LinkCompletion.linkTarget(for: path, from: note, settings: ObsidianSettings(linkFormat: .relative), isNameUnique: true), "Signals/Lecture 3")
        XCTAssertEqual(LinkCompletion.linkTarget(for: try VaultPath("Slides/Deck.pdf"), from: note, settings: ObsidianSettings(), isNameUnique: true), "Deck.pdf")
    }

    func testBlocksAndTheirIdentifiers() {
        let text = "---\na: 1\n---\n# Title\nFirst paragraph\ncontinues here ^intro\n\n- item one\n  more of item one\n- item two\n\n| a | b |\n| - | - |\n^table1\n\n```\ncode\n```\n"
        let blocks = NoteBlocks.blocks(in: text)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .listItem, .listItem, .table, .code])
        guard blocks.count == 5 else { return }
        XCTAssertEqual(blocks[0].identifier, "intro")
        XCTAssertEqual(blocks[0].text, "First paragraph\ncontinues here")
        XCTAssertEqual(blocks[1].text, "- item one\n  more of item one")
        XCTAssertEqual(blocks[3].identifier, "table1")
        XCTAssertNil(blocks[4].identifier)
        XCTAssertEqual(NoteBlocks.block(withIdentifier: "INTRO", in: text)?.kind, .paragraph)
        let addedToItem = NoteBlocks.addingIdentifier("abc123", to: blocks[2], in: text)
        XCTAssertEqual((text as NSString).replacingCharacters(in: addedToItem.range, with: addedToItem.replacement).contains("- item two ^abc123\n"), true)
        let addedToCode = NoteBlocks.addingIdentifier("xyz789", to: blocks[4], in: text)
        XCTAssertTrue((text as NSString).replacingCharacters(in: addedToCode.range, with: addedToCode.replacement).hasSuffix("```\n^xyz789\n"))
        let identifier = NoteBlocks.newIdentifier(avoiding: ["intro"])
        XCTAssertEqual(identifier.count, 6)
        XCTAssertTrue(identifier.allSatisfy { character in character.isLowercase || character.isNumber })
    }
}

final class BlockEmbedTests: XCTestCase {
    func testEmbedsShowTheBlockOrSection() {
        let body = "# One\nintro\n\n## Two\nPara ^abc\n\nother"
        XCTAssertEqual(NoteBlocks.embeddedPart(of: body, subpath: "^abc"), "Para")
        XCTAssertEqual(NoteBlocks.embeddedPart(of: body, subpath: "Two"), "## Two\nPara ^abc\n\nother")
        // A subpath that names nothing is reported, as in Obsidian, not shown as the whole note.
        XCTAssertNil(NoteBlocks.embeddedPart(of: body, subpath: "^missing"))
        XCTAssertNil(NoteBlocks.embeddedPart(of: body, subpath: "Missing heading"))
        XCTAssertEqual(NoteBlocks.embeddedPart(of: body, subpath: nil), body)
    }
}
