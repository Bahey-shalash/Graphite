import XCTest
@testable import GraphiteCore

/// Source ranges, exclusions and bounded work in `MarkdownSemantics.parse`.
final class CoreSemanticsParseTests: XCTestCase {
    /// The source text each link's range covers, in order.
    private func linkTexts(in source: String) throws -> [String] {
        try MarkdownSemantics.parse(source).links.map { link in (source as NSString).substring(with: link.range) }
    }

    func testWindowsLineEndingsKeepEveryMarkdownLinkRange() throws {
        let source = "[b](Old.md) x\r\n[a](Old.md)\r\n`[[Old]]` in code\r\n"
        XCTAssertEqual(try linkTexts(in: source), ["[b](Old.md)", "[a](Old.md)"], "The wikilink inside code is text.")
        let lineFeedSource = source.replacingOccurrences(of: "\r\n", with: "\n")
        XCTAssertEqual(try linkTexts(in: lineFeedSource), ["[b](Old.md)", "[a](Old.md)"])
    }

    func testWindowsLineEndingsKeepCodeExcluded() throws {
        let semantics = try MarkdownSemantics.parse("Text [[L]] #t\r\n`[[C]] #c` [[D]]")
        XCTAssertEqual(semantics.links.map(\.target), ["L", "D"])
        XCTAssertEqual(semantics.tags, ["t"])
        XCTAssertEqual(try MarkdownSemantics.parse("a\r\n```\r\n[[InCode]] #code\r\n```\r\n[[After]]").links.map(\.target), ["After"])
        let withFrontmatter = "---\r\ntags: [x]\r\n---\r\nIntro\r\n`[[C]]` then [m](M.md)\r\n"
        XCTAssertEqual(try linkTexts(in: withFrontmatter), ["[m](M.md)"])
    }

    func testOldMacLineEndingsAreLineBreaks() throws {
        XCTAssertEqual(try linkTexts(in: "[a](x.md)\r\r[b](y.md) and `[[C]]`"), ["[a](x.md)", "[b](y.md)"])
    }

    func testIndentedContinuationLinesKeepExactRanges() throws {
        XCTAssertEqual(try linkTexts(in: "Some paragraph\n  continued with [Other](Other.md) here.\n"), ["[Other](Other.md)"])
        XCTAssertEqual(try linkTexts(in: "first\n\tsee [x](y.md)"), ["[x](y.md)"])
        XCTAssertEqual(try linkTexts(in: "- item\n\tcontinued [x](y.md)"), ["[x](y.md)"])
        XCTAssertEqual(try linkTexts(in: "- item\n    continued [x](y.md)"), ["[x](y.md)"])
        XCTAssertEqual(try linkTexts(in: "> quote\n>   continued [x](y.md)"), ["[x](y.md)"])
        XCTAssertEqual(try linkTexts(in: "> quote\n   lazily [x](y.md)"), ["[x](y.md)"])
        XCTAssertEqual(try linkTexts(in: "> - item\n>   more [x](y.md)\n> > nested\n> >  deeper ![i](i.png)"), ["[x](y.md)", "![i](i.png)"])
        XCTAssertEqual(try linkTexts(in: "  indented start [a](a.md)\n    é then ü [b](b.md) 😀 [c](c.md)"), ["[a](a.md)", "[b](b.md)", "[c](c.md)"])
        XCTAssertEqual(try linkTexts(in: "Title [a](a.md)\n  under [b](b.md)\n---"), ["[a](a.md)", "[b](b.md)"], "A setext heading's second line.")
    }

    func testLinksSpanningLinesAndCodeOnContinuationLines() throws {
        XCTAssertEqual(try linkTexts(in: "Start [a\n   b](c.md) end"), ["[a\n   b](c.md)"])
        XCTAssertEqual(try MarkdownSemantics.parse("text\n  `[[Code]]` [[Real]]\r\n   <a title=\"[[Html]]\">x</a>").links.map(\.target), ["Real"])
    }

