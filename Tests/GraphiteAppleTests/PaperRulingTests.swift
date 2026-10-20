import CoreGraphics
import XCTest
import GraphiteCore
@testable import GraphiteApple

final class PaperRulingTests: XCTestCase {
    private let notabilityRuled = PaperRuling(lineColorHex: "#A3B7D3", lineWidth: 0.5, firstRowFromTop: 36, leftEdge: 15.9375,
                                              rightEdge: 612 - 15.9375, gridColumnAnchor: nil)

    func testASpecificationWithARulingRoundTripsAndOlderDataHasNone() throws {
        let paper = PaperSpecification(template: .ruled, width: 612, height: 803.25, spacing: 36, ruling: notabilityRuled)
        XCTAssertEqual(try JSONDecoder().decode(PaperSpecification.self, from: JSONEncoder().encode(paper)), paper)
        let older = Data(#"{"template":"ruled","width":595.28,"height":841.89,"spacing":18}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(PaperSpecification.self, from: older).ruling)
        let withoutRuling = try JSONEncoder().encode(PaperSpecification(template: .grid))
        XCTAssertFalse(String(decoding: withoutRuling, as: UTF8.self).contains("ruling"), "no ruling key is written for Graphite's own paper")
    }

    func testRuledRowsStartBelowTheTopAndRunBetweenTheEdges() throws {
        let paper = PaperSpecification(template: .ruled, width: 612, height: 803.25, spacing: 36, ruling: notabilityRuled)
        let lines = try Self.lines(of: PDFTemplateGenerator.documentData(paper: paper))
        // Rows at 36, 72, … 792 points from the top: 22 rows.
        XCTAssertEqual(lines.count, 22)
        XCTAssertEqual(lines.first?.start.x ?? 0, 15.9375, accuracy: 0.001)
        XCTAssertEqual(lines.first?.end.x ?? 0, 596.0625, accuracy: 0.001)
        XCTAssertEqual(lines.map(\.start.y).max() ?? 0, 803.25 - 36, accuracy: 0.001)
        XCTAssertTrue(lines.allSatisfy { line in line.start.y == line.end.y })
    }

    func testGridColumnsStandAtTheAnchorAndEverySpacingAtFullHeight() throws {
        var ruling = notabilityRuled
        ruling.rightEdge = 612
        ruling.gridColumnAnchor = 321.94
        let paper = PaperSpecification(template: .grid, width: 612, height: 803.25, spacing: 36, ruling: ruling)
        let columns = try Self.lines(of: PDFTemplateGenerator.documentData(paper: paper)).filter { line in line.start.x == line.end.x }
        let positions = columns.map(\.start.x).sorted()
        XCTAssertEqual(positions.count, 17)
        XCTAssertEqual(positions.first ?? 0, 321.94 - 8 * 36, accuracy: 0.001)
        XCTAssertTrue(positions.contains { position in abs(position - 321.94) < 0.001 })
        XCTAssertTrue(columns.allSatisfy { line in min(line.start.y, line.end.y) == 0 && max(line.start.y, line.end.y) == 803.25 })
    }

    func testARulingThatCannotBeDrawnIsRefused() {
        let cases: [(PaperRuling, PaperRulingError)] = [
            (PaperRuling(lineColorHex: "blue", lineWidth: 0.5, firstRowFromTop: 36, leftEdge: 0, rightEdge: 100, gridColumnAnchor: nil),
             .lineColorNotReadable("blue")),
            (PaperRuling(lineColorHex: "#A3B7D3", lineWidth: 0, firstRowFromTop: 36, leftEdge: 0, rightEdge: 100, gridColumnAnchor: nil),
             .lineWidthNotUsable(0)),
            (PaperRuling(lineColorHex: "#A3B7D3", lineWidth: 0.5, firstRowFromTop: 36, leftEdge: 100, rightEdge: 50, gridColumnAnchor: nil),
             .rowsNotOnThePage(firstRowFromTop: 36, leftEdge: 100, rightEdge: 50)),
            (PaperRuling(lineColorHex: "#A3B7D3", lineWidth: 0.5, firstRowFromTop: 36, leftEdge: 0, rightEdge: 100, gridColumnAnchor: .infinity),
             .gridColumnAnchorNotUsable(.infinity)),
        ]
        for (ruling, expected) in cases {
            XCTAssertThrowsError(try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .grid, ruling: ruling))) { error in
                XCTAssertEqual(error as? PaperRulingError, expected)
            }
        }
    }

    private struct Line {
        let start: CGPoint
        let end: CGPoint
    }

    /// Every straight line the first page's content stream draws, `x y m x y l`, in PDF page space.
    private static func lines(of documentData: Data) throws -> [Line] {
        let provider = try XCTUnwrap(CGDataProvider(data: documentData as CFData))
        let page = try XCTUnwrap(CGPDFDocument(provider)?.page(at: 1))
        var stream: CGPDFStreamRef?
        XCTAssertTrue(CGPDFDictionaryGetStream(try XCTUnwrap(page.dictionary), "Contents", &stream))
        var format = CGPDFDataFormat.raw
        let content = String(decoding: try XCTUnwrap(stream.flatMap { stream in CGPDFStreamCopyData(stream, &format) }) as Data, as: UTF8.self)
        let tokens = content.split(whereSeparator: \.isWhitespace).map(String.init)
        var lines: [Line] = []
        for tokenIndex in tokens.indices where tokens[tokenIndex] == "l" && tokenIndex >= 5 && tokens[tokenIndex - 3] == "m" {
            guard let startX = Double(tokens[tokenIndex - 5]), let startY = Double(tokens[tokenIndex - 4]),
                  let endX = Double(tokens[tokenIndex - 2]), let endY = Double(tokens[tokenIndex - 1]) else { continue }
            lines.append(Line(start: CGPoint(x: startX, y: startY), end: CGPoint(x: endX, y: endY)))
        }
        return lines
    }
}
