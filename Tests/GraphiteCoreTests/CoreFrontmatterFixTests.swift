import Markdown
import XCTest
@testable import GraphiteCore

/// Edits through the Properties panel parse the note, change one property, and write the
/// whole list back; these helpers do the same.
private func panelEdit(_ note: String, setting key: String, to value: PropertyValue) throws -> String {
    let yaml = try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: note))
    let properties = try XCTUnwrap(NoteProperties.parse(yaml))
    let edited = properties.contains { property in property.key == key }
        ? properties.map { property in property.key == key ? NoteProperty(key: key, value: value) : property }
        : properties + [NoteProperty(key: key, value: value)]
    return NoteProperties.replacingFrontmatter(in: note, with: edited)
}

private func panelRemoval(_ note: String, removing key: String) throws -> String {
    let properties = try XCTUnwrap(NoteProperties.parse(try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: note))))
    return NoteProperties.replacingFrontmatter(in: note, with: properties.filter { property in property.key != key })
}

final class CoreFrontmatterUntouchedPropertiesTests: XCTestCase {
    func testNestedListItemsSurviveAnEditOfAnotherProperty() throws {
        let note = "---\ntitle: a\nlinks:\n  - name: one\n    url: two\n  - plain\n  - [x, y]\n---\nBody\n"
        let properties = try XCTUnwrap(NoteProperties.parse(try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: note))))
        guard case .unsupported(let yaml) = properties[1].value else { return XCTFail("A list holding mappings is shown as YAML, not as its text items.") }
        XCTAssertTrue(yaml.contains("name: one"), yaml)
        XCTAssertEqual(try panelEdit(note, setting: "title", to: .text("changed")),
                       "---\ntitle: changed\nlinks:\n  - name: one\n    url: two\n  - plain\n  - [x, y]\n---\nBody\n")
        // Even the full rewrite, used only when lines cannot be matched, keeps the items.
        let rewritten = NoteProperties.serialize(properties)
        XCTAssertEqual(NoteProperties.parse(rewritten), properties)
    }

    func testNumbersKeepTheirSpellingInBothEditPaths() throws {
        let note = "---\nstatus: draft\nid: 9007199254740993\ntweet: 1234567890123456789\nzip: 00123\nversion: 1.10\nyears: [2023, 2024]\n---\nBody"
        let expected = "---\nstatus: done\nid: 9007199254740993\ntweet: 1234567890123456789\nzip: 00123\nversion: 1.10\nyears: [2023, 2024]\n---\nBody"
        XCTAssertEqual(try panelEdit(note, setting: "status", to: .text("done")), expected)
        XCTAssertEqual(try BasePropertyEditing.settingProperty("status", to: .text("done"), in: note), expected)
    }

    func testChangedWholeNumbersAreWrittenWithoutExponentOrFraction() throws {
        XCTAssertEqual(NoteProperties.formatted(1_234_567_890_123_456_768), "1234567890123456768")
        XCTAssertEqual(NoteProperties.formatted(1e16), "10000000000000000")
        XCTAssertEqual(NoteProperties.formatted(1e20), "100000000000000000000")
        XCTAssertEqual(NoteProperties.formatted(-42), "-42")
        XCTAssertEqual(NoteProperties.formatted(4.5), "4.5")
        let written = NoteProperties.serialize([NoteProperty(key: "big", value: .number(1e20))])
        XCTAssertEqual(NoteProperties.parse(written), [NoteProperty(key: "big", value: .number(1e20))])
    }

    func testCommentsAnchorsTagsAndBlockScalarsAreKept() throws {
        let note = "---\n# about this note\nstatus: todo # keep me\n# note\nother: 1\nbase: &anchor hello\ncopy: *anchor\nx: !!str 5\ndesc: >\n  folded\n  text\n---\nBody"
        let updated = try BasePropertyEditing.settingProperty("status", to: .text("done"), in: note)
        XCTAssertEqual(updated, note.replacingOccurrences(of: "status: todo # keep me", with: "status: done # keep me"))
        XCTAssertEqual(try panelEdit(note, setting: "other", to: .number(2)), note.replacingOccurrences(of: "other: 1", with: "other: 2"))
        let added = try BasePropertyEditing.settingProperty("rating", to: .number(5), in: note)
        XCTAssertEqual(added, note.replacingOccurrences(of: "  text\n---", with: "  text\nrating: 5\n---"), "A property is appended after a block scalar.")
    }

    func testAQuotedHashIsNotTakenForAComment() throws {
        let note = "---\ntitle: \"a # b\" # real comment\n---\n"
        XCTAssertEqual(try panelEdit(note, setting: "title", to: .text("c")), "---\ntitle: c # real comment\n---\n")
    }

    func testRemovingAPropertyKeepsTheCommentAboutTheNextOne() throws {
        let note = "---\na: 1\n# about b\nb: 2\n---\n"
        XCTAssertEqual(try panelRemoval(note, removing: "a"), "---\n# about b\nb: 2\n---\n")
        XCTAssertEqual(try panelRemoval(note, removing: "b"), "---\na: 1\n# about b\n---\n")
    }

    func testChangingAnAnchoredValueStillKeepsItsAliasesMeaning() throws {
        let note = "---\nbase: &anchor hello\ncopy: *anchor\n---\nBody"
        let updated = try panelEdit(note, setting: "base", to: .text("bye"))
        let properties = try XCTUnwrap(NoteProperties.parse(try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: updated))))
        XCTAssertEqual(properties, [NoteProperty(key: "base", value: .text("bye")), NoteProperty(key: "copy", value: .text("hello"))])
        XCTAssertTrue(updated.hasSuffix("---\nBody"))
    }

    func testFlowMappingFrontmatterIsStillRewritten() throws {
        let updated = try panelEdit("---\n{a: 1, b: two}\n---\nBody", setting: "a", to: .number(3))
        XCTAssertEqual(updated, "---\na: 3\nb: two\n---\nBody")
    }

    func testComplexKeysAreNeverDropped() throws {
        let note = "---\ntitle: a\n? [a, b]\n: c\n---\nBody\n"
        XCTAssertEqual(try panelEdit(note, setting: "title", to: .text("changed")), "---\ntitle: changed\n? [a, b]\n: c\n---\nBody\n")
        XCTAssertEqual(try BasePropertyEditing.settingProperty("title", to: .text("changed"), in: note), "---\ntitle: changed\n? [a, b]\n: c\n---\nBody\n")
        XCTAssertEqual(try panelRemoval(note, removing: "title"), "---\n? [a, b]\n: c\n---\nBody\n", "The frontmatter stays while an entry remains.")
    }

    func testCommaSeparatedTagsAreTwoTagsAndStayAsWritten() throws {
        XCTAssertEqual(NoteProperties.parse("tags: alpha, beta")?.first?.value, .list(["alpha", "beta"]))
        let note = "---\ndone: false\ntags: alpha, beta\n---\n"
        XCTAssertEqual(try panelEdit(note, setting: "done", to: .checkbox(true)), "---\ndone: true\ntags: alpha, beta\n---\n")
        XCTAssertEqual(try panelEdit(note, setting: "tags", to: .list(["alpha", "beta", "gamma"])),
                       "---\ndone: false\ntags:\n  - alpha\n  - beta\n  - gamma\n---\n")
    }

    func testFrontmatterLineEndingsComeFromTheFrontmatter() throws {
        let note = "---\ntitle: a\n---\nBody\r\nmore\n"
        XCTAssertEqual(try panelEdit(note, setting: "title", to: .text("changed")), "---\ntitle: changed\n---\nBody\r\nmore\n")
        XCTAssertEqual(try panelEdit(note, setting: "added", to: .text("x")), "---\ntitle: a\nadded: x\n---\nBody\r\nmore\n")
        XCTAssertEqual(try panelEdit("---\r\ntitle: a\r\n---\r\nBody\n", setting: "added", to: .text("x")), "---\r\ntitle: a\r\nadded: x\r\n---\r\nBody\n")
    }

    func testCommentOnlyFrontmatterHasNoPropertiesAndCanBeEdited() throws {
        XCTAssertEqual(NoteProperties.parse("# just a comment"), [])
        let note = "---\n# just a comment\n---\nBody"
        XCTAssertEqual(try BasePropertyEditing.settingProperty("status", to: .text("done"), in: note), "---\n# just a comment\nstatus: done\n---\nBody")
        XCTAssertEqual(try panelEdit(note, setting: "status", to: .text("done")), "---\n# just a comment\nstatus: done\n---\nBody")
    }
}

