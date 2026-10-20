import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// How long PDF autosave waits and how many steps the history keeps. The delays are a
/// table: `min(max(2 s, 10 × last save), 30 s)`, and after failed saves `2 s × 2^min(failures, 5)`
/// capped at 60 s (never shorter than the first). The delays are a pure function, tested as a
/// table; the session's own autosave sleeps on a `ManualClock`, so what it does at each delay is
/// tested without waiting.
@MainActor
final class PDFSessionAutosavePolicyTests: XCTestCase {
    private var directory: URL!
    private let clock = ManualClock()

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "PDFSessionAutosavePolicy", for: self).root
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

    // MARK: What autosave does at each delay

    /// Every save into the folder fails until it is writable again. It is made writable when the
    /// test ends, so the folder can be removed (this runs before the temporary vault's removal).
    private func makeFolderReadOnly() throws {
        let folder = directory!
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
    }

    private func makeFolderWritable() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    }

    private func savedRotation(of location: URL) throws -> Int {
        try XCTUnwrap(PDFDocument(url: location)?.page(at: 0)).rotation
    }

    func testAutosaveWritesTwoSecondsAfterAnEditAndNotBefore() async throws {
        let location = try makePDF()
        let session = try await PDFSession.open(location, clock: clock)
        try session.rotatePages([0], clockwise: true)
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(2)])

        clock.advance(by: .milliseconds(1_999))
        await ManualClock.letResumedTasksRun()
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(try savedRotation(of: location), 0, "Nothing is written before the delay has passed.")

        clock.advance(by: .milliseconds(1))
        try await waitUntil("the autosave writes the edit") { !session.hasUnsavedChanges }
        XCTAssertEqual(try savedRotation(of: location), 90)
        XCTAssertEqual(clock.pendingSleepCount, 0)
    }

    func testFailedAutosavesAreRetriedAfterFourEightSixteenThirtyTwoThenSixtySeconds() async throws {
        let location = try makePDF()
        let session = try await PDFSession.open(location, clock: clock)
        try makeFolderReadOnly()
        try session.rotatePages([0], clockwise: true)
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(2)])

        // Each wait ends in a failed save, which schedules the next, longer wait.
        let retryDelays: [Duration] = [.seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60), .seconds(60)]
        var delayJustWaited = Duration.seconds(2)
        for retryDelay in retryDelays {
            clock.advance(by: delayJustWaited)
            try await clock.awaitPendingSleepers()
            XCTAssertEqual(clock.pendingSleepDurations, [retryDelay], "After waiting \(delayJustWaited) and failing again.")
            XCTAssertTrue(session.hasFailedSave)
            delayJustWaited = retryDelay
        }

        try makeFolderWritable()
        clock.advance(by: .seconds(60))
        try await waitUntil("the retry saves the edit") { !session.hasUnsavedChanges }
        XCTAssertEqual(try savedRotation(of: location), 90)
        XCTAssertFalse(session.hasFailedSave)

        // A save that worked ends the back-off: the next edit waits the base delay again.
        try session.rotatePages([0], clockwise: true)
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(2)])
    }

    func testAConflictStopsAutosaveBeforeItWritesAnything() async throws {
        let location = try makePDF()
        let session = try await PDFSession.open(location, clock: clock)
        try session.rotatePages([0], clockwise: true)
        try await clock.awaitPendingSleepers()

        session.hasExternalConflict = true
        clock.advance(by: .seconds(2))
        await ManualClock.letResumedTasksRun()

        XCTAssertEqual(clock.pendingSleepCount, 0, "No later autosave is scheduled while the conflict waits for the user's choice.")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertFalse(session.hasFailedSave, "No save was attempted.")
        XCTAssertEqual(try savedRotation(of: location), 0)
    }

    func testAConflictThatArisesWhileWaitingToRetryStopsTheRetries() async throws {
        let location = try makePDF()
        let session = try await PDFSession.open(location, clock: clock)
        try makeFolderReadOnly()
        try session.rotatePages([0], clockwise: true)
        try await clock.awaitPendingSleepers()
        clock.advance(by: .seconds(2))
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(4)])
        try makeFolderWritable()

        session.hasExternalConflict = true
        clock.advance(by: .seconds(4))
        await ManualClock.letResumedTasksRun()

        XCTAssertEqual(clock.pendingSleepCount, 0)
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(try savedRotation(of: location), 0, "The retry did not write over the other app's file.")
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
