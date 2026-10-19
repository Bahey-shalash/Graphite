import XCTest
@testable import GraphiteCore

final class NotePreviewSummaryTests: XCTestCase {
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
        1. First
        > [!tip] Remember
        """
        let summary = NotePreviewSummary.summary(ofPrefix: note, isWholeFile: true)
        XCTAssertEqual(summary.lines, [
            .heading(level: 1, text: "Complex numbers"),
            .paragraph("A number with a real and an imaginary part, see notes."),
            .task(isDone: false, text: "Exercise 1"),
            .task(isDone: true, text: "Exercise 2"),
            .listItem("Definition"),
            .listItem("First"),
            .paragraph("Remember"),
        ])
    }

    func testCodeMathCommentsAndRulesAreLeftOut() {
        let note = "```swift\nlet x = 1\n```\n$$\nx^2\n$$\n%% hidden %%\n---\nVisible"
        XCTAssertEqual(NotePreviewSummary.summary(ofPrefix: note, isWholeFile: true).lines, [.paragraph("Visible")])
    }

    func testFirstEmbeddedPictureIsFoundAndNotShownAsText() {
        let note = "Intro\n![[Lecture.pdf#page=3]]\n![[Board photo.jpg|300]]\n![](second.png)"
        let summary = NotePreviewSummary.summary(ofPrefix: note, isWholeFile: true)
        XCTAssertEqual(summary.firstPictureTarget, "Board photo.jpg")
        XCTAssertEqual(summary.lines, [.paragraph("Intro")])
    }

    func testMarkdownPictureLinkIsDecoded() {
        XCTAssertEqual(NotePreviewSummary.summary(ofPrefix: "![photo](Attachments/My%20photo.png)", isWholeFile: true).firstPictureTarget, "Attachments/My photo.png")
    }

    func testLineCutAtTheEndOfThePrefixIsDropped() {
        let summary = NotePreviewSummary.summary(ofPrefix: "Whole line\nHalf a li", isWholeFile: false)
        XCTAssertEqual(summary.lines, [.paragraph("Whole line")])
    }

    func testFrontmatterStillOpenAtTheCutHidesEverything() {
        let summary = NotePreviewSummary.summary(ofPrefix: "---\ntitle: long\naliases:\n  - a\n", isWholeFile: false)
        XCTAssertEqual(summary.lines, [])
    }

    func testLineCountIsBounded() {
        let note = (1...100).map { number in "Line \(number)" }.joined(separator: "\n")
        XCTAssertEqual(NotePreviewSummary.summary(ofPrefix: note, isWholeFile: true).lines.count, NotePreviewSummary.maximumLineCount)
    }

    func testEmptyNoteHasNoLines() {
        XCTAssertEqual(NotePreviewSummary.summary(ofPrefix: "", isWholeFile: true), NotePreviewSummary(lines: [], firstPictureTarget: nil))
    }
}
