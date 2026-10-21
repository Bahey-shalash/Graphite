import GraphiteTestSupport
import XCTest
@testable import GraphiteCore

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
