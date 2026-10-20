import CoreGraphics
import Foundation
import XCTest
@testable import GraphiteCore

/// Notability's ruled and grid paper and its line shapes, as the page planner plans them on letter paper 572 units wide.
final class NotabilityPaperAndShapePlannerTests: XCTestCase {
    private static let accuracy = 1e-9
    private static let pageWidthInUnits = 572.0
    private static let pointsPerUnit = 612.0 / 572.0
    private static let leftInset = 15.9375
    private static let inkColor = NotebookImportColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
    private static let white = NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let rulingColor = NotebookImportColor(red: 0xA3 / 255.0, green: 0xB7 / 255.0, blue: 0xD3 / 255.0, alpha: 1)

    // MARK: Paper

    func testRuledPaperHasRowsEveryThirtySixPointsBetweenTheInsets() throws {
        let plan = try Self.plan(lineStyle: .lines(parameters: ["false", "false", "0.5"]))
        guard case .ruledPaper(let ruledPaper) = plan.background else { return XCTFail("\(plan.background)") }
        XCTAssertEqual(ruledPaper.paperColor, Self.white)
        XCTAssertEqual(ruledPaper.lineColor, Self.rulingColor)
        XCTAssertEqual(ruledPaper.lineWidth, 0.5)
        XCTAssertEqual(ruledPaper.spacing, 36, accuracy: Self.accuracy)
        XCTAssertEqual(ruledPaper.firstRowFromTop, 36, accuracy: Self.accuracy)
        XCTAssertEqual(ruledPaper.leftEdge, Self.leftInset)
        XCTAssertEqual(ruledPaper.rightEdge, 612 - Self.leftInset, accuracy: Self.accuracy)
        XCTAssertNil(ruledPaper.gridColumnAnchor)
        XCTAssertEqual(plan.report, [])
    }

    func testGridPaperRunsToTheRightEdgeWithAColumnAtTheMiddleOfTheDocument() throws {
        let plan = try Self.plan(lineStyle: .grid(parameters: ["false", "true", "0.5"]))
        guard case .ruledPaper(let ruledPaper) = plan.background else { return XCTFail("\(plan.background)") }
        XCTAssertEqual(ruledPaper.lineWidth, 0.4)
        XCTAssertEqual(ruledPaper.spacing, 36, accuracy: Self.accuracy)
        XCTAssertEqual(ruledPaper.rightEdge, 612, accuracy: Self.accuracy)
        XCTAssertEqual(ruledPaper.gridColumnAnchor ?? 0, 321.9375, accuracy: Self.accuracy)
        XCTAssertEqual(plan.report, [])
    }

    func testAnImportedPDFPageIsTheBackgroundEvenOnRuledPaper() throws {
        let importedPage = NotabilityImportedPDFPage(documentPageNumber: 1, pdfFile: .fixture("PDFs/Document.pdf"), pdfPageNumber: 2,
                                                     isBookmarked: false)
        let plan = try Self.plan(lineStyle: .lines(parameters: []), importedPDFPages: [importedPage])
        XCTAssertEqual(plan.background, .pdfPage(ImportedSourceFile(path: .fixture("PDFs/Document.pdf")), pageNumber: 2))
    }

    func testOnlyAPageMadeFromABookmarkedPDFPageIsBookmarked() throws {
        let importedPages = [NotabilityImportedPDFPage(documentPageNumber: 1, pdfFile: .fixture("PDFs/Document.pdf"), pdfPageNumber: 1, isBookmarked: true),
                             NotabilityImportedPDFPage(documentPageNumber: 2, pdfFile: .fixture("PDFs/Document.pdf"), pdfPageNumber: 2, isBookmarked: false)]
        XCTAssertTrue(try Self.plan(importedPDFPages: importedPages).isBookmarked)
        let secondPage = NotabilityPage(pageNumber: 2, topInUnits: 0, curves: [], shapes: [], pictures: [])
        XCTAssertFalse(try Self.plan(importedPDFPages: importedPages, page: secondPage).isBookmarked)
    }

    // MARK: Shapes

    func testALineShapeIsMonolineInkAtItsWidthAndIsReported() throws {
        let shape = Self.shape(drawnBeforeCurveIndex: 0, start: CGPoint(x: 0, y: 10), end: CGPoint(x: 10, y: 10), dashPattern: [4, 2])
        let plan = try Self.plan(page: Self.page(curves: [], shapes: [shape]))
        let stroke = try XCTUnwrap(plan.strokes.first)
        XCTAssertEqual(plan.strokes.count, 1)
        XCTAssertEqual(stroke.ink, .monoline)
        XCTAssertEqual(stroke.color, Self.inkColor)
        XCTAssertEqual(stroke.samples.first?.location.x ?? 0, Self.leftInset, accuracy: Self.accuracy)
        XCTAssertEqual(stroke.samples.last?.location.x ?? 0, Self.leftInset + 10 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertTrue(stroke.samples.allSatisfy { sample in abs(sample.width - 3 * Self.pointsPerUnit) < Self.accuracy })
        XCTAssertGreaterThan(stroke.samples.count, 2, "a straight side gets points along it")
        XCTAssertEqual(plan.report, [.shapesDrawnAsInk(count: 1), .dashesNotKept(strokeCount: 1)])
    }

    func testACurvedShapePassesNearItsControlPoint() throws {
        let shape = Self.shape(drawnBeforeCurveIndex: 0, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 100, y: 100),
                               control: CGPoint(x: 50, y: 0))
        let stroke = try XCTUnwrap(try Self.plan(page: Self.page(curves: [], shapes: [shape])).strokes.first)
        // The quadratic's middle is halfway between the control point and the chord: y = 50 units.
        let highest = stroke.samples.map(\.location.y).min() ?? 0
        XCTAssertEqual(highest, 50 * Self.pointsPerUnit, accuracy: 0.2)
    }

