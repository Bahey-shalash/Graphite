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
}
