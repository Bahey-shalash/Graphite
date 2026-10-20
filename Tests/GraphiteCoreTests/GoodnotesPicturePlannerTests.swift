import CoreGraphics
import Foundation
import XCTest
@testable import GraphiteCore

/// Planning Goodnotes pictures: their file, frame in points, angle, drawing order and report.
final class GoodnotesPicturePlannerTests: XCTestCase {
    private static let accuracy = 1e-9
    private static let inkColor = NotebookImportColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)

    func testAPictureIsItsAttachmentsFileInAFrameCenteredOnThePlacementInPointsTurnedByItsAngle() throws {
        let picture = Self.picture(file: "attachments/PHOTO", center: CGPoint(x: 220, y: 330), size: CGSize(width: 110, height: 55),
                                   rotationRadians: 0.5087)
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [picture]), pageNumber: 1)))
        XCTAssertEqual(plan.pictures.count, 1)
        let planned = try XCTUnwrap(plan.pictures.first)
        XCTAssertEqual(planned.file, ImportedSourceFile(path: .fixture("attachments/PHOTO")))
        // Center (120, 180) and size 60 × 30 in points.
        XCTAssertEqual(planned.frame.minX, 90, accuracy: Self.accuracy)
        XCTAssertEqual(planned.frame.minY, 165, accuracy: Self.accuracy)
        XCTAssertEqual(planned.frame.width, 60, accuracy: Self.accuracy)
        XCTAssertEqual(planned.frame.height, 30, accuracy: Self.accuracy)
        XCTAssertEqual(planned.rotationRadiansClockwise, 0.5087, accuracy: Self.accuracy)
        XCTAssertNil(planned.cropRectangleInPixels, "A cropped Goodnotes picture already names a file of the kept part.")
        XCTAssertFalse(planned.isFlippedHorizontally)
        XCTAssertFalse(planned.isFlippedVertically)
        XCTAssertEqual(plan.report, [])
    }

    func testAPictureWithoutItsAttachmentOrWithoutAFileIsLeftOutAndCounted() throws {
        let withoutAttachment = Self.element(.picture(GoodnotesPicture(attachment: nil, boundingBox: .zero, center: .zero,
                                                                       size: CGSize(width: 10, height: 10), rotationRadians: 0, kind: nil)), counter: 1)
        let attachment = GoodnotesAttachment(identifier: "attachment-2", fileIdentifier: "../escape", file: nil, byteCount: nil, pdfPageCount: nil)
        let withoutFile = Self.element(.picture(GoodnotesPicture(attachment: attachment, boundingBox: .zero, center: .zero,
                                                                 size: CGSize(width: 10, height: 10), rotationRadians: 0, kind: nil)), counter: 2)
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [withoutAttachment, withoutFile]), pageNumber: 1)))
        XCTAssertEqual(plan.pictures, [])
        XCTAssertEqual(plan.report, [.pictureFilesMissing(count: 2)])
    }

    func testAnAnimatedGIFIsPlannedAndCountedAsKeptStill() throws {
        let gif = Self.picture(file: "attachments/GIF", kind: .animatedGIF, counter: 1)
        let sticker = Self.picture(file: "attachments/STICKER", kind: .jpeg2000Sticker, counter: 2)
        let turned = Self.picture(file: "attachments/TURNED", kind: .unknown(1), counter: 3)
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: [gif, sticker, turned]), pageNumber: 1)))
        XCTAssertEqual(plan.pictures.map(\.file.pathInSource), ["attachments/GIF", "attachments/STICKER", "attachments/TURNED"])
        XCTAssertEqual(plan.report, [.animatedPicturesKeptStill(count: 1)])
    }

    /// Ink drawn before a picture was under it in Goodnotes and is over it in Graphite.
    func testPicturesKeepTheirDrawingOrderAndThoseDrawnAfterInkAreCountedAsMovedUnderIt() throws {
        let elements = [
            Self.picture(file: "attachments/FIRST", counter: 1),
            Self.stroke(counter: 2),
            Self.picture(file: "attachments/SECOND", counter: 3),
            Self.picture(file: "attachments/THIRD", counter: 4)
        ]
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: elements), pageNumber: 1)))
        XCTAssertEqual(plan.pictures.map(\.file.pathInSource), ["attachments/FIRST", "attachments/SECOND", "attachments/THIRD"])
        XCTAssertEqual(plan.strokes.count, 1)
        XCTAssertEqual(plan.report, [.picturesMovedUnderInk(count: 2)])
    }

    /// Goodnotes draws highlighters over everything, and strokes left out draw nothing, so neither moves a picture.
    func testHighlighterAndStrokesLeftOutBeforeAPictureDoNotCountItAsMoved() throws {
        let elements = [
            Self.stroke(isHighlighter: true, counter: 1),
            Self.stroke(isTape: true, counter: 2),
            Self.stroke(shape: GoodnotesShape(geometry: nil, width: nil), counter: 3),
            Self.picture(file: "attachments/PHOTO", counter: 4)
        ]
        let plan = try XCTUnwrap(Self.plannedPlan(GoodnotesPagePlanner.plan(Self.page(elements: elements), pageNumber: 1)))
        XCTAssertEqual(plan.pictures.count, 1)
        XCTAssertEqual(plan.report, [
            .highlighterNotMultiplied(strokeCount: 1), .tapeLeftOut(strokeCount: 1), .elementsNotYetConverted(kind: .shape, count: 1)
        ])
    }

    // MARK: Builders

    private static func plannedPlan(_ outcome: ImportedPageOutcome) -> ImportedPagePlan? {
        guard case .planned(let plan) = outcome else { return nil }
        return plan
    }

    private static func page(elements: [GoodnotesElement]) -> GoodnotesPage {
        let attachment = GoodnotesAttachment(identifier: "attachment-1", fileIdentifier: "FILE-1", file: .fixture("attachments/FILE-1"),
                                             byteCount: nil, pdfPageCount: nil)
        let paper = GoodnotesPaper(identifier: "paper-1", attachment: attachment, pdfPageNumber: 1, sizeInUnits: CGSize(width: 1100, height: 1650),
                                   template: nil)
        let descriptor = GoodnotesPageDescriptor(identifier: "page-1", layerIdentifier: nil, paper: paper, isBookmarked: false, isFlagged: false)
        return GoodnotesPage(descriptor: descriptor, elements: elements, issues: [])
    }

    private static func element(_ content: GoodnotesElementContent, counter: UInt64) -> GoodnotesElement {
        GoodnotesElement(identifier: "element-\(counter)", drawingPosition: GoodnotesDrawingPosition(counter: counter, replica: 0), content: content)
    }

    private static func picture(file: String, center: CGPoint = CGPoint(x: 110, y: 110), size: CGSize = CGSize(width: 55, height: 55),
                                rotationRadians: Double = 0, kind: GoodnotesPicture.Kind? = nil, counter: UInt64 = 1) -> GoodnotesElement {
        let attachment = GoodnotesAttachment(identifier: "attachment-\(file)", fileIdentifier: file, file: .fixture(file), byteCount: nil,
                                             pdfPageCount: nil)
        return element(.picture(GoodnotesPicture(attachment: attachment, boundingBox: .zero, center: center, size: size,
                                                 rotationRadians: rotationRadians, kind: kind)), counter: counter)
    }

    private static func stroke(isHighlighter: Bool = false, isTape: Bool = false, shape: GoodnotesShape? = nil, counter: UInt64) -> GoodnotesElement {
        let subpath = GoodnotesSubpath(start: CGPoint(x: 0, y: 0), curves: [GoodnotesQuadraticCurve(control: CGPoint(x: 55, y: 0), end: CGPoint(x: 110, y: 0))])
        let path = GoodnotesStrokePath.constantWidth(GoodnotesConstantWidthPath(width: 11, subpaths: [subpath], dashPattern: []))
        return element(.stroke(GoodnotesStroke(ink: isTape ? .fountainPenBrushPenOrTape : .ballPenOrHighlighter, color: inkColor,
                                               isHighlighter: isHighlighter, isTape: isTape, groupIdentifier: nil, offset: .zero, shape: shape,
                                               path: path)), counter: counter)
    }
}