final class CoreFrontmatterValueWritingTests: XCTestCase {
    func testTextThatPlainYAMLWouldChangeIsQuotedAndReadsBack() throws {
        let texts = ["a\r\nb", "a\t#b", "a:\tb", "a\u{2028}b", "a\u{85}b", "a\u{7}b", "a\u{9F}b", "trailing tab\t",
                     "line\nbreak", "inf", ".inf", "a # b", "ends:", "\"quoted\" at the start \\ with a backslash"]
        for text in texts {
            let yaml = NoteProperties.serialize([NoteProperty(key: "k", value: .text(text))])
            XCTAssertTrue(yaml.hasPrefix("k: \""), "Quoted: \(yaml.debugDescription)")
            XCTAssertEqual(NoteProperties.parse(yaml), [NoteProperty(key: "k", value: .text(text))], yaml.debugDescription)
        }
        for plainText in ["back\\slash \"quoted\" inside", "tab\tinside", "a#b"] {
            let yaml = NoteProperties.serialize([NoteProperty(key: "k", value: .text(plainText))])
            XCTAssertEqual(yaml, "k: \(plainText)\n", "Plain YAML reads these back unchanged.")
            XCTAssertEqual(NoteProperties.parse(yaml), [NoteProperty(key: "k", value: .text(plainText))])
        }
        // libyaml drops a byte order mark even when escaped, so it cannot survive; quoting
        // still keeps the YAML valid and the rest of the text.
        XCTAssertEqual(NoteProperties.parse(NoteProperties.serialize([NoteProperty(key: "k", value: .text("\u{FEFF}text"))])), [NoteProperty(key: "k", value: .text("text"))])
        XCTAssertEqual(NoteProperties.quotedIfNeeded("plain words"), "plain words")
        let key = NoteProperties.serialize([NoteProperty(key: "odd\u{2028}key", value: .text("v"))])
        XCTAssertEqual(NoteProperties.parse(key)?.first?.key, "odd\u{2028}key", "Keys are quoted the same way.")
    }

