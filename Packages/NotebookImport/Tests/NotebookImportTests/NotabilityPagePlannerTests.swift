import CoreGraphics
import Foundation
import XCTest
@testable import NotebookImport

/// Planning Notability pages into Graphite pages, on small notes built from the reader's value types.
final class NotabilityPagePlannerTests: XCTestCase {
    private static let accuracy = 1e-9
    private static let pageWidthInUnits = 572.0
    private static let pointsPerUnit = 612.0 / 572.0
    private static let leftInset = 15.9375
    private static let letterPageSize = CGSize(width: 612, height: 803.25)
    private static let inkColor = NotebookImportColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
    private static let white = NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let black = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1)

    // MARK: Page size and geometry

    func testAnUnknownPageWidthLeavesThePageOut() {
        let note = Self.note(pageWidthInUnits: nil)
        let outcome = NotabilityPagePlanner.plan(Self.page(number: 3, curves: []), note: note)
        XCTAssertEqual(outcome, .leftOut(sourcePageNumber: 3, report: [.pageGeometryUnknown]))
    }

    func testAnUnknownPaperSizeLeavesThePageOut() {
        let note = Self.note(paper: Self.paper(size: .unknown("legal")))
        let outcome = NotabilityPagePlanner.plan(Self.page(number: 2, curves: []), note: note)
        XCTAssertEqual(outcome, .leftOut(sourcePageNumber: 2, report: [.pageGeometryUnknown]))
    }

    func testThePageHasTheExportSizeOfTheLetterPaper() throws {
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: []), note: Self.note())))
        XCTAssertEqual(plan.sizeInPoints, Self.letterPageSize)
        XCTAssertEqual(plan.sourcePageNumber, 1)
        XCTAssertEqual(plan.strokes, [])
        XCTAssertEqual(plan.report, [])
    }

    func testPointsFollowTheInsetTheScaleAndThePageTop() throws {
        let points = Self.straightChain(through: [CGPoint(x: 10, y: 200), CGPoint(x: 40, y: 200)])
        let curve = Self.curve(width: 2, points: points, knots: [Self.knot(widthFactor: 1), Self.knot(widthFactor: 3)])
        let page = Self.page(number: 2, top: 100, curves: [curve])
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(page, note: Self.note())))
        let planned = try XCTUnwrap(plan.strokes.first)
        XCTAssertEqual(plan.strokes.count, 1)
        XCTAssertEqual(planned.ink, .pen)
        XCTAssertEqual(planned.color, Self.inkColor)
        XCTAssertNil(planned.outline)
        XCTAssertEqual(planned.samples.count, 2)
        Self.assertPoint(planned.samples[0].location, x: Self.leftInset + 10 * Self.pointsPerUnit, y: 100 * Self.pointsPerUnit)
        Self.assertPoint(planned.samples[1].location, x: Self.leftInset + 40 * Self.pointsPerUnit, y: 100 * Self.pointsPerUnit)
        XCTAssertEqual(planned.samples[0].width, 2 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.samples[1].width, 6 * Self.pointsPerUnit, accuracy: Self.accuracy)
    }

    // MARK: Per-knot values

    func testWidthForceAltitudeAndAzimuthAreInterpolatedLinearlyBetweenKnots() throws {
        let points = [CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 300), CGPoint(x: 200, y: 300), CGPoint(x: 200, y: 100)]
        let knots = [
            Self.knot(widthFactor: 1, force: 0.2, altitude: 0.5, azimuth: NotabilityAzimuthVector(horizontal: 1, vertical: 0)),
            Self.knot(widthFactor: 3, force: 0.8, altitude: 1.0, azimuth: NotabilityAzimuthVector(horizontal: 0, vertical: 1))
        ]
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(
            Self.page(number: 1, curves: [Self.curve(width: 2, points: points, knots: knots)]), note: Self.note())))
        let samples = try XCTUnwrap(plan.strokes.first).samples
        let pagePoints = points.map { point in CGPoint(x: Self.leftInset + point.x * Self.pointsPerUnit, y: point.y * Self.pointsPerUnit) }
        let parameters = BezierFlattening.cubicParameters(start: pagePoints[0], control1: pagePoints[1], control2: pagePoints[2],
                                                          end: pagePoints[3], tolerance: NotabilityCurveSampling.flatteningToleranceInPoints)
        XCTAssertGreaterThan(parameters.count, 1)
        XCTAssertEqual(samples.count, parameters.count + 1)
        XCTAssertEqual(samples[0].width, 2 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(samples[0].force ?? -1, 0.2, accuracy: Self.accuracy)
        XCTAssertEqual(samples[0].altitudeRadians ?? -1, 0.5, accuracy: Self.accuracy)
        XCTAssertEqual(samples[0].azimuthRadians ?? -1, 0, accuracy: Self.accuracy)
        for (sampleIndex, parameter) in parameters.enumerated() {
            let sample = samples[sampleIndex + 1]
            XCTAssertEqual(sample.width, 2 * Self.pointsPerUnit * (1 + 2 * parameter), accuracy: Self.accuracy)
            XCTAssertEqual(sample.force ?? -1, 0.2 + 0.6 * parameter, accuracy: Self.accuracy)
            XCTAssertEqual(sample.altitudeRadians ?? -1, 0.5 + 0.5 * parameter, accuracy: Self.accuracy)
            XCTAssertEqual(sample.azimuthRadians ?? -1, Double.pi / 2 * parameter, accuracy: Self.accuracy)
        }
        let lastSample = try XCTUnwrap(samples.last)
        XCTAssertEqual(lastSample.width, 6 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(lastSample.azimuthRadians ?? -1, Double.pi / 2, accuracy: Self.accuracy)
    }

    func testAKnotWithoutAltitudeOrAzimuthKeepsItsForceAndGivesNoAngles() throws {
        let points = Self.straightChain(through: [CGPoint(x: 10, y: 50), CGPoint(x: 40, y: 50)])
        let curve = Self.curve(width: 1, points: points, knots: [Self.knot(force: 0.4), Self.knot(force: 0.6)])
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: [curve]), note: Self.note())))
        let samples = try XCTUnwrap(plan.strokes.first).samples
        XCTAssertEqual(samples.map { sample in sample.force }, [0.4, 0.6])
        XCTAssertEqual(samples.map { sample in sample.altitudeRadians }, [nil, nil])
        XCTAssertEqual(samples.map { sample in sample.azimuthRadians }, [nil, nil])
    }

    func testTheAzimuthIsTheAngleOfTheKnotsVectorWithTheVerticalComponentSecond() throws {
        let points = Self.straightChain(through: [CGPoint(x: 10, y: 50), CGPoint(x: 40, y: 50)])
        let leftward = NotabilityAzimuthVector(horizontal: -1, vertical: 0)
        let upward = NotabilityAzimuthVector(horizontal: 0, vertical: -1)
        let curve = Self.curve(width: 1, points: points, knots: [Self.knot(azimuth: leftward), Self.knot(azimuth: upward)])
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: [curve]), note: Self.note())))
        let samples = try XCTUnwrap(plan.strokes.first).samples
        XCTAssertEqual(samples[0].azimuthRadians ?? 0, Double.pi, accuracy: Self.accuracy)
        let lastAzimuth = try XCTUnwrap(samples[1].azimuthRadians)
        XCTAssertEqual(remainder(lastAzimuth - -Double.pi / 2, 2 * Double.pi), 0, accuracy: Self.accuracy)
    }

    // MARK: Cutting at the page edges

    func testACurveCrossingThePageBottomIsCutKeepingOneSamplePastTheEdge() throws {
        let knotPositions = [700.0, 740, 790, 850].map { verticalUnits in CGPoint(x: 50, y: verticalUnits) }
        let curve = Self.curve(width: 1, points: Self.straightChain(through: knotPositions), knots: knotPositions.map { _ in Self.knot() })
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: [curve]), note: Self.note())))
        XCTAssertEqual(plan.strokes.count, 1)
        let samples = try XCTUnwrap(plan.strokes.first).samples
        XCTAssertEqual(samples.map { sample in sample.location.y }, [700, 740, 790].map { verticalUnits in verticalUnits * Self.pointsPerUnit })
        XCTAssertGreaterThan(try XCTUnwrap(samples.last).location.y, Self.letterPageSize.height)
    }

    func testACurveThatLeavesAndReentersThePageBecomesTwoStrokes() throws {
        let knotPositions = [700.0, 740, 790, 700].map { verticalUnits in CGPoint(x: 50, y: verticalUnits) }
        let curve = Self.curve(width: 1, points: Self.straightChain(through: knotPositions), knots: knotPositions.map { _ in Self.knot() })
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: [curve]), note: Self.note())))
        XCTAssertEqual(plan.strokes.count, 2)
        XCTAssertEqual(plan.strokes[0].samples.map { sample in sample.location.y },
                       [700, 740, 790].map { verticalUnits in verticalUnits * Self.pointsPerUnit })
        XCTAssertEqual(plan.strokes[1].samples.map { sample in sample.location.y },
                       [790, 700].map { verticalUnits in verticalUnits * Self.pointsPerUnit })
    }

    func testACurveEnteringThePageFromAboveKeepsOneSamplePastTheTopEdge() throws {
        let knotPositions = [-200.0, -100, 50, 100].map { verticalUnits in CGPoint(x: 50, y: verticalUnits) }
        let curve = Self.curve(width: 1, points: Self.straightChain(through: knotPositions), knots: knotPositions.map { _ in Self.knot() })
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: [curve]), note: Self.note())))
        XCTAssertEqual(plan.strokes.count, 1)
        XCTAssertEqual(try XCTUnwrap(plan.strokes.first).samples.map { sample in sample.location.y },
                       [-100, 50, 100].map { verticalUnits in verticalUnits * Self.pointsPerUnit })
    }

    func testACurveEntirelyOffThePageGivesNoStroke() throws {
        let knotPositions = [2000.0, 2100].map { verticalUnits in CGPoint(x: 50, y: verticalUnits) }
        let curve = Self.curve(width: 1, points: Self.straightChain(through: knotPositions), knots: knotPositions.map { _ in Self.knot() })
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: [curve]), note: Self.note())))
        XCTAssertEqual(plan.strokes, [])
    }

    // MARK: Ink styles

    func testAHighlighterCurveHasHighlighterInkAndIsCounted() throws {
        let points = Self.straightChain(through: [CGPoint(x: 10, y: 50), CGPoint(x: 40, y: 50)])
        let highlighter = Self.curve(style: .highlighter, width: 10, points: points, knots: [Self.knot(), Self.knot()])
        let pen = Self.curve(style: .pen, width: 1, points: points, knots: [Self.knot(), Self.knot()])
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: [highlighter, pen]), note: Self.note())))
        XCTAssertEqual(plan.strokes.map { stroke in stroke.ink }, [.highlighter, .pen])
        XCTAssertEqual(plan.report, [.highlighterNotMultiplied(strokeCount: 1)])
    }

    func testAnUnknownCurveStyleIsDrawnAsPenAndReported() throws {
        let points = Self.straightChain(through: [CGPoint(x: 10, y: 50), CGPoint(x: 40, y: 50)])
        let curve = Self.curve(style: .unknown(9), width: 1, points: points, knots: [Self.knot(), Self.knot()])
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: [curve, curve]), note: Self.note())))
        XCTAssertEqual(plan.strokes.map { stroke in stroke.ink }, [.pen, .pen])
        XCTAssertEqual(plan.report, [.notabilityReadingIssue(.curveStyleUnknown(rawStyle: 9))])
    }

    // MARK: Background

    func testAnImportedPdfPageForThePageNumberIsThePageBackground() throws {
        let importedPage = NotabilityImportedPDFPage(documentPageNumber: 2, pdfFile: .fixture("PDFs/Lecture.pdf"), pdfPageNumber: 5, isBookmarked: false)
        let note = Self.note(importedPDFPages: [importedPage])
        let second = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 2, curves: []), note: note)))
        XCTAssertEqual(second.background, .pdfPage(ImportedSourceFile(path: .fixture("PDFs/Lecture.pdf")), pageNumber: 5))
        let first = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: []), note: note)))
        XCTAssertEqual(first.background, .plainColor(Self.white))
    }

    func testAnImportedPdfPageWithoutAPdfPageNumberShowsThePdfsFirstPage() throws {
        let importedPage = NotabilityImportedPDFPage(documentPageNumber: 1, pdfFile: .fixture("PDFs/Lecture.pdf"), pdfPageNumber: nil, isBookmarked: false)
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: []),
                                                                             note: Self.note(importedPDFPages: [importedPage]))))
        XCTAssertEqual(plan.background, .pdfPage(ImportedSourceFile(path: .fixture("PDFs/Lecture.pdf")), pageNumber: 1))
    }

    func testLegacyBlackPaperIsBlackAndOtherPaperIsWhite() throws {
        let blackPlan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(
            Self.page(number: 1, curves: []), note: Self.note(paper: Self.paper(identifier: .legacyBlack)))))
        XCTAssertEqual(blackPlan.background, .plainColor(Self.black))
        let whitePlan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(
            Self.page(number: 1, curves: []), note: Self.note(paper: Self.paper(identifier: .legacyWhite)))))
        XCTAssertEqual(whitePlan.background, .plainColor(Self.white))
    }

    func testAnUnknownLineStyleReportsThatItsRulingIsNotDrawn() throws {
        let note = Self.note(paper: Self.paper(lineStyle: .unknown("Dots")))
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: []), note: note)))
        XCTAssertEqual(plan.report, [.paperRulingNotDrawn])
        XCTAssertEqual(plan.background, .plainColor(Self.white))
    }

    func testPaperWithoutLinesOrWithAnAbsentLineStyleReportsNoRuling() throws {
        for lineStyle in [NotabilityPaperLineStyle.noLines, nil] {
            let note = Self.note(paper: Self.paper(lineStyle: lineStyle))
            let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: []), note: note)))
            XCTAssertEqual(plan.report, [])
        }
    }

    // MARK: Elements left out

    func testShapesWithoutAWidthAreCountedAndPicturesArePlanned() throws {
        let shape = NotabilityShape(kind: .line, drawnBeforeCurveIndex: 0, start: .zero, end: CGPoint(x: 10, y: 10), quadraticControlPoint: nil,
                                    width: nil, color: Self.inkColor, dashPattern: nil)
        let picture = NotabilityPicture(file: .fixture("Images/Image 1.jpg"), origin: .zero, size: CGSize(width: 10, height: 10),
                                        rotationRadiansClockwise: 0, zIndex: 0, cropRectangle: CGRect(x: 0, y: 0, width: 10, height: 10),
                                        isFlippedHorizontally: false, isFlippedVertically: false)
        let note = Self.note(typedText: NotabilityTypedText(text: "Some words", runs: []))
        let page = Self.page(number: 1, curves: [], shapes: [shape, shape], pictures: [picture])
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(page, note: note)))
        XCTAssertEqual(plan.report, [.elementsNotYetConverted(kind: .shape, count: 2)])
        XCTAssertEqual(plan.pictures.count, 1)
    }

    func testTypedTextStartsOnlyOnTheFirstPageAndNeverWhenEmpty() throws {
        let typed = Self.note(typedText: NotabilityTypedText(text: "Some words", runs: []))
        let first = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: []), note: typed)))
        XCTAssertEqual(first.flowingText?.runs.map(\.text), ["Some words"])
        XCTAssertEqual(first.report, [])
        let later = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 2, curves: []), note: typed)))
        XCTAssertNil(later.flowingText)
        XCTAssertEqual(later.report, [])
        let empty = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(Self.page(number: 1, curves: []), note: Self.note())))
        XCTAssertNil(empty.flowingText)
        XCTAssertEqual(empty.report, [])
    }

    // MARK: Builders

    private static func plannedPlan(_ outcome: ImportedPageOutcome) -> ImportedPagePlan? {
        guard case .planned(let plan) = outcome else { return nil }
        return plan
    }

    private static func paper(identifier: NotabilityPaperIdentifier? = .legacyWhite, size: NotabilityPaperSize? = .letter,
                              lineStyle: NotabilityPaperLineStyle? = .noLines) -> NotabilityPaper {
        NotabilityPaper(identifier: identifier, size: size, orientation: .portrait,
                        sizingBehaviour: .lockedWidth(width: pageWidthInUnits, device: "iPad"), lineStyle: lineStyle)
    }

    private static func note(pageWidthInUnits: Double? = pageWidthInUnits, paper: NotabilityPaper = paper(),
                             typedText: NotabilityTypedText = NotabilityTypedText(text: "", runs: []),
                             importedPDFPages: [NotabilityImportedPDFPage] = []) -> NotabilityNote {
        NotabilityNote(name: nil, sessionFormatVersion: 9, applicationVersion: nil, paper: paper,
                       reflowState: pageWidthInUnits.map { width in .locked(pageWidth: width, device: nil) } ?? .reflowable,
                       pageGeometry: NotabilityPageGeometry(pageWidthInUnits: pageWidthInUnits, paper: paper), shapes: [], pictures: [],
                       typedText: typedText, importedPDFPages: importedPDFPages, recordings: [], playbackEvents: [])
    }

    private static func page(number: Int, top: Double = 0, curves: [NotabilityCurve], shapes: [NotabilityShape] = [],
                             pictures: [NotabilityPicture] = []) -> NotabilityPage {
        NotabilityPage(pageNumber: number, topInUnits: top, curves: curves, shapes: shapes, pictures: pictures)
    }

    private static func curve(style: NotabilityCurveStyle = .pen, width: Double, points: [CGPoint], knots: [NotabilityKnot]) -> NotabilityCurve {
        NotabilityCurve(index: 0, uuid: UUID(), style: style, width: width, color: inkColor, points: points, knots: knots)
    }

    private static func knot(widthFactor: Double = 1, force: Double = 1, altitude: Double? = nil,
                             azimuth: NotabilityAzimuthVector? = nil) -> NotabilityKnot {
        NotabilityKnot(widthFactor: widthFactor, force: force, altitudeAngle: altitude, azimuthUnitVector: azimuth)
    }

    /// A chain of straight cubic segments through the knots: each segment's controls sit a third and two thirds along it.
    private static func straightChain(through knots: [CGPoint]) -> [CGPoint] {
        var points = [knots[0]]
        for (start, end) in zip(knots, knots.dropFirst()) {
            points.append(CGPoint(x: start.x + (end.x - start.x) / 3, y: start.y + (end.y - start.y) / 3))
            points.append(CGPoint(x: start.x + (end.x - start.x) * 2 / 3, y: start.y + (end.y - start.y) * 2 / 3))
            points.append(end)
        }
        return points
    }

    private static func assertPoint(_ point: CGPoint, x: Double, y: Double) {
        XCTAssertEqual(point.x, x, accuracy: accuracy)
        XCTAssertEqual(point.y, y, accuracy: accuracy)
    }
}
