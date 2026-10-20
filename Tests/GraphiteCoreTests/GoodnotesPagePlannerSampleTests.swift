import CoreGraphics
import Foundation
import XCTest
@testable import GraphiteCore

/// Plans every page of the owner's Goodnotes samples. The notebooks are personal and never in the repository, so
/// this test is skipped unless `GRAPHITE_IMPORT_SAMPLES` and `GRAPHITE_IMPORT_REFERENCE_COUNTS` are set (see
/// `NotebookImportSamples`).
final class GoodnotesPagePlannerSampleTests: XCTestCase {
    func testEverySamplePageIsPlannedWithOneStrokePerInkSubpathAndFiniteSamples() throws {
        let configuration = try NotebookImportSamples.configuration()
        for samplePath in NotebookImportSamples.samplePaths(withExtension: "goodnotes", in: configuration) {
            let archiveBytes = try Data(contentsOf: configuration.samplesFolder.appendingPathComponent(samplePath), options: .alwaysMapped)
            let reader = try GoodnotesNotebookReader(archiveBytes: archiveBytes, limits: .standard)
            var plannedStrokeCount = 0, expectedStrokeCount = 0, sampleCount = 0
            for pageIndex in 0..<reader.pageCount {
                let page = try reader.page(at: pageIndex)
                guard case .planned(let plan) = GoodnotesPagePlanner.plan(page, pageNumber: pageIndex + 1) else {
                    XCTFail("page \(pageIndex + 1) of \(samplePath) was left out")
                    continue
                }
                expectedStrokeCount += page.elements.reduce(0) { total, element in total + Self.expectedStrokeCount(element.content) }
                plannedStrokeCount += plan.strokes.count
                sampleCount += plan.strokes.reduce(0) { total, stroke in total + stroke.samples.count }
                for stroke in plan.strokes { Self.assertFinite(stroke, in: samplePath) }
            }
            XCTAssertEqual(plannedStrokeCount, expectedStrokeCount, samplePath)
            print("GOODNOTES-PLAN \(samplePath) strokes \(plannedStrokeCount) samples \(sampleCount)")
        }
    }

    /// One planned stroke per subpath of each ink stroke the planner converts; none for shapes, tape and the older ink.
    private static func expectedStrokeCount(_ content: GoodnotesElementContent) -> Int {
        guard case .stroke(let stroke) = content, stroke.shape == nil, !stroke.isTape else { return 0 }
        switch stroke.path {
        case .constantWidth(let path): return path.subpaths.count
        case .varyingWidth(let path): return path.centerLine == nil ? 0 : 1
        case .olderVaryingWidth: return 0
        case .pencil(let path): return path.subpaths.count
        case .unknownLayout: return 0
        }
    }

    private static func assertFinite(_ stroke: ImportedStroke, in samplePath: String) {
        XCTAssertFalse(stroke.samples.isEmpty, samplePath)
        for sample in stroke.samples where !(sample.location.x.isFinite && sample.location.y.isFinite && sample.width.isFinite && sample.width >= 0) {
            XCTFail("a sample of \(samplePath) is not finite: \(sample)")
            return
        }
    }
}
