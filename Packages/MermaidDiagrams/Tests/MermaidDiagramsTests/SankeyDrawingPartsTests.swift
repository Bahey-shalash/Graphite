import XCTest
@testable import MermaidDiagrams

final class SankeyDrawingPartsTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func parts(_ source: String) throws -> (SankeyLayout, SankeyDrawingParts) {
        let layout = try SankeyLayoutEngine.layout(try SankeyReading.diagram(source), typography: typography)
        return (layout, SankeyDrawingParts(layout: layout))
    }

    func testBarsAreGroupedBySeriesColorAndTheColorsComeRoundAgain() throws {
        let rows = (1...9).map { number in "hub,n\(number),\(number)" }.joined(separator: "\n")
        let (layout, parts) = try parts("sankey\n" + rows)
        XCTAssertEqual(parts.nodeFills.count, 8)
        let ninthTarget = layout.nodes[9].frame
        XCTAssertTrue(parts.nodeFills[1].contains(CGPoint(x: ninthTarget.midX, y: ninthTarget.midY)), "The tenth node takes the second color")
    }

    func testABandRunsBetweenItsBarsWithItsThickness() throws {
        let (layout, parts) = try parts("sankey\na,b,30\na,c,10")
        let band = try XCTUnwrap(parts.bands.first)
        let bounds = band.outline.boundingBoxOfPath
        XCTAssertEqual(bounds.minX, layout.nodes[0].frame.maxX, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, layout.nodes[1].frame.minX, accuracy: 0.001)
        XCTAssertTrue(band.outline.contains(CGPoint(x: bounds.minX + 1, y: layout.links[0].sourceY)))
        XCTAssertFalse(band.outline.contains(CGPoint(x: bounds.minX + 1, y: layout.links[0].sourceY + layout.links[0].halfThickness + 1)))
        XCTAssertEqual([band.sourceSeriesIndex, band.targetSeriesIndex], [0, 1])
    }

    func testNamesAndValuesAreApartForTheirColors() throws {
        let (_, parts) = try parts("---\ntitle: Flows\n---\nsankey\na,b,1.5")
        XCTAssertEqual(parts.names.map(\.lines), [["a"], ["b"]])
        XCTAssertEqual(parts.values.map(\.lines), [["1.5"], ["1.5"]])
        XCTAssertEqual(parts.title?.lines, ["Flows"])
    }
}
