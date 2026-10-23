import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingSankeyShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsASankeyDiagram: Error {}

    private func sankey(_ source: String) throws -> ReadingSankeyDiagram {
        guard case .sankey(let diagram) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsASankeyDiagram() }
        return diagram
    }

    func testEachBandsGradientRunsAcrossItsOwnRun() throws {
        let diagram = try sankey("sankey\na,b,3\na,c,1")
        let band = try XCTUnwrap(diagram.shapes.bands.first)
        let link = diagram.layout.links[0]
        XCTAssertEqual(band.gradientStart.x * diagram.layout.size.width, link.startX, accuracy: 0.001)
        XCTAssertEqual(band.gradientEnd.x * diagram.layout.size.width, link.endX, accuracy: 0.001)
        XCTAssertEqual([band.sourceSeriesIndex, band.targetSeriesIndex], [0, 1])
        XCTAssertEqual(band.outline.boundingRect.minX, link.startX, accuracy: 0.001)
    }

    func testBarsArePaintedPerSeriesColor() throws {
        let rows = (1...9).map { number in "hub,n\(number),\(number)" }.joined(separator: "\n")
        let diagram = try sankey("sankey\n" + rows)
        XCTAssertEqual(diagram.shapes.nodeFills.count, 8)
        XCTAssertEqual(ReadingDiagramColors(background: .white, foreground: .black).series.count, diagram.shapes.nodeFills.count)
    }

    func testNamesAndTheTitleAreApartFromTheValues() throws {
        let diagram = try sankey("---\ntitle: Flows\n---\nsankey\na,b,2.5")
        XCTAssertEqual(diagram.shapes.textLines.map(\.text), ["a", "b", "Flows"])
        XCTAssertEqual(diagram.shapes.textLines.last?.isBold, true)
        XCTAssertEqual(diagram.shapes.valueLines.map(\.text), ["2.5", "2.5"])
        let hidden = try sankey("---\nconfig:\n  sankey:\n    showValues: false\n---\nsankey\na,b,2.5")
        XCTAssertTrue(hidden.shapes.valueLines.isEmpty)
    }
}
