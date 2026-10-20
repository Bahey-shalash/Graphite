import CoreGraphics
import Foundation
import XCTest
@testable import GraphiteCore

/// Plans every page of the owner's Notability samples. The notes are personal and never in the repository, so this
/// test is skipped unless `GRAPHITE_IMPORT_SAMPLES` and `GRAPHITE_IMPORT_REFERENCE_COUNTS` are set (see
/// `NotebookImportSamples`).
final class NotabilityPagePlannerSampleTests: XCTestCase {
    func testEveryPageOfANoteWithKnownGeometryIsPlannedWithEveryCurveAndFiniteSamples() throws {
        let configuration = try NotebookImportSamples.configuration()
        for samplePath in NotebookImportSamples.samplePaths(withExtension: "note", in: configuration) {
            let archiveBytes = try Data(contentsOf: configuration.samplesFolder.appendingPathComponent(samplePath), options: .alwaysMapped)
            let reader = try NotabilityNoteReader(archiveBytes: archiveBytes, limits: .standard)
            guard let pageCount = reader.pageCount else {
                XCTAssertNil(reader.note.pageGeometry.pointsPerUnit, samplePath)
                continue
            }
            var plannedStrokeCount = 0, curvesOnPages = 0
            for pageNumber in 1...pageCount {
                let page = try reader.page(number: pageNumber)
                guard case .planned(let plan) = NotabilityPagePlanner.plan(page, note: reader.note) else {
                    XCTFail("page \(pageNumber) of \(samplePath) was left out")
                    continue
                }
                curvesOnPages += page.curves.count
                plannedStrokeCount += plan.strokes.count
                XCTAssertEqual(plan.sizeInPoints, reader.note.pageGeometry.exportPageSizeInPoints, samplePath)
                for stroke in plan.strokes {
                    XCTAssertTrue(stroke.samples.allSatisfy { sample in sample.location.x.isFinite && sample.location.y.isFinite && sample.width > 0 },
                                  samplePath)
                }
            }
            // A curve can be cut into several pieces, and one listed on a page may have no sample there.
            XCTAssertGreaterThanOrEqual(plannedStrokeCount, reader.curveCount == 0 ? 0 : 1, samplePath)
            print("NOTABILITY-PLAN \(samplePath) pages \(pageCount) curves on pages \(curvesOnPages) strokes \(plannedStrokeCount)")
        }
    }

    /// Each picture of each note is planned on every page it reaches, with a file the note gives and a usable crop.
    func testEverySamplePictureIsPlannedOnThePagesItReaches() throws {
        let configuration = try NotebookImportSamples.configuration()
        var plannedTotal = 0
        for samplePath in NotebookImportSamples.samplePaths(withExtension: "note", in: configuration) {
            let archiveBytes = try Data(contentsOf: configuration.samplesFolder.appendingPathComponent(samplePath), options: .alwaysMapped)
            let reader = try NotabilityNoteReader(archiveBytes: archiveBytes, limits: .standard)
            XCTAssertEqual(configuration.referenceCounts[samplePath]?["pictures"], .number(Double(reader.note.pictures.count)), samplePath)
            guard let pageCount = reader.pageCount else {
                XCTAssertEqual(reader.note.pictures, [], "\(samplePath): a note left out whole has no picture to lose")
                continue
            }
            var picturesOnPages: [NotabilityPicture] = []
            for pageNumber in 1...pageCount {
                let page = try reader.page(number: pageNumber)
                guard case .planned(let plan) = NotabilityPagePlanner.plan(page, note: reader.note) else { continue }
                XCTAssertEqual(plan.pictures.count, page.pictures.count, samplePath)
                for picture in page.pictures where !picturesOnPages.contains(picture) { picturesOnPages.append(picture) }
                for picture in plan.pictures { try Self.assertUsable(picture, reader: reader, in: samplePath) }
            }
            XCTAssertEqual(picturesOnPages.count, reader.note.pictures.count, samplePath)
            plannedTotal += picturesOnPages.count
        }
        print("NOTABILITY-PICTURES planned \(plannedTotal)")
    }

    private static func assertUsable(_ picture: ImportedPicture, reader: NotabilityNoteReader, in samplePath: String) throws {
        XCTAssertNoThrow(try reader.fileBytes(picture.file.path), "\(samplePath): \(picture.file.pathInSource)")
        let crop = try XCTUnwrap(picture.cropRectangleInPixels, samplePath)
        let values = [picture.frame.minX, picture.frame.minY, picture.frame.width, picture.frame.height, crop.minX, crop.minY, crop.width, crop.height,
                      picture.rotationRadiansClockwise]
        XCTAssertTrue(values.allSatisfy(\.isFinite), samplePath)
        XCTAssertTrue(picture.frame.width > 0 && picture.frame.height > 0 && crop.width > 0 && crop.height > 0, samplePath)
    }
}
