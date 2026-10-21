import XCTest
@testable import GraphiteCore

/// A setext heading (`Title` over `=====` or `-----`) is a heading in the outline, in heading
/// links and section embeds, and in the reading view's blocks, as it is in the editor.
final class NotePreviewDocumentSetextHeadingTests: XCTestCase {
    private let note = "Title\n=====\nIntro\n\nSub\n---\nBody\n\n## Atx\nEnd"

    func testOutlineListsSetextHeadingsWithTheirLevels() {
        let outline = NotePreviewDocument.outline(of: note)
        XCTAssertEqual(outline.map(\.level), [1, 2, 2])
        XCTAssertEqual(outline.map(\.text), ["Title", "Sub", "Atx"])
        XCTAssertEqual(outline.map(\.anchor), ["title", "sub", "atx"])
    }

    func testSectionEmbedOfASetextHeadingRunsToTheNextHeadingOfTheSameOrHigherLevel() {
        XCTAssertEqual(NotePreviewDocument.locatedSectionIfPresent(of: note, headingAnchor: "sub")?.text, "Sub\n---\nBody\n")
        XCTAssertEqual(NotePreviewDocument.locatedSectionIfPresent(of: note, headingAnchor: "title")?.text, note)
    }

    func testReadingViewBlocksMakeSetextHeadingsHeadingBlocks() {
        let blocks = NotePreviewDocument.blocks(from: "Title\n=====\nIntro\n\nSub\n---\nBody")
        XCTAssertEqual(blocks, [.heading(level: 1, text: "Title", anchor: "title"), .markdown("Intro\n"),
                                .heading(level: 2, text: "Sub", anchor: "sub"), .markdown("Body")])
    }

    func testAHeadingBlockStartsAtItsTextLine() {
        let located = NotePreviewDocument.locatedBlocks(from: "Intro\n\nSub\n---\nBody")
        XCTAssertEqual(located.map(\.startOffset), [0, 7, 15])
    }

    func testARuleAfterABlankLineIsNotAHeadingUnderline() {
        let blocks = NotePreviewDocument.blocks(from: "Text\n\n---\nMore")
        XCTAssertFalse(blocks.contains { block in if case .heading = block { true } else { false } })
        XCTAssertTrue(NotePreviewDocument.outline(of: "Text\n\n---\nMore").isEmpty)
    }

    func testUnderlinesInsideACodeBlockMakeNoHeading() {
        let code = "```\nTitle\n=====\n```\nAfter"
        XCTAssertTrue(NotePreviewDocument.outline(of: code).isEmpty)
    }

    func testListItemsAndQuotesAreNotSetextHeadingText() {
        XCTAssertTrue(NotePreviewDocument.outline(of: "- item\n---\n> quote\n---").isEmpty)
    }

    func testHeadingLineLocationFindsSetextAndRepeatedHeadings() {
        let body = "Intro\n\nSub\n---\nBody\n\nSub\n===\nEnd"
        XCTAssertEqual(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: "sub", in: body), 7)
        XCTAssertEqual(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: "sub", occurrence: 1, in: body), 21)
        XCTAssertNil(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: "sub", occurrence: 2, in: body))
        XCTAssertNil(NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: "missing", in: body))
    }
}