    func testNonFiniteNumbersUseYAMLSpellings() {
        for number in [Double.infinity, -Double.infinity] {
            let yaml = NoteProperties.serialize([NoteProperty(key: "k", value: .number(number))])
            XCTAssertEqual(NoteProperties.parse(yaml), [NoteProperty(key: "k", value: .number(number))], yaml)
        }
        let notANumber = NoteProperties.serialize([NoteProperty(key: "k", value: .number(.nan))])
        XCTAssertEqual(notANumber, "k: .nan\n")
        guard case .number(let number) = NoteProperties.parse(notANumber)?.first?.value, number.isNaN else { return XCTFail("`.nan` reads back as a number.") }
    }

    func testDateTextThatIsNotADateIsQuoted() throws {
        let updated = try BasePropertyEditing.settingProperty("due", to: .date("TBD: later"), in: "Body", declaredTypes: ["due": .date])
        XCTAssertEqual(updated, "---\ndue: \"TBD: later\"\n---\nBody")
        XCTAssertEqual(NoteProperties.parse(try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: updated)), declaredTypes: ["due": .date]),
                       [NoteProperty(key: "due", value: .date("TBD: later"))])
        let dateTime = NoteProperties.serialize([NoteProperty(key: "at", value: .dateTime("x # y"))])
        XCTAssertEqual(NoteProperties.parse(dateTime, declaredTypes: ["at": .datetime]), [NoteProperty(key: "at", value: .dateTime("x # y"))])
        XCTAssertEqual(NoteProperties.serialize([NoteProperty(key: "due", value: .date("2026-09-23"))]), "due: 2026-09-23\n", "Real dates stay plain.")
    }
}

final class CoreFrontmatterBaseEditingTests: XCTestCase {
    func testOrdinaryNotesCanBeEditedWithoutTypesJSON() throws {
        let frontmatters = ["tags: fiction", "tags:", "tags: [fiction, 2024]", "years: [2023, 2024]", "list:\n  - a\n  -\n  - b",
                            "due: \"TBD: later\"", "items:\n  - name: a\n    count: 1"]
        for frontmatter in frontmatters {
            let note = "---\nstatus: todo\n\(frontmatter)\n---\nBody"
            let updated = try BasePropertyEditing.settingProperty("status", to: .text("done"), in: note, declaredTypes: ["due": .date])
            XCTAssertEqual(updated, "---\nstatus: done\n\(frontmatter)\n---\nBody")
        }
    }

    func testTextSetOnTagsIsReadAsTheTagsItNames() throws {
        for text in ["fiction classic", "fiction,classic"] {
            XCTAssertEqual(try BasePropertyEditing.settingProperty("tags", to: .text(text), in: "---\ntags: fiction\n---\n"), "---\ntags: \(text)\n---\n")
        }
    }