    func testEscapedAndDoubledEmbedMarkersStillLink() throws {
        let escaped = try MarkdownSemantics.parse("\\![[E]]")
        XCTAssertEqual(escaped.links.map(\.target), ["E"])
        XCTAssertEqual(escaped.links.first?.isEmbed, false)
        XCTAssertEqual(try linkTexts(in: "\\![[E]]"), ["[[E]]"])
        let doubled = try MarkdownSemantics.parse("!![[E]]")
        XCTAssertEqual(doubled.links.first?.isEmbed, true)
        XCTAssertEqual(try linkTexts(in: "!![[E]]"), ["![[E]]"])
        XCTAssertTrue(try MarkdownSemantics.parse("\\[[E]]").links.isEmpty, "An escaped bracket is text.")
        XCTAssertEqual(try MarkdownSemantics.parse("\\\\![[E]]").links.first?.isEmbed, true, "An escaped backslash leaves the embed.")
    }

    func testEmojiTagsKeepSkinToneModifiers() throws {
        XCTAssertEqual(try MarkdownSemantics.parse("Great #👍🏽 work").tags, ["👍🏽"])
        XCTAssertTrue(TagSyntax.isValidTag("👍🏽"))
        XCTAssertTrue(TagSyntax.isValidTag("🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"), "A subdivision flag.")
        XCTAssertEqual(try MarkdownSemantics.parse("#tag^block").tags, ["tag"], "Other modifier symbols still end a tag.")
    }

    func testAliasBombInFrontmatterIsRefusedQuickly() throws {
        var lines = ["a0: &a0 [x, x, x, x, x, x, x, x, x, x]"]
        for level in 1...9 { lines.append("a\(level): &a\(level) [" + Array(repeating: "*a\(level - 1)", count: 10).joined(separator: ", ") + "]") }
        let source = "---\n" + lines.joined(separator: "\n") + "\ntags: [kept]\n---\nBody [[Link]]\n"
        let start = Date()
        let semantics = try MarkdownSemantics.parse(source)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "The expansion stops at the node budget.")
        XCTAssertTrue(semantics.tags.isEmpty, "Properties that would expand without bound are not read.")
        XCTAssertEqual(semantics.links.map(\.target), ["Link"], "The body is still indexed.")
    }

    func testOrdinaryAliasesInFrontmatterStillWork() throws {
        let semantics = try MarkdownSemantics.parse("---\nshared: &shared [fiction, classic]\ntags: *shared\naliases: [Book]\n---\nBody\n")
        XCTAssertEqual(semantics.tags, ["classic", "fiction"])
        XCTAssertEqual(semantics.aliases, ["Book"])
    }

    func testLinkDenseNotesKeepEveryLinkAndTag() throws {
        let source = (0..<3_000).map { index in "Line \(index) [[Note \(index)]] #tag\(index) `[[Code \(index)]] #code` [m](m\(index).md)" }.joined(separator: "\r\n")
        let semantics = try MarkdownSemantics.parse(source)
        XCTAssertEqual(semantics.links.count, 6_000)
        XCTAssertEqual(semantics.tags.count, 3_000)
        XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(semantics.links.last).range), "[m](m2999.md)")
    }

    /// Every Markdown link range, in notes mixing line endings, quotes, lists, tabs,
    /// lazy continuation lines and multi-byte text, covers exactly `[label](target)`.
    func testMarkdownLinkRangesCoverTheirSourceInVariedNotes() throws {
        var generator = ParseTestGenerator(seed: 7)
        let prefixes = ["", "  ", "\t", "    ", "> ", ">  ", "> > ", "- ", "  - ", "1. ", "> - ", "   ", " ", ">\t", "-\t", "# ", "| ", "\t\t", ">> ", "* > ", "2) \t"]
        let words = ["text", "é", "😀", "ü ö", "**b**", "*i*", "`c`", "[[W]]", "#tag", "<b>", "x", "\t", "|", "\\", "---", "==="]
        for _ in 0..<1_500 {
            let lineBreak = ["\n", "\r\n", "\r"][generator.index(below: 3)]
            var lines: [String] = []
            var linkCount = 0
            for _ in 0..<(1 + generator.index(below: 6)) {
                var line = prefixes[generator.index(below: prefixes.count)]
                for _ in 0..<generator.index(below: 5) {
                    if generator.index(below: 2) == 0 {
                        line += (generator.index(below: 2) == 0 ? "!" : "") + "[l \(words[generator.index(below: words.count)])](d\(linkCount).md) "
                        linkCount += 1
                    } else {
                        line += words[generator.index(below: words.count)] + " "
                    }
                }
                lines.append(line)
            }
            let source = lines.joined(separator: lineBreak)
            for link in try MarkdownSemantics.parse(source).links where !link.isWiki {
                let linkText = (source as NSString).substring(with: link.range)
                XCTAssertTrue((linkText.hasPrefix("[") || linkText.hasPrefix("![")) && linkText.hasSuffix("(\(link.target))"), "\(source.debugDescription): \(linkText.debugDescription)")
            }
        }
    }
}

