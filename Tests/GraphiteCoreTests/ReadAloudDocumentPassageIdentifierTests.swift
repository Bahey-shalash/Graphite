import XCTest
@testable import GraphiteCore

/// The transcript and the section navigation use a passage's `id` as its index in
/// `document.passages`, so every way of making a document numbers its passages from 0 in order.
final class ReadAloudDocumentPassageIdentifierTests: XCTestCase {
    private func assertIdentifiersAreIndices(_ document: ReadAloudDocument, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(document.passages.isEmpty, label, file: file, line: line)
        XCTAssertEqual(document.passages.map(\.id), Array(document.passages.indices), label, file: file, line: line)
    }

    private let longSentences = Array(repeating: "Café 🧠 sentence.", count: 600).joined(separator: " ")

    func testMarkdownNumbersHeadingsParagraphsListsTablesAndCalloutsInOrder() throws {
        let note = """
        ---
        title: Fixture
        ---
        # Heading

        First paragraph with $x^2$ and `code`.

        - one
        - two

        | Gate | Inputs |
        | --- | --- |
        | NAND | 2 |
        | NOR | 2 |

        > [!note] Remember
        > Body of the callout.

        Last paragraph.
        """
        assertIdentifiersAreIndices(try ReadAloudDocument.markdown(note), "markdown with every block kind")
    }

    func testMarkdownNumbersThePiecesOfAParagraphLongerThanOnePassage() throws {
        let document = try ReadAloudDocument.markdown("# Title\n\n" + longSentences + "\n\nAfter it.")

        XCTAssertGreaterThan(document.passages.count, 3)
        assertIdentifiersAreIndices(document, "markdown with a long paragraph between others")
    }

    func testMarkdownOfOnlyASelectionStillNumbersFromZero() throws {
        let note = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let range = (note as NSString).range(of: "Second paragraph.")

        let document = try ReadAloudDocument.markdown(note, selectedRange: range)

        XCTAssertEqual(document.passages.map(\.id), [0])
    }

    func testPlainTextNumbersTheSplitPassagesInOrder() throws {
        let document = try ReadAloudDocument.plainText(longSentences)

        XCTAssertGreaterThan(document.passages.count, 1)
        assertIdentifiersAreIndices(document, "plain text longer than one passage")
    }

    func testPageTextNumbersSlideLinesBulletsAndLongUnitsInOrder() throws {
        let slide = "Static logic\n• Pass-transistor logic\n• nMOS logic\n\nA closing sentence that ends here.\n" + longSentences + "\nL05 Static logic v1.0\n2"

        let document = try ReadAloudDocument.pageText(slide, pageLabels: ["2"])

        XCTAssertGreaterThan(document.passages.count, 4)
        assertIdentifiersAreIndices(document, "PDF page text with bullets, a footer and a long unit")
    }
}
