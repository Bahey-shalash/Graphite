import XCTest
@testable import GraphiteCore

final class NotePreviewSummaryTests: XCTestCase {
    /// The blocks with their text as plain characters, to compare without styles.
    private func plainBlocks(of note: String, isWholeFile: Bool = true) -> [String] {
        NotePreviewSummary.summary(ofPrefix: note, isWholeFile: isWholeFile).blocks.map { block in
            switch block {
            case .heading(let level, let text): "h\(level) " + String(text.characters)
            case .paragraph(let text): "p " + String(text.characters)
            case .listItem(let marker, let depth, let text): String(repeating: "  ", count: depth) + marker + " " + String(text.characters)
            case .task(let isDone, let depth, let text): String(repeating: "  ", count: depth) + (isDone ? "[x] " : "[ ] ") + String(text.characters)
            case .quote(let text): "> " + String(text.characters)
            case .callout(let type, let title): "callout \(type): " + String(title.characters)
            case .code(let code): "code " + code
            case .rule: "rule"
            case .picture: "picture"
            }
        }
    }

    func testShowsReadingTextNotSource() {
        let note = """
        ---
        tags: [analysis]
        ---
        # Complex numbers
        A **number** with a [[Real part|real]] and an *imaginary* part, see [notes](https://x.org).
        - [ ] Exercise 1
        - [x] Exercise 2
        - Definition
            - Nested
        1. First
        > [!tip] Remember
        > Quoted ==line==
        ---
        """
        XCTAssertEqual(plainBlocks(of: note), [
            "h1 Complex numbers",
            "p A number with a real and an imaginary part, see notes.",
            "[ ] Exercise 1",
            "[x] Exercise 2",
            "• Definition",
            "  • Nested",
            "1. First",
            "callout tip: Remember",
            "> Quoted line",
            "rule",
        ])
    }

    func testEmphasisIsKeptAsStyle() throws {
        let summary = NotePreviewSummary.summary(ofPrefix: "A **bold** word", isWholeFile: true)
        guard case .paragraph(let text) = try XCTUnwrap(summary.blocks.first) else { return XCTFail("Expected a paragraph") }
        let boldRun = try XCTUnwrap(text.runs.first { run in run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertEqual(String(text[boldRun.range].characters), "bold")
    }

    func testLinksKeepTheirLabelButNotTheirTarget() throws {
        let summary = NotePreviewSummary.summary(ofPrefix: "See [the site](https://example.org)", isWholeFile: true)
        guard case .paragraph(let text) = try XCTUnwrap(summary.blocks.first) else { return XCTFail("Expected a paragraph") }
        XCTAssertEqual(String(text.characters), "See the site")
        XCTAssertTrue(text.runs.allSatisfy { run in run.link == nil })
    }

    func testCodeBlocksShowTheirFirstLinesAndMathIsLeftOut() {
        let note = "```swift\nlet x = 1\nlet y = 2\n```\n$$\nx^2\n$$\n%% hidden %%\nVisible"
        XCTAssertEqual(plainBlocks(of: note), ["code let x = 1\nlet y = 2", "p Visible"])
    }

    func testFirstEmbeddedPictureIsPlacedWhereItSits() {
        let note = "Intro\n![[Lecture.pdf#page=3]]\n![[Board photo.jpg|300]]\n![](second.png)\nAfter"
        let summary = NotePreviewSummary.summary(ofPrefix: note, isWholeFile: true)
        XCTAssertEqual(summary.firstPictureTarget, "Board photo.jpg")
        XCTAssertEqual(plainBlocks(of: note), ["p Intro", "picture", "p After"])
    }

    func testMarkdownPictureLinkIsDecoded() {
        XCTAssertEqual(NotePreviewSummary.summary(ofPrefix: "![photo](Attachments/My%20photo.png)", isWholeFile: true).firstPictureTarget, "Attachments/My photo.png")
    }

    func testLineCutAtTheEndOfThePrefixIsDropped() {
        XCTAssertEqual(plainBlocks(of: "Whole line\nHalf a li", isWholeFile: false), ["p Whole line"])
    }

    func testFrontmatterStillOpenAtTheCutHidesEverything() {
        XCTAssertEqual(plainBlocks(of: "---\ntitle: long\naliases:\n  - a\n", isWholeFile: false), [])
    }

    func testBlockCountIsBounded() {
        let note = (1...100).map { number in "Line \(number)" }.joined(separator: "\n")
        XCTAssertEqual(NotePreviewSummary.summary(ofPrefix: note, isWholeFile: true).blocks.count, NotePreviewSummary.maximumBlockCount)
    }

    func testEmptyNoteHasNoBlocks() {
        XCTAssertEqual(NotePreviewSummary.summary(ofPrefix: "", isWholeFile: true), NotePreviewSummary(blocks: [], firstPictureTarget: nil))
    }
}