/// A small deterministic generator, so the varied notes are the same on every run.
private struct ParseTestGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func index(below count: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(count))
    }
}

extension CoreSemanticsParseTests {
    func testLinesContinuingACodeSpanOrTagKeepExactRanges() throws {
        XCTAssertEqual(try linkTexts(in: "a `b\nc` [x](y.md)"), ["[x](y.md)"])
        XCTAssertEqual(try linkTexts(in: "a `b\n  c` [x](y.md) [[W]]"), ["[x](y.md)", "[[W]]"])
        XCTAssertEqual(try linkTexts(in: "> a `b\n> c` [x](y.md)"), ["[x](y.md)"])
        XCTAssertEqual(try linkTexts(in: "[a\n](x.md) b [c](d.md)"), ["[a\n](x.md)", "[c](d.md)"])
        XCTAssertEqual(try linkTexts(in: "t\n  [u\nv](w.md) [z](z.md)"), ["[u\nv](w.md)", "[z](z.md)"])
        XCTAssertEqual(try linkTexts(in: "a <span\n  x=1> [x](y.md)"), ["[x](y.md)"])
    }
}

extension CoreSemanticsParseTests {
    /// cmark leaves the line number unchanged at a backslash hard break and at a break
    /// inside a link's destination or title; the columns run on across the break.
    func testHardBreaksAndMultiLineLinksKeepExactRanges() throws {
        XCTAssertEqual(try linkTexts(in: "hard  \n   [x](x.md) and\\\n [y](y.md)"), ["[x](x.md)", "[y](y.md)"])
        XCTAssertEqual(try linkTexts(in: "a [b](c.md\n'x') d\\\ne [f](f.md)\ng [h](h.md)"), ["[b](c.md\n'x')", "[f](f.md)", "[h](h.md)"])
        XCTAssertEqual(try linkTexts(in: "> a\\\n> b [x](x.md)\n> c [y](y.md)"), ["[x](x.md)", "[y](y.md)"])
        XCTAssertEqual(try linkTexts(in: "- a\\\n  b [x](x.md)\n  c [y](y.md)"), ["[x](x.md)", "[y](y.md)"])
        XCTAssertEqual(try linkTexts(in: "x\r\ny\\\r\nz [a](a.md)\r\n  w [b](b.md)"), ["[a](a.md)", "[b](b.md)"], "A CRLF break counts once.")
        XCTAssertEqual(try linkTexts(in: "[a](b.md\r\n  \"t\") [c](c.md)\r\nnext [d](d.md)"), ["[a](b.md\r\n  \"t\")", "[c](c.md)", "[d](d.md)"])
        XCTAssertEqual(try linkTexts(in: "x\ry\\\rz [a](a.md)\r  w [b](b.md)"), ["[a](a.md)", "[b](b.md)"])
    }

    /// The end of a code span or HTML tag that spans lines is counted from its last line's
    /// start, without the paragraph's first column.
    func testCodeAndHTMLSpanningLinesInsideContainersKeepExactRanges() throws {
        XCTAssertEqual(try linkTexts(in: "> a `b\n> c` [x](y.md) `[[C]]` [[W]]"), ["[x](y.md)", "[[W]]"])
        XCTAssertEqual(try linkTexts(in: "- a ``b\n  c`` [x](y.md)"), ["[x](y.md)"])
        XCTAssertEqual(try linkTexts(in: "- a <span\n  x=1> [x](y.md)"), ["[x](y.md)"])
        XCTAssertEqual(try linkTexts(in: "a <span\r\n  x=1> [x](y.md)"), ["[x](y.md)"])
    }

    /// cmark drops a leading link reference definition from its paragraph's positions, which
    /// the converter does not model: such a range is left empty rather than pointing at other
    /// text, and code in the paragraph is still excluded.
    func testMisplacedLinkRangesAreEmptyRatherThanWrong() throws {
        let source = "[r]: r.md\ntext [x](x.md) `[[InCode]]`"
        let semantics = try MarkdownSemantics.parse(source)
        let link = try XCTUnwrap(semantics.links.first { link in link.target == "x.md" })
        XCTAssertTrue(link.length == 0 || (source as NSString).substring(with: link.range) == "[x](x.md)")
        XCTAssertFalse(semantics.links.contains { link in link.target == "InCode" }, "Code found from the text stays excluded.")
    }

