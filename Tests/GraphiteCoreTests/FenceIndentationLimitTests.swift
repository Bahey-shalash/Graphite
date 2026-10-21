import XCTest
@testable import GraphiteCore

/// A fence line indented four or more columns past its container (column 0, or the content
/// of the list item holding it) is no fence, for every reader that follows fences line by
/// line, as for the index and the editor (`BUG-MDCORE-03`, decision 11 (b)).
final class FenceIndentationLimitTests: XCTestCase {
    /// Indented code followed by a heading: the indented backticks open nothing.
    private let headingAfterIndentedBackticks = "    ```\n# Heading\nbody"

    func testFoldingFoldsAHeadingAfterBackticksIndentedFourColumns() {
        let regions = NoteFolding.regions(in: headingAfterIndentedBackticks)
        XCTAssertTrue(regions.contains { region in region.kind == .heading(level: 1) })
    }

    func testFoldingFoldsAHeadingAfterBackticksFourColumnsPastTheirListItemContent() {
        let regions = NoteFolding.regions(in: "- item\n\n      ```\n# Heading\nbody")
        XCTAssertTrue(regions.contains { region in region.kind == .heading(level: 1) })
    }

    func testFoldingKeepsAFenceThreeColumnsPastItsListItemContentAsCode() {
        let regions = NoteFolding.regions(in: "- item\n     ```\n# Not a heading\nbody\n     ```")
        XCTAssertFalse(regions.contains { region in region.kind == .heading(level: 1) })
    }

    func testFootnoteReferenceAfterBackticksIndentedFourColumnsIsAReference() {
        let references = Footnotes.parse("    ```\nA claim[^source].\n\n[^source]: The book.").references
        XCTAssertEqual(references.map(\.label), ["source"])
    }

    func testReturnContinuesAListAfterBackticksIndentedFourColumns() {
        let text = "    ```\n- item" as NSString
        XCTAssertNotNil(MarkdownEditing.continuingList(in: text, selection: NSRange(location: text.length, length: 0), indentUnit: "\t"))
    }

    func testOutlineListsAHeadingAfterBackticksIndentedFourColumns() {
        XCTAssertEqual(NotePreviewDocument.outline(of: headingAfterIndentedBackticks).map(\.text), ["Heading"])
    }

    func testReadingViewDrawsATaskAfterBackticksIndentedFourColumnsAsACheckbox() {
        let marked = ObsidianInlineMarkup.markingTasks(in: "    ```\n- [ ] task")
        XCTAssertFalse(marked.contains("[ ]"))
    }

    func testReadingViewKeepsSoftLineBreaksAfterBackticksIndentedFourColumnsAsBreaks() {
        let prepared = ObsidianPreviewText.applyingSoftLineBreaks(to: "    ```\nfirst\nsecond")
        XCTAssertTrue(prepared.contains("first  \n"))
    }

    func testSearchSplitsSectionsAtAHeadingAfterBackticksIndentedFourColumns() {
        XCTAssertEqual(SearchContentParts.sections(of: "intro\n    ```\n# Heading\nbody").count, 2)
    }

    func testLinkCompletionSuggestsNotesAfterBackticksIndentedFourColumns() {
        let text = "    ```\n[[No" as NSString
        XCTAssertNotNil(LinkCompletion.context(in: text, cursor: text.length))
    }

    func testColorsAfterBackticksIndentedFourColumnsContinuingAParagraphAreRead() {
        XCTAssertEqual(TextColorMarkup.sections(in: "Paragraph\n    ```\n~={#ff0000}red=~" as NSString).count, 1)
    }

    func testUnlinkedMentionsAfterBackticksIndentedFourColumnsAreFound() {
        XCTAssertEqual(Mentions.unlinkedMentions(of: ["Alpha"], in: "    ```\nAlpha here").count, 1)
    }
}
