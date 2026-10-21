import CoreGraphics
import Foundation
import XCTest
@testable import NotebookImport

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

    /// Each picture the reference reader counts is planned with a file the notebook gives, or reported as missing.
    func testEverySamplePictureIsPlannedWithAFileTheNotebookHasOrReportedMissing() throws {
        let configuration = try NotebookImportSamples.configuration()
        var plannedTotal = 0, missingTotal = 0
        for samplePath in NotebookImportSamples.samplePaths(withExtension: "goodnotes", in: configuration) {
            let archiveBytes = try Data(contentsOf: configuration.samplesFolder.appendingPathComponent(samplePath), options: .alwaysMapped)
            let reader = try GoodnotesNotebookReader(archiveBytes: archiveBytes, limits: .standard)
            var plannedCount = 0, missingCount = 0
            for pageIndex in 0..<reader.pageCount {
                guard case .planned(let plan) = GoodnotesPagePlanner.plan(try reader.page(at: pageIndex), pageNumber: pageIndex + 1) else { continue }
                plannedCount += plan.pictures.count
                missingCount += plan.report.reduce(0) { total, entry in
                    guard case .pictureFilesMissing(let count) = entry else { return total }
                    return total + count
                }
                for picture in plan.pictures {
                    XCTAssertNoThrow(try reader.contents(ofFileAt: picture.file.path), "\(samplePath): \(picture.file.pathInSource)")
                    Self.assertUsable(picture, in: samplePath)
                }
            }
            XCTAssertEqual(configuration.referenceCounts[samplePath]?["pictures"], .number(Double(plannedCount + missingCount)), samplePath)
            plannedTotal += plannedCount
            missingTotal += missingCount
        }
        print("GOODNOTES-PICTURES planned \(plannedTotal) missing \(missingTotal)")
    }

    /// Every outline entry of the samples names a page of its notebook, in the reference reader's count.
    func testEveryOutlineEntryOfTheSamplesNamesAPageOfItsNotebook() throws {
        let configuration = try NotebookImportSamples.configuration()
        var entryCount = 0
        for samplePath in NotebookImportSamples.samplePaths(withExtension: "goodnotes", in: configuration) {
            let archiveBytes = try Data(contentsOf: configuration.samplesFolder.appendingPathComponent(samplePath), options: .alwaysMapped)
            let notebook = try GoodnotesNotebookReader(archiveBytes: archiveBytes, limits: .standard).notebook
            let plan = GoodnotesOutlinePlanner.plan(notebook)
            XCTAssertEqual(plan.report, [], samplePath)
            XCTAssertEqual(configuration.referenceCounts[samplePath]?["outline_entries"], .number(Double(plan.entries.count)), samplePath)
            XCTAssertEqual(plan.entries.map(\.sourcePageNumber), plan.entries.map(\.sourcePageNumber).sorted(),
                           "In the entries' order the pages only go forward: \(samplePath)")
            entryCount += plan.entries.count
        }
        print("GOODNOTES-OUTLINE entries \(entryCount)")
    }

    private static func assertUsable(_ picture: ImportedPicture, in samplePath: String) {
        let frame = picture.frame
        XCTAssertTrue([frame.minX, frame.minY, frame.width, frame.height, picture.rotationRadiansClockwise].allSatisfy(\.isFinite), samplePath)
        XCTAssertGreaterThan(frame.width, 0, samplePath)
        XCTAssertGreaterThan(frame.height, 0, samplePath)
    }

    /// One planned stroke per subpath of each ink stroke the planner converts, and one per shape with geometry and a
    /// width (its own, or its path's single width); none for other shapes, tape and the older ink.
    private static func expectedStrokeCount(_ content: GoodnotesElementContent) -> Int {
        guard case .stroke(let stroke) = content else { return 0 }
        if let shape = stroke.shape { return shape.geometry != nil && (shape.width != nil || hasSingleWidth(stroke.path)) ? 1 : 0 }
        guard !stroke.isTape else { return 0 }
        switch stroke.path {
        case .constantWidth(let path): return path.subpaths.count
        case .varyingWidth(let path): return path.centerLine == nil ? 0 : 1
        case .olderVaryingWidth: return 0
        case .pencil(let path): return path.subpaths.count
        case .unknownLayout: return 0
        }
    }

    private static func hasSingleWidth(_ path: GoodnotesStrokePath) -> Bool {
        switch path {
        case .constantWidth, .olderVaryingWidth, .pencil: true
        case .varyingWidth, .unknownLayout: false
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
