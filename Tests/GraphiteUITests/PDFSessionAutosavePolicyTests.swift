import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// How long PDF autosave waits and how many steps the history keeps. The delays are a
/// table: `min(max(2 s, 10 × last save), 30 s)`, and after failed saves `2 s × 2^min(failures, 5)`
/// capped at 60 s (never shorter than the first).
@MainActor
final class PDFSessionAutosavePolicyTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFSessionAutosavePolicy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAutosaveWaitsTenTimesTheLastSaveBetweenTwoAndThirtySeconds() {
        let cases: [(saveDuration: Duration, delay: Duration)] = [
            (.zero, .seconds(2)), (.milliseconds(50), .seconds(2)), (.milliseconds(199), .seconds(2)), (.milliseconds(200), .seconds(2)),
            (.milliseconds(201), .milliseconds(2_010)), (.milliseconds(800), .seconds(8)), (.seconds(2), .seconds(20)),
            (.milliseconds(2_999), .milliseconds(29_990)), (.seconds(3), .seconds(30)), (.milliseconds(3_001), .seconds(30)), (.seconds(7), .seconds(30)), (.seconds(600), .seconds(30)),
        ]
        for testCase in cases {
            XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: testCase.saveDuration, consecutiveFailures: 0), testCase.delay, "\(testCase.saveDuration)")
        }
    }

    func testAutosaveAfterFailuresDoublesFromFourSecondsAndStopsAtSixtySeconds() {
        let delaysByFailureCount: [(failures: Int, delay: Duration)] = [
            (1, .seconds(4)), (2, .seconds(8)), (3, .seconds(16)), (4, .seconds(32)), (5, .seconds(60)), (6, .seconds(60)), (40, .seconds(60)), (Int.max, .seconds(60)),
        ]
        for testCase in delaysByFailureCount {
            XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .zero, consecutiveFailures: testCase.failures), testCase.delay, "\(testCase.failures) failures")
        }
    }

    func testAutosaveAfterFailuresNeverWaitsLessThanAfterTheSlowSave() {
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .seconds(7), consecutiveFailures: 1), .seconds(30))
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .seconds(7), consecutiveFailures: 2), .seconds(30))
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .seconds(7), consecutiveFailures: 4), .seconds(32))
        XCTAssertEqual(PDFSession.autosaveDelay(afterSaveTaking: .seconds(2), consecutiveFailures: 1), .seconds(20))
    }

    func testTheBaseAutosaveDelayIsTwoSeconds() {
        XCTAssertEqual(PDFSession.autosaveDelay, .seconds(2))
    }

    // MARK: History

    private func makePDF() throws -> URL {
        let location = directory.appendingPathComponent("Notebook.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1).write(to: location)
        return location
    }

    func testTheHistoryKeepsOneHundredSteps() async throws {
        XCTAssertEqual(PDFSession.maximumUndoSteps, 100)
        let session = try await PDFSession.open(makePDF())
        XCTAssertEqual(session.undoManager.levelsOfUndo, 100)
        session.undoManager.groupsByEvent = false
        // Each turn of the page is one step; the first of 101 is dropped.
        for _ in 0..<101 {
            session.undoManager.beginUndoGrouping()
            try session.rotatePages([0], clockwise: true)
            session.undoManager.endUndoGrouping()
        }
        XCTAssertEqual(session.document.page(at: 0)?.rotation, 90 * 101 % 360)
        var undoneStepCount = 0
        while session.undoAvailability.canUndo {
            session.undoAvailability.undo()
            undoneStepCount += 1
            XCTAssertLessThanOrEqual(undoneStepCount, 101)
        }
        XCTAssertEqual(undoneStepCount, 100)
        XCTAssertEqual(session.document.page(at: 0)?.rotation, 90, "The first turn can no longer be undone.")
    }
}
