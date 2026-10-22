import XCTest
@testable import MermaidDiagrams

final class DiagramTextBlockTests: XCTestCase {
    private let measurer = UniformWidthTextMeasurer()

    func testALineWiderThanTheLimitWrapsAtSpaces() {
        let block = DiagramTextBlock(label: DiagramLabel("one two three four"), measurer: measurer, maximumWidth: 79)
        XCTAssertEqual(block.lines, ["one two", "three", "four"])
        XCTAssertEqual(block.lineWidths, [56, 40, 32])
        XCTAssertEqual(block.size, CGSize(width: 56, height: 72))
    }

    func testAWordWiderThanTheLimitStaysWhole() {
        let block = DiagramTextBlock(label: DiagramLabel("supercalifragilistic"), measurer: measurer, maximumWidth: 80)
        XCTAssertEqual(block.lines, ["supercalifragilistic"])
    }

    func testBrokenLinesStayBrokenAndAnEmptyLabelHasNoLines() {
        XCTAssertEqual(DiagramTextBlock(label: DiagramLabel(lines: ["a", "b"]), measurer: measurer, maximumWidth: 200).lines, ["a", "b"])
        XCTAssertTrue(DiagramTextBlock(label: DiagramLabel(""), measurer: measurer, maximumWidth: 200).lines.isEmpty)
    }
}
