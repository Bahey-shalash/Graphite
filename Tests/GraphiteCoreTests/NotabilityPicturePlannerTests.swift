import CoreGraphics
import Foundation
import XCTest
@testable import GraphiteCore

/// Planning Notability pictures: their file, frame through the page transform, angle, crop, flips and order.
final class NotabilityPicturePlannerTests: XCTestCase {
    private static let accuracy = 1e-9
    private static let pageWidthInUnits = 572.0
    private static let pointsPerUnit = 612.0 / 572.0
    private static let leftInset = 15.9375

    func testAPictureIsPlacedThroughThePageTransformWithItsAngleCropAndFlips() throws {
        let crop = CGRect(x: 0, y: 0, width: 226.7, height: 174.7)
        let picture = Self.picture(file: "Images/Image 1.jpg", origin: CGPoint(x: 100, y: 300), size: CGSize(width: 50, height: 40),
                                   rotationRadiansClockwise: 0.443, crop: crop, isFlippedHorizontally: true, isFlippedVertically: false)
        let page = NotabilityPage(pageNumber: 2, topInUnits: 200, curves: [], shapes: [], pictures: [picture])
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(page, note: Self.note())))
        let planned = try XCTUnwrap(plan.pictures.first)
        XCTAssertEqual(plan.pictures.count, 1)
        XCTAssertEqual(planned.file, ImportedSourceFile(path: .fixture("Images/Image 1.jpg")))
        XCTAssertEqual(planned.frame.minX, Self.leftInset + 100 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.frame.minY, 100 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.frame.width, 50 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.frame.height, 40 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.rotationRadiansClockwise, 0.443, accuracy: Self.accuracy)
        XCTAssertEqual(planned.cropRectangleInPixels, crop)
        XCTAssertTrue(planned.isFlippedHorizontally)
        XCTAssertFalse(planned.isFlippedVertically)
        XCTAssertEqual(plan.report, [], "Notability draws pictures under all ink, as Graphite does.")
    }

    func testAPictureStartingAboveThePageHasAFrameAboveItsTop() throws {
        let picture = Self.picture(file: "Images/Image 1.jpg", origin: CGPoint(x: -14.8, y: 180), size: CGSize(width: 40, height: 40))
        let page = NotabilityPage(pageNumber: 2, topInUnits: 200, curves: [], shapes: [], pictures: [picture])
        let planned = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(page, note: Self.note()))?.pictures.first)
        XCTAssertEqual(planned.frame.minX, Self.leftInset - 14.8 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.frame.minY, -20 * Self.pointsPerUnit, accuracy: Self.accuracy)
    }

    func testPicturesAreOrderedByTheirIndexAndThoseOfOneIndexKeepTheNotesOrder() throws {
        let pictures = [
            Self.picture(file: "Images/C.jpg", zIndex: 2), Self.picture(file: "Images/A.jpg", zIndex: 0),
            Self.picture(file: "Images/B1.jpg", zIndex: 1), Self.picture(file: "Images/B2.jpg", zIndex: 1)
        ]
        let page = NotabilityPage(pageNumber: 1, topInUnits: 0, curves: [], shapes: [], pictures: pictures)
        let plan = try XCTUnwrap(Self.plannedPlan(NotabilityPagePlanner.plan(page, note: Self.note())))
        XCTAssertEqual(plan.pictures.map(\.file.pathInSource), ["Images/A.jpg", "Images/B1.jpg", "Images/B2.jpg", "Images/C.jpg"])
    }

    // MARK: Builders

    private static func plannedPlan(_ outcome: ImportedPageOutcome) -> ImportedPagePlan? {
        guard case .planned(let plan) = outcome else { return nil }
        return plan
    }

    private static func picture(file: String, origin: CGPoint = CGPoint(x: 10, y: 10), size: CGSize = CGSize(width: 20, height: 20),
                                rotationRadiansClockwise: Double = 0, zIndex: Int = 0, crop: CGRect = CGRect(x: 0, y: 0, width: 40, height: 40),
                                isFlippedHorizontally: Bool = false, isFlippedVertically: Bool = false) -> NotabilityPicture {
        NotabilityPicture(file: .fixture(file), origin: origin, size: size, rotationRadiansClockwise: rotationRadiansClockwise, zIndex: zIndex,
                          cropRectangle: crop, isFlippedHorizontally: isFlippedHorizontally, isFlippedVertically: isFlippedVertically)
    }

    private static func note() -> NotabilityNote {
        let paper = NotabilityPaper(identifier: .legacyWhite, size: .letter, orientation: .portrait,
                                    sizingBehaviour: .lockedWidth(width: pageWidthInUnits, device: "iPad"), lineStyle: .noLines)
        return NotabilityNote(name: nil, sessionFormatVersion: 9, applicationVersion: nil, paper: paper,
                              reflowState: .locked(pageWidth: pageWidthInUnits, device: nil),
                              pageGeometry: NotabilityPageGeometry(pageWidthInUnits: pageWidthInUnits, paper: paper), shapes: [], pictures: [],
                              typedText: NotabilityTypedText(text: "", runs: []), importedPDFPages: [], recordings: [], playbackEvents: [])
    }
}
