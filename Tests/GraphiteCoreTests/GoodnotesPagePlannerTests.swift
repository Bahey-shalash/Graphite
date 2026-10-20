import CoreGraphics
import Foundation
import XCTest
@testable import GraphiteCore

/// Planning Goodnotes pages into Graphite pages, on small pages built from the reader's value types.
final class GoodnotesPagePlannerTests: XCTestCase {
    private static let pointsPerUnit = 6.0 / 11.0
    private static let accuracy = 1e-9
    private static let inkColor = NotebookImportColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
    private static let white = NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)

    // MARK: Page and background

    func testAPageWithoutPaperIsLeftOutWithTheReason() {
        let outcome = GoodnotesPagePlanner.plan(Self.page(paper: nil, elements: []), pageNumber: 3)
        XCTAssertEqual(outcome, .leftOut(sourcePageNumber: 3, report: [.pageWithoutPaper]))
    }

    func testAPageWithPaperAndAnAttachmentIsAPdfPageOfThePaperSizeInPoints() throws {
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(paper: Self.makePaper(), elements: []), pageNumber: 4)))
        XCTAssertEqual(plan.sourcePageNumber, 4)
        XCTAssertEqual(plan.background, .pdfPage(ImportedSourceFile(path: .fixture("attachments/FILE-1")), pageNumber: 2))
        XCTAssertEqual(plan.sizeInPoints.width, 600, accuracy: Self.accuracy)
        XCTAssertEqual(plan.sizeInPoints.height, 900, accuracy: Self.accuracy)
        XCTAssertEqual(plan.strokes, [])
        XCTAssertEqual(plan.report, [])
    }

    func testAPaperWithoutAnAttachmentIsPlainWhitePaperAndIsReported() throws {
        let page = Self.page(paper: Self.makePaper(attachment: nil), elements: [])
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(page, pageNumber: 1)))
        XCTAssertEqual(plan.background, .plainColor(Self.white))
        XCTAssertEqual(plan.report, [.backgroundFileMissing])
        XCTAssertEqual(plan.sizeInPoints.width, 600, accuracy: Self.accuracy)
    }

    func testTheReadersIssuesAppearFirstInThePageReport() throws {
        let issues: [GoodnotesReadingIssue] = [.eventKindNotKnown(5), .schemaVersionNotKnown(nil)]
        let planned = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(paper: Self.makePaper(attachment: nil), elements: [],
                                                                                          issues: issues), pageNumber: 1)))
        XCTAssertEqual(planned.report, [.goodnotesReadingIssue(.eventKindNotKnown(5)), .goodnotesReadingIssue(.schemaVersionNotKnown(nil)),
                                        .backgroundFileMissing])
        let leftOut = GoodnotesPagePlanner.plan(Self.page(paper: nil, elements: [], issues: issues), pageNumber: 2)
        XCTAssertEqual(leftOut, .leftOut(sourcePageNumber: 2, report: [
            .goodnotesReadingIssue(.eventKindNotKnown(5)), .goodnotesReadingIssue(.schemaVersionNotKnown(nil)), .pageWithoutPaper
        ]))
    }

    // MARK: Constant-width strokes

    func testAConstantWidthStrokeIsSampledInPointsWithTheOffsetAndOneWidth() throws {
        let subpath = GoodnotesSubpath(start: CGPoint(x: 11, y: 22), curves: [
            GoodnotesQuadraticCurve(control: CGPoint(x: 33, y: 22), end: CGPoint(x: 55, y: 22))
        ])
        let path = GoodnotesStrokePath.constantWidth(GoodnotesConstantWidthPath(width: 22, subpaths: [subpath], dashPattern: []))
        let stroke = Self.stroke(path: path, offset: CGVector(dx: 11, dy: 0))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [stroke]), pageNumber: 1)))
        let planned = try XCTUnwrap(plan.strokes.first)
        XCTAssertEqual(plan.strokes.count, 1)
        XCTAssertEqual(planned.ink, .monoline)
        XCTAssertEqual(planned.color, Self.inkColor)
        XCTAssertNil(planned.outline)
        XCTAssertEqual(planned.samples.count, 2)
        Self.assertLocation(planned.samples[0], x: 22 * Self.pointsPerUnit, y: 22 * Self.pointsPerUnit)
        Self.assertLocation(planned.samples[1], x: 66 * Self.pointsPerUnit, y: 22 * Self.pointsPerUnit)
        for sample in planned.samples {
            XCTAssertEqual(sample.width, 12, accuracy: Self.accuracy)
            XCTAssertNil(sample.force)
            XCTAssertNil(sample.azimuthRadians)
            XCTAssertNil(sample.altitudeRadians)
        }
        XCTAssertEqual(plan.report, [])
    }

    func testACurvedConstantWidthStrokeEndsAtTheCurveEndAndStaysCloseToTheCurve() throws {
        let curve = GoodnotesQuadraticCurve(control: CGPoint(x: 110, y: 220), end: CGPoint(x: 220, y: 0))
        let path = GoodnotesStrokePath.constantWidth(GoodnotesConstantWidthPath(
            width: 11, subpaths: [GoodnotesSubpath(start: CGPoint(x: 0, y: 0), curves: [curve])], dashPattern: []))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        let samples = try XCTUnwrap(plan.strokes.first).samples
        XCTAssertGreaterThan(samples.count, 3)
        let lastSample = try XCTUnwrap(samples.last)
        Self.assertLocation(samples[0], x: 0, y: 0)
        Self.assertLocation(lastSample, x: 120, y: 0)
        let peakHeight = try XCTUnwrap(samples.map { sample in sample.location.y }.max())
        XCTAssertEqual(peakHeight, 60, accuracy: 0.2)
    }

    func testEverySubpathOfAConstantWidthStrokeBecomesItsOwnStroke() throws {
        let straight = { (start: CGPoint, end: CGPoint) in
            GoodnotesSubpath(start: start, curves: [GoodnotesQuadraticCurve(control: CGPoint(x: (start.x + end.x) / 2, y: start.y), end: end)])
        }
        let path = GoodnotesStrokePath.constantWidth(GoodnotesConstantWidthPath(width: 11, subpaths: [
            straight(CGPoint(x: 0, y: 0), CGPoint(x: 110, y: 0)), straight(CGPoint(x: 0, y: 55), CGPoint(x: 110, y: 55))
        ], dashPattern: []))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        XCTAssertEqual(plan.strokes.count, 2)
        XCTAssertEqual(plan.strokes.map { stroke in stroke.ink }, [.monoline, .monoline])
        XCTAssertEqual(try XCTUnwrap(plan.strokes[1].samples.first).location.y, 30, accuracy: Self.accuracy)
    }

    func testADashedStrokeIsKeptSolidAndCounted() throws {
        let path = GoodnotesStrokePath.constantWidth(GoodnotesConstantWidthPath(
            width: 11, subpaths: [Self.straightSubpath()], dashPattern: [10, 5]))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        XCTAssertEqual(plan.strokes.count, 1)
        XCTAssertEqual(plan.report, [.dashesNotKept(strokeCount: 1)])
    }

    // MARK: Highlighters

    func testHighlighterStrokesComeAfterAllOtherInkEvenWhenDrawnEarlier() throws {
        let highlighterColor = NotebookImportColor(red: 1, green: 1, blue: 0, alpha: 0.5)
        let highlighter = Self.stroke(path: Self.straightPath(), color: highlighterColor, isHighlighter: true, counter: 1)
        let ballPen = Self.stroke(path: Self.straightPath(), counter: 2)
        let secondHighlighter = Self.stroke(path: Self.straightPath(), color: highlighterColor, isHighlighter: true, counter: 3)
        let lastBallPen = Self.stroke(path: Self.straightPath(), counter: 4)
        let page = Self.page(elements: [highlighter, ballPen, secondHighlighter, lastBallPen])
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(page, pageNumber: 1)))
        XCTAssertEqual(plan.strokes.map { stroke in stroke.ink }, [.monoline, .monoline, .highlighter, .highlighter])
        XCTAssertEqual(plan.strokes.map { stroke in stroke.color }, [Self.inkColor, Self.inkColor, highlighterColor, highlighterColor])
        XCTAssertEqual(plan.report, [.highlighterNotMultiplied(strokeCount: 2)])
    }

    // MARK: Varying-width strokes

    func testAVaryingWidthStrokeInterpolatesTheStoredWidthsAlongTheCenterLine() throws {
        let centerLine = GoodnotesCenterLine(start: GoodnotesWidthPoint(point: CGPoint(x: 0, y: 0), width: 11), curves: [
            GoodnotesWidthCurve(control: GoodnotesWidthPoint(point: CGPoint(x: 110, y: 220), width: 55),
                                end: GoodnotesWidthPoint(point: CGPoint(x: 220, y: 0), width: 33))
        ])
        let path = GoodnotesStrokePath.varyingWidth(GoodnotesVaryingWidthPath(centerLine: centerLine, outline: []))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        XCTAssertEqual(plan.strokes.count, 1)
        let planned = try XCTUnwrap(plan.strokes.first)
        XCTAssertEqual(planned.ink, .fountainPen)
        XCTAssertEqual(planned.outline, [])
        let parameters = BezierFlattening.quadraticParameters(start: CGPoint(x: 0, y: 0), control: CGPoint(x: 60, y: 120),
                                                              end: CGPoint(x: 120, y: 0), tolerance: GoodnotesStrokePlanner.flatteningToleranceInPoints)
        XCTAssertEqual(planned.samples.count, parameters.count + 1)
        XCTAssertEqual(planned.samples[0].width, 6, accuracy: Self.accuracy)
        XCTAssertEqual(try XCTUnwrap(planned.samples.last).width, 18, accuracy: Self.accuracy)
        let middleIndex = parameters.count / 2
        let middleParameter = parameters[middleIndex - 1]
        let remaining = 1 - middleParameter
        let expectedMiddleWidth = remaining * remaining * 6 + 2 * remaining * middleParameter * 30 + middleParameter * middleParameter * 18
        XCTAssertEqual(planned.samples[middleIndex].width, expectedMiddleWidth, accuracy: Self.accuracy)
        XCTAssertGreaterThan(planned.samples[middleIndex].width, 6)
    }

    func testAVaryingWidthOutlineKeepsTheFlattenedMoveCubicArcAndFlatCapPoints() throws {
        let outline: [[GoodnotesOutlineCommand]] = [[
            .move(to: CGPoint(x: 0, y: 0)),
            .cubic(control1: CGPoint(x: 11, y: 0), control2: CGPoint(x: 22, y: 0), end: CGPoint(x: 33, y: 0)),
            .arc(center: CGPoint(x: 33, y: 11), radius: 11, startAngleRadians: -Double.pi / 2, endAngleRadians: Double.pi / 2),
            .flatCap(through: CGPoint(x: 0, y: 22))
        ]]
        let centerLine = GoodnotesCenterLine(start: GoodnotesWidthPoint(point: .zero, width: 11), curves: [])
        let path = GoodnotesStrokePath.varyingWidth(GoodnotesVaryingWidthPath(centerLine: centerLine, outline: outline))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        let polygons = try XCTUnwrap(try XCTUnwrap(plan.strokes.first).outline)
        XCTAssertEqual(polygons.count, 1)
        let polygon = polygons[0]
        XCTAssertGreaterThan(polygon.count, 4)
        Self.assertPoint(polygon[0], x: 0, y: 0)
        Self.assertPoint(polygon[1], x: 18, y: 0)
        Self.assertPoint(polygon[polygon.count - 1], x: 0, y: 12)
        Self.assertPoint(polygon[polygon.count - 2], x: 18, y: 12)
        for arcPoint in polygon[2..<(polygon.count - 1)] {
            XCTAssertEqual(hypot(arcPoint.x - 18, arcPoint.y - 6), 6, accuracy: Self.accuracy)
            XCTAssertGreaterThanOrEqual(arcPoint.x, 18 - Self.accuracy)
        }
    }

    func testAnOutlineSubpathOfTwoPointsIsDroppedBecauseItEnclosesNothing() throws {
        let outline: [[GoodnotesOutlineCommand]] = [[.move(to: CGPoint(x: 0, y: 0)), .flatCap(through: CGPoint(x: 11, y: 11))]]
        let centerLine = GoodnotesCenterLine(start: GoodnotesWidthPoint(point: .zero, width: 11), curves: [])
        let path = GoodnotesStrokePath.varyingWidth(GoodnotesVaryingWidthPath(centerLine: centerLine, outline: outline))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        XCTAssertEqual(try XCTUnwrap(plan.strokes.first).outline, [])
    }

    func testAVaryingWidthPathWithoutACenterLineIsCountedAsOlderInk() throws {
        let path = GoodnotesStrokePath.varyingWidth(GoodnotesVaryingWidthPath(centerLine: nil, outline: []))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        XCTAssertEqual(plan.strokes, [])
        XCTAssertEqual(plan.report, [.olderVaryingWidthInkLeftOut(strokeCount: 1)])
    }

    // MARK: Pencil strokes

    func testAPencilStrokeKeepsTheStateAtItsEndsAndInterpolatesInBetween() throws {
        let path = GoodnotesStrokePath.pencil(GoodnotesPencilPath(width: 11, subpaths: [Self.pencilSubpath()]))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        XCTAssertEqual(plan.strokes.count, 1)
        let planned = try XCTUnwrap(plan.strokes.first)
        XCTAssertEqual(planned.ink, .pencil)
        let first = planned.samples[0], last = try XCTUnwrap(planned.samples.last)
        XCTAssertEqual(first.force ?? -1, 1, accuracy: Self.accuracy)
        XCTAssertEqual(first.azimuthRadians ?? 0, 3.0, accuracy: Self.accuracy)
        XCTAssertEqual(first.altitudeRadians ?? -1, 0.5, accuracy: Self.accuracy)
        XCTAssertEqual(last.force ?? -1, 3, accuracy: Self.accuracy)
        XCTAssertEqual(last.azimuthRadians ?? 0, -2.9, accuracy: Self.accuracy)
        XCTAssertEqual(last.altitudeRadians ?? -1, 1.5, accuracy: Self.accuracy)
        let parameters = BezierFlattening.quadraticParameters(start: CGPoint(x: 0, y: 0), control: CGPoint(x: 30, y: 30),
                                                              end: CGPoint(x: 60, y: 0), tolerance: GoodnotesStrokePlanner.flatteningToleranceInPoints)
        XCTAssertEqual(planned.samples.count, parameters.count + 1)
        let middleIndex = parameters.count / 2
        let middleParameter = parameters[middleIndex - 1]
        XCTAssertEqual(planned.samples[middleIndex].force ?? -1, 1 + 2 * middleParameter, accuracy: Self.accuracy)
        XCTAssertEqual(planned.samples[middleIndex].altitudeRadians ?? -1, 0.5 + middleParameter, accuracy: Self.accuracy)
        for sample in planned.samples {
            XCTAssertEqual(sample.width, 6, accuracy: Self.accuracy)
        }
    }

    func testAPencilAzimuthTurningAcrossPlusOrMinusPiGoesTheShortWay() throws {
        let path = GoodnotesStrokePath.pencil(GoodnotesPencilPath(width: 11, subpaths: [Self.pencilSubpath()]))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        let samples = try XCTUnwrap(plan.strokes.first).samples
        for sample in samples {
            let azimuth = try XCTUnwrap(sample.azimuthRadians)
            XCTAssertLessThanOrEqual(abs(abs(azimuth) - Double.pi), 0.3)
        }
    }

    func testAPencilStrokeIsCountedForItsTexture() throws {
        let path = GoodnotesStrokePath.pencil(GoodnotesPencilPath(width: 11, subpaths: [Self.pencilSubpath(), Self.pencilSubpath()]))
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [Self.stroke(path: path)]), pageNumber: 1)))
        XCTAssertEqual(plan.strokes.count, 2)
        XCTAssertEqual(plan.report, [.pencilTextureNotKept(strokeCount: 1)])
    }

    // MARK: Elements left out

    func testShapesTapeOlderInkAndOtherElementsAreLeftOutAndCounted() throws {
        let shapeStroke = Self.stroke(path: Self.straightPath(), shape: GoodnotesShape(geometry: nil, width: nil), counter: 1)
        let tape = Self.stroke(path: Self.straightPath(), ink: .fountainPenBrushPenOrTape, isTape: true, counter: 2)
        let olderInk = Self.stroke(path: .olderVaryingWidth(GoodnotesOlderVaryingWidthPath(width: 11, outline: [])),
                                   ink: .olderVaryingWidth, counter: 3)
        let richText = GoodnotesRichText(text: "Text", runs: [], defaultAttributes: nil)
        let picture = GoodnotesPicture(attachment: nil, boundingBox: .zero, center: .zero, size: .zero, rotationRadians: 0, kind: nil)
        let elements = [
            shapeStroke, tape, olderInk,
            Self.element(.picture(picture), counter: 4), Self.element(.picture(picture), counter: 5),
            Self.element(.shapeFill(GoodnotesShapeFill(color: Self.inkColor, shape: nil, outlineStrokeIdentifiers: [], offset: .zero)),
                         counter: 6),
            Self.element(.textBox(GoodnotesTextBox(origin: .zero, rotationRadians: 0, scale: 1, size: nil, insets: nil, richText: richText)),
                         counter: 7),
            Self.element(.rtfTextBox(GoodnotesRTFTextBox(frame: .zero, textFrame: .zero, rtf: "")), counter: 8),
            Self.element(.rtfTextElement(rtf: ""), counter: 9),
            Self.element(.stickyNote(GoodnotesStickyNote(origin: .zero, size: .zero, paperColor: Self.white, richText: richText,
                                                         authorName: "Author")), counter: 10)
        ]
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: elements), pageNumber: 1)))
        XCTAssertEqual(plan.strokes, [])
        XCTAssertEqual(plan.pictures, [], "Pictures without an attachment have no file to place.")
        XCTAssertEqual(plan.report, [
            .elementsNotYetConverted(kind: .shape, count: 1), .tapeLeftOut(strokeCount: 1), .olderVaryingWidthInkLeftOut(strokeCount: 1),
            .pictureFilesMissing(count: 2), .elementsNotYetConverted(kind: .shapeFill, count: 1),
            .elementsNotYetConverted(kind: .textBox, count: 3), .elementsNotYetConverted(kind: .stickyNote, count: 1)
        ])
    }

    func testABookmarkedPageIsPlannedBookmarked() throws {
        let bookmarked = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [], isBookmarked: true), pageNumber: 1)))
        XCTAssertTrue(bookmarked.isBookmarked)
        let unmarked = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: []), pageNumber: 1)))
        XCTAssertFalse(unmarked.isBookmarked)
    }

    // MARK: Builders

    private static func plannedPlan(_ outcome: ImportedPageOutcome) -> ImportedPagePlan? {
        guard case .planned(let plan) = outcome else { return nil }
        return plan
    }

    private static func makePaper(attachment: GoodnotesAttachment? = GoodnotesAttachment(identifier: "attachment-1", file: .fixture("attachments/FILE-1"),
                                                                                      byteCount: nil, pdfPageCount: nil)) -> GoodnotesPaper {
        GoodnotesPaper(identifier: "paper-1", attachment: attachment, pdfPageNumber: 2, sizeInUnits: CGSize(width: 1100, height: 1650), template: nil)
    }

    private static func page(paper: GoodnotesPaper? = makePaper(), elements: [GoodnotesElement], issues: [GoodnotesReadingIssue] = [],
                             isBookmarked: Bool = false) -> GoodnotesPage {
        let descriptor = GoodnotesPageDescriptor(identifier: "page-1", layerIdentifier: nil, paper: paper, isBookmarked: isBookmarked, isFlagged: false)
        return GoodnotesPage(descriptor: descriptor, elements: elements, issues: issues)
    }

    private static func element(_ content: GoodnotesElementContent, counter: UInt64) -> GoodnotesElement {
        GoodnotesElement(identifier: "element-\(counter)", drawingPosition: GoodnotesDrawingPosition(counter: counter, replica: 0), content: content)
    }

    private static func stroke(path: GoodnotesStrokePath, ink: GoodnotesStroke.Ink = .ballPenOrHighlighter, color: NotebookImportColor = inkColor,
                               isHighlighter: Bool = false, isTape: Bool = false, offset: CGVector = .zero, shape: GoodnotesShape? = nil,
                               counter: UInt64 = 1) -> GoodnotesElement {
        element(.stroke(GoodnotesStroke(ink: ink, color: color, isHighlighter: isHighlighter, isTape: isTape, groupIdentifier: nil, offset: offset,
                                        shape: shape, path: path)), counter: counter)
    }

    private static func straightSubpath() -> GoodnotesSubpath {
        GoodnotesSubpath(start: CGPoint(x: 0, y: 0), curves: [GoodnotesQuadraticCurve(control: CGPoint(x: 55, y: 0), end: CGPoint(x: 110, y: 0))])
    }

    private static func straightPath() -> GoodnotesStrokePath {
        .constantWidth(GoodnotesConstantWidthPath(width: 11, subpaths: [straightSubpath()], dashPattern: []))
    }

    /// From (0, 0) through (30, 30) to (60, 0) in points; the azimuth turns from 3.0 through -3.0 to -2.9, across π.
    private static func pencilSubpath() -> GoodnotesPencilSubpath {
        func sample(_ x: Double, _ y: Double, azimuth: Double, altitude: Double, force: Double) -> GoodnotesPencilSample {
            GoodnotesPencilSample(point: CGPoint(x: x, y: y), azimuthRadians: azimuth, altitudeRadians: altitude, force: force)
        }
        return GoodnotesPencilSubpath(start: sample(0, 0, azimuth: 3.0, altitude: 0.5, force: 1), curves: [
            GoodnotesPencilCurve(control: sample(55, 55, azimuth: -3.0, altitude: 1.0, force: 2),
                                 end: sample(110, 0, azimuth: -2.9, altitude: 1.5, force: 3), leadingValue: 0)
        ])
    }

    private static func assertLocation(_ sample: ImportedStrokeSample, x: Double, y: Double) {
        assertPoint(sample.location, x: x, y: y)
    }

    private static func assertPoint(_ point: CGPoint, x: Double, y: Double) {
        XCTAssertEqual(point.x, x, accuracy: accuracy)
        XCTAssertEqual(point.y, y, accuracy: accuracy)
    }
}