    /// Notes with hard breaks, links and code spanning lines, and every line ending: each
    /// Markdown link's range covers exactly its source.
    func testMarkdownLinkRangesAreExactAcrossBreaksInVariedNotes() throws {
        var generator = ParseTestGenerator(seed: 11)
        let prefixes = ["", "  ", " ", "\t", "# ", "   "]
        let words = ["text", "é", "😀", "**b**", "`c`", "`multi\u{0}line`", "<b>", "<span\u{0}x=1>", "[[W]]", "#tag", "\\", "x", "*i\u{0}j*"]
        let lineEndings = ["", "\\", "  ", " "]
        for _ in 0..<1_500 {
            let lineBreak = ["\n", "\r\n", "\r"][generator.index(below: 3)]
            var lines: [String] = []
            var linkCount = 0
            for _ in 0..<(1 + generator.index(below: 6)) {
                var line = prefixes[generator.index(below: prefixes.count)]
                for _ in 0..<generator.index(below: 5) {
                    switch generator.index(below: 4) {
                    case 0: line += "[l w](d\(linkCount).md) "; linkCount += 1
                    case 1: line += "[l](d\(linkCount).md\u{0}\"title\") "; linkCount += 1
                    case 2: line += "![i](d\(linkCount).md) "; linkCount += 1
                    default: line += words[generator.index(below: words.count)] + " "
                    }
                }
                lines.append(line + lineEndings[generator.index(below: lineEndings.count)])
            }
            let source = lines.joined(separator: lineBreak).replacingOccurrences(of: "\u{0}", with: lineBreak)
            for link in try MarkdownSemantics.parse(source).links where !link.isWiki {
                let linkText = (source as NSString).substring(with: link.range)
                XCTAssertTrue((linkText.hasPrefix("[") || linkText.hasPrefix("![")) && linkText.hasSuffix(")") && linkText.contains(link.target),
                              "\(source.debugDescription): \(linkText.debugDescription)")
            }
        }
    }

    /// Where the converter cannot place a range exactly (lazy lines, reference definitions),
    /// a Markdown link's range is empty or exact, never other text.
    func testMarkdownLinkRangesAreExactOrEmptyInNestedNotes() throws {
        var generator = ParseTestGenerator(seed: 23)
        let prefixes = ["", "  ", "> ", "> > ", "- ", "  - ", "> - ", "   ", "[r]: r.md ", "1. ", ">\t", "\t"]
        let words = ["text", "é", "`c`", "`multi\u{0}line`", "<span\u{0}x=1>", "[[W]]", "\\", "x"]
        let lineEndings = ["", "\\", "  "]
        for _ in 0..<1_500 {
            let lineBreak = ["\n", "\r\n", "\r"][generator.index(below: 3)]
            var lines: [String] = []
            var linkCount = 0
            for _ in 0..<(1 + generator.index(below: 6)) {
                var line = prefixes[generator.index(below: prefixes.count)]
                for _ in 0..<generator.index(below: 5) {
                    switch generator.index(below: 3) {
                    case 0: line += "[l](d\(linkCount).md) "; linkCount += 1
                    case 1: line += "[l](d\(linkCount).md\u{0}\"title\") "; linkCount += 1
                    default: line += words[generator.index(below: words.count)] + " "
                    }
                }
                lines.append(line + lineEndings[generator.index(below: lineEndings.count)])
            }
            let source = lines.joined(separator: lineBreak).replacingOccurrences(of: "\u{0}", with: lineBreak)
            for link in try MarkdownSemantics.parse(source).links where !link.isWiki && link.length > 0 {
                let linkText = (source as NSString).substring(with: link.range)
                // "[r]" is a reference link to the definition's r.md.
                let isExact = link.target == "r.md" ? linkText == "[r]" : linkText.hasPrefix("[") && linkText.hasSuffix(")") && linkText.contains(link.target)
                XCTAssertTrue(isExact, "\(source.debugDescription): \(linkText.debugDescription)")
            }
        }
    }
}