    func testTheNewValueMustReadBackAsWritten() throws {
        let updated = try BasePropertyEditing.settingProperty("note", to: .text("a # b"), in: "Body")
        XCTAssertEqual(NoteProperties.parse(try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: updated))), [NoteProperty(key: "note", value: .text("a # b"))])
        XCTAssertEqual(try BasePropertyEditing.settingProperty("rating", to: .number(4.5), in: "---\nrating: 3\n---\n", declaredTypes: ["rating": .text]),
                       "---\nrating: 4.5\n---\n", "A number set on a text property is accepted: it reads back as the same text.")
    }
}

final class CoreFrontmatterBlockTests: XCTestCase {
    private func applying(_ edit: MarkdownTextEdit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testCodeInsideAListItemIsNeitherSplitNorGivenAnIdentifier() throws {
        let text = "- item\n  ```\n  code\n\n  x = 1 ^fake\n  ```\n\nAfter\n"
        XCTAssertNil(NoteBlocks.block(withIdentifier: "fake", in: text))
        let blocks = NoteBlocks.blocks(in: text)
        XCTAssertEqual(blocks.map(\.kind), [.listItem, .code, .paragraph])
        XCTAssertEqual(blocks[0].text, "- item")
        XCTAssertEqual(blocks[1].text, "  ```\n  code\n\n  x = 1 ^fake\n  ```")
        XCTAssertEqual(applying(NoteBlocks.addingIdentifier("abc123", to: blocks[0], in: text), to: text),
                       "- item ^abc123\n  ```\n  code\n\n  x = 1 ^fake\n  ```\n\nAfter\n")
        XCTAssertEqual(applying(NoteBlocks.addingIdentifier("abc123", to: blocks[1], in: text), to: text),
                       "- item\n  ```\n  code\n\n  x = 1 ^fake\n  ```\n  ^abc123\n\nAfter\n", "The marker stays inside the list item.")
    }

    func testSetextHeadingsAndThematicBreaksAreNotBlocks() {
        XCTAssertEqual(NoteBlocks.blocks(in: "Heading text\n---\n\nPara\n").map(\.text), ["Para"])
        XCTAssertEqual(NoteBlocks.blocks(in: "Heading text\n===\nPara\n").map(\.text), ["Para"])
        XCTAssertEqual(NoteBlocks.blocks(in: "Para\n\n---\n\n***\n\n- - -\n\n___\n\nNext\n").map(\.text), ["Para", "Next"])
        XCTAssertEqual(NoteBlocks.blocks(in: "Para\n***\nNext\n").map(\.text), ["Para", "Next"], "A thematic break ends a paragraph.")
    }

    func testObsidianStructuredBlockIdentifiers() throws {
        let text = "> quote line\n\n^quote-id\n\n| a | b |\n| - | - |\n| 1 | 2 |\n\n^table-id\n\n- one\n- two\n\n^list-id\n\nAfter\n"
        XCTAssertEqual(NoteBlocks.block(withIdentifier: "quote-id", in: text)?.text, "> quote line")
        XCTAssertEqual(NoteBlocks.block(withIdentifier: "table-id", in: text)?.text, "| a | b |\n| - | - |\n| 1 | 2 |")
        let list = try XCTUnwrap(NoteBlocks.block(withIdentifier: "list-id", in: text))
        XCTAssertEqual(list.kind, .list)
        XCTAssertEqual(list.text, "- one\n- two")
        XCTAssertEqual(NoteBlocks.embeddedPart(of: text, subpath: "^list-id"), "- one\n- two")
        XCTAssertEqual(NoteBlocks.blocks(in: text).map(\.kind), [.quote, .table, .listItem, .listItem, .list, .paragraph])
    }

    func testTableAndQuoteIdentifiersGoAfterABlankLine() throws {
        let tableText = "| a | b |\n| - | - |\n| 1 | 2 |\n\nafter\n"
        let blocks = NoteBlocks.blocks(in: tableText)
        let edited = applying(NoteBlocks.addingIdentifier("abc123", to: blocks[0], in: tableText), to: tableText)
        XCTAssertEqual(edited, "| a | b |\n| - | - |\n| 1 | 2 |\n\n^abc123\n\nafter\n")
        let table = try XCTUnwrap(Document(parsing: edited).child(at: 0) as? Markdown.Table)
        XCTAssertEqual(table.body.childCount, 1, "The marker is not a table row.")
        XCTAssertEqual(NoteBlocks.block(withIdentifier: "abc123", in: edited)?.kind, .table)

        let quoteText = "> quote\n# Heading\n"
        let quote = try XCTUnwrap(NoteBlocks.blocks(in: quoteText).first)
        XCTAssertEqual(applying(NoteBlocks.addingIdentifier("abc123", to: quote, in: quoteText), to: quoteText), "> quote\n\n^abc123\n\n# Heading\n",
                       "A blank line after the marker keeps the next block apart.")
    }

    func testLazyContinuationLinesStayWithTheirQuoteOrTable() throws {
        let quoteText = "> quote\nlazy line\n\nafter\n"
        let quote = try XCTUnwrap(NoteBlocks.blocks(in: quoteText).first)
        XCTAssertEqual(quote.text, "> quote\nlazy line")
        let quoteEdited = applying(NoteBlocks.addingIdentifier("abc123", to: quote, in: quoteText), to: quoteText)
        XCTAssertEqual(quoteEdited, "> quote\nlazy line\n\n^abc123\n\nafter\n", "The marker does not split the lazy line from its quote.")
        let blockQuote = try XCTUnwrap(Document(parsing: quoteEdited).child(at: 0) as? BlockQuote)
        XCTAssertTrue(blockQuote.format().contains("lazy line"), "The lazy line is still quoted.")

        let tableText = "| a |\n| - |\n| 1 |\nlazy\n\nafter\n"
        let table = try XCTUnwrap(NoteBlocks.blocks(in: tableText).first)
        XCTAssertEqual(table.text, "| a |\n| - |\n| 1 |\nlazy")
        let tableEdited = applying(NoteBlocks.addingIdentifier("abc123", to: table, in: tableText), to: tableText)
        XCTAssertEqual(tableEdited, "| a |\n| - |\n| 1 |\nlazy\n\n^abc123\n\nafter\n")
        XCTAssertEqual(try XCTUnwrap(Document(parsing: tableEdited).child(at: 0) as? Markdown.Table).body.childCount, 2, "The lazy row stays in the table.")
        XCTAssertEqual(NoteBlocks.blocks(in: "> quote\n>\nnot lazy\n").map(\.kind), [.quote, .paragraph], "An empty quote line ends the quoted text.")
    }

    func testIdentifierLinesKeepCRLFLineEndings() throws {
        let text = "| a |\r\n| - |\r\n| 1 |\r\n\r\nafter\r\n"
        let table = try XCTUnwrap(NoteBlocks.blocks(in: text).first)
        XCTAssertEqual(applying(NoteBlocks.addingIdentifier("abc123", to: table, in: text), to: text), "| a |\r\n| - |\r\n| 1 |\r\n\r\n^abc123\r\n\r\nafter\r\n")
        let code = "```\r\ncode\r\n```"
        let codeBlock = try XCTUnwrap(NoteBlocks.blocks(in: code).first)
        XCTAssertEqual(applying(NoteBlocks.addingIdentifier("abc123", to: codeBlock, in: code), to: code), "```\r\ncode\r\n```\r\n^abc123",
                       "At the end of the note the note's own line ending is used.")
    }

    func testIndentedCodeAndInlineMathDoNotConfuseBlocks() {
        let indentedCode = NoteBlocks.blocks(in: "Para\n\n    code line ^inside\n\n    more code\n\nAfter\n")
        XCTAssertEqual(indentedCode.map(\.kind), [.paragraph, .code, .paragraph])
        XCTAssertNil(NoteBlocks.block(withIdentifier: "inside", in: "Para\n\n    code line ^inside\n"))
        XCTAssertEqual(indentedCode[1].text, "    code line ^inside\n\n    more code")
        XCTAssertEqual(NoteBlocks.blocks(in: "- item\n\n    continued item paragraph ^para\n").last?.identifier, "para",
                       "Indented text under a list item is not code.")

        let math = NoteBlocks.blocks(in: "$$a$$ and text\n\npara two\n\nlast $$\n")
        XCTAssertEqual(math.map(\.kind), [.paragraph, .paragraph, .paragraph])
        XCTAssertEqual(math.map(\.text), ["$$a$$ and text", "para two", "last $$"])
        XCTAssertEqual(NoteBlocks.blocks(in: "$$\nx = 1\n$$\n").map(\.kind), [.math])
        XCTAssertEqual(NoteBlocks.blocks(in: "$$x$$\n").map(\.kind), [.math])
    }
}