    func testShapesAreDrawnInTheirPlaceAmongTheCurves() throws {
        let curves = [Self.curve(index: 4, x: 1), Self.curve(index: 7, x: 2)]
        let shapes = [Self.shape(drawnBeforeCurveIndex: 9, start: CGPoint(x: 30, y: 0), end: CGPoint(x: 30, y: 1)),
                      Self.shape(drawnBeforeCurveIndex: 5, start: CGPoint(x: 20, y: 0), end: CGPoint(x: 20, y: 1)),
                      Self.shape(drawnBeforeCurveIndex: 0, start: CGPoint(x: 10, y: 0), end: CGPoint(x: 10, y: 1))]
        let plan = try Self.plan(page: Self.page(curves: curves, shapes: shapes))
        let firstXs = plan.strokes.map { stroke in ((stroke.samples.first?.location.x ?? 0) - Self.leftInset) / Self.pointsPerUnit }
        XCTAssertEqual(firstXs.map { x in x.rounded() }, [10, 1, 20, 2, 30])
        XCTAssertEqual(plan.report, [.shapesDrawnAsInk(count: 3)])
    }

    func testAShapeOfAnUnknownKindIsCountedAsLeftOut() throws {
        let shape = NotabilityShape(kind: .unknown("ellipse"), drawnBeforeCurveIndex: 0, start: .zero, end: CGPoint(x: 10, y: 10),
                                    quadraticControlPoint: nil, width: 2, color: Self.inkColor, dashPattern: nil)
        let plan = try Self.plan(page: Self.page(curves: [], shapes: [shape]))
        XCTAssertEqual(plan.strokes, [])
        XCTAssertEqual(plan.report, [.elementsNotYetConverted(kind: .shape, count: 1)])
    }

    func testAShapeIsCutAtThePageBottom() throws {
        let pageHeightInUnits = 803.25 / Self.pointsPerUnit
        let shape = Self.shape(drawnBeforeCurveIndex: 0, start: CGPoint(x: 10, y: pageHeightInUnits - 20),
                               end: CGPoint(x: 10, y: pageHeightInUnits + 200))
        let stroke = try XCTUnwrap(try Self.plan(page: Self.page(curves: [], shapes: [shape])).strokes.first)
        let lowest = stroke.samples.map(\.location.y).max() ?? 0
        XCTAssertLessThanOrEqual(lowest, 803.25 + 2 * 3 * Self.pointsPerUnit + ShapeOutlineSampling.maximumStraightSpacing)
    }

    // MARK: Builders

    private static func plan(lineStyle: NotabilityPaperLineStyle? = .noLines, importedPDFPages: [NotabilityImportedPDFPage] = [],
                             page: NotabilityPage = page(curves: [], shapes: [])) throws -> ImportedPagePlan {
        let paper = NotabilityPaper(identifier: .legacyWhite, size: .letter, orientation: .portrait,
                                    sizingBehaviour: .lockedWidth(width: pageWidthInUnits, device: "iPad"), lineStyle: lineStyle)
        let note = NotabilityNote(name: nil, sessionFormatVersion: 9, applicationVersion: nil, paper: paper,
                                  reflowState: .locked(pageWidth: pageWidthInUnits, device: nil),
                                  pageGeometry: NotabilityPageGeometry(pageWidthInUnits: pageWidthInUnits, paper: paper), shapes: [], pictures: [],
                                  typedText: NotabilityTypedText(text: "", runs: []), importedPDFPages: importedPDFPages, recordings: [],
                                  playbackEvents: [])
        guard case .planned(let plan) = NotabilityPagePlanner.plan(page, note: note) else { return try XCTUnwrap(nil as ImportedPagePlan?, "the page was left out") }
        return plan
    }

    private static func plan(page: NotabilityPage) throws -> ImportedPagePlan {
        try plan(lineStyle: .noLines, page: page)
    }

    private static func page(curves: [NotabilityCurve], shapes: [NotabilityShape]) -> NotabilityPage {
        NotabilityPage(pageNumber: 1, topInUnits: 0, curves: curves, shapes: shapes, pictures: [])
    }

    private static func shape(drawnBeforeCurveIndex: Int, start: CGPoint, end: CGPoint, control: CGPoint? = nil,
                              dashPattern: [Double]? = nil) -> NotabilityShape {
        NotabilityShape(kind: .line, drawnBeforeCurveIndex: drawnBeforeCurveIndex, start: start, end: end, quadraticControlPoint: control,
                        width: 3, color: inkColor, dashPattern: dashPattern)
    }

    /// A short straight curve at `x` units.
    private static func curve(index: Int, x: Double) -> NotabilityCurve {
        let points = [CGPoint(x: x, y: 0), CGPoint(x: x, y: 1), CGPoint(x: x, y: 2), CGPoint(x: x, y: 3)]
        let knot = NotabilityKnot(widthFactor: 1, force: 1, altitudeAngle: nil, azimuthUnitVector: nil)
        return NotabilityCurve(index: index, uuid: UUID(), style: .pen, width: 1, color: inkColor, points: points, knots: [knot, knot])
    }
}
