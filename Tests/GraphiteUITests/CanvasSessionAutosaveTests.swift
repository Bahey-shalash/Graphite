import XCTest
import CoreGraphics
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Canvas autosave fires 900 ms after the last edit or keystroke; each pause in typing
/// commits one "Edit Text" step. The session's autosave sleeps on a `ManualClock`, so the
/// boundary is tested at 899 and 900 ms without waiting, and the other tests drive the save
/// the autosave runs (`save()`) directly.
@MainActor
final class CanvasSessionAutosaveTests: XCTestCase {
    private var vault: URL!
    private var store: VaultStore!
    private var canvasPath: VaultPath!
    private let clock = ManualClock()

    private let board = "{\n\t\"nodes\":[\n"
        + "\t\t{\"id\":\"1000000000000001\",\"type\":\"text\",\"text\":\"First\",\"x\":0,\"y\":0,\"width\":250,\"height\":200}\n"
        + "\t]\n}"

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "CanvasSessionAutosave", for: self).root
        canvasPath = try VaultPath("Board.canvas")
        try Data(board.utf8).write(to: vault.appendingPathComponent(canvasPath.rawValue))
        store = VaultStore(root: vault)
    }

    private func openSession() async throws -> CanvasSession {
        let session = try CanvasSession(path: canvasPath, snapshot: try await store.read(canvasPath), store: store, clock: clock) { _ in }
        session.viewSize = CGSize(width: 1000, height: 800)
        session.isWriting = true
        session.undoManager.groupsByEvent = false
        return session
    }

    private func fileText() throws -> String {
        try String(contentsOf: vault.appendingPathComponent(canvasPath.rawValue), encoding: .utf8)
    }

    private func text(of session: CanvasSession) -> String? {
        guard case .text(let text)? = session.file.node(withIdentifier: "1000000000000001")?.content else { return nil }
        return text
    }

    func testAutosaveWaitsNineHundredMillisecondsAfterTheLastEdit() {
        XCTAssertEqual(CanvasSession.autosaveDelay, .milliseconds(900))
    }

    func testAnEditIsWrittenOnceAtNineHundredMillisecondsAndNotAtEightHundredNinetyNine() async throws {
        let session = try await openSession()
        session.perform([.setText("First, edited", nodeIdentifier: "1000000000000001")], named: "Edit Text")
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.milliseconds(900)])

        clock.advance(by: .milliseconds(899))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(try fileText(), board, "Nothing is written before the delay has passed.")
        XCTAssertTrue(session.hasUnsavedChanges)

        clock.advance(by: .milliseconds(1))
        try await waitUntil("the autosave writes the edit") { !session.hasUnsavedChanges }
        XCTAssertTrue(try fileText().contains("\"text\":\"First, edited\""))
        XCTAssertEqual(clock.pendingSleepCount, 0, "One edit is one autosave.")
    }

    func testEachEditRestartsTheNineHundredMillisecondWait() async throws {
        let session = try await openSession()
        session.perform([.setText("First, edited", nodeIdentifier: "1000000000000001")], named: "Edit Text")
        try await clock.awaitPendingSleepers()
        clock.advance(by: .milliseconds(600))
        session.perform([.setText("First, edited again", nodeIdentifier: "1000000000000001")], named: "Edit Text")
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.milliseconds(900)], "The first wait was replaced, not kept.")

        clock.advance(by: .milliseconds(899))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(try fileText(), board, "1,499 ms after the first edit is 899 ms after the last.")

        clock.advance(by: .milliseconds(1))
        try await waitUntil("the autosave writes the last edit") { !session.hasUnsavedChanges }
        XCTAssertTrue(try fileText().contains("\"text\":\"First, edited again\""))
    }

    func testTextTypedInACardIsWrittenNineHundredMillisecondsAfterTheLastKeystroke() async throws {
        let session = try await openSession()
        session.beginEditingText(of: "1000000000000001")
        session.updateTextEdit("First, typed")
        try await clock.awaitPendingSleepers()

        clock.advance(by: .milliseconds(899))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(try fileText(), board)

        clock.advance(by: .milliseconds(1))
        try await waitUntil("the autosave writes the typed text") { try fileText().contains("\"text\":\"First, typed\"") }
        XCTAssertEqual(session.undoAvailability.undoActionName, "Edit Text")
    }

    func testTypingWritesNothingToTheFileUntilTheSaveThatAutosaveRuns() async throws {
        let session = try await openSession()
        session.beginEditingText(of: "1000000000000001")
        session.updateTextEdit("First, edited")

        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(try fileText(), board, "Nothing is written while typing.")
        XCTAssertEqual(text(of: session), "First", "The card takes the text at the pause.")

        try await session.save()

        XCTAssertEqual(text(of: session), "First, edited")
        XCTAssertTrue(try fileText().contains("\"text\":\"First, edited\""))
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    func testKeystrokesWithoutAPauseAreOneStepAndEachPauseCommitsOneEditTextStep() async throws {
        let session = try await openSession()
        session.beginEditingText(of: "1000000000000001")
        for typed in ["First a", "First ab", "First abc"] { session.updateTextEdit(typed) }
        try await session.save()
        XCTAssertEqual(session.undoAvailability.undoActionName, "Edit Text")

        session.updateTextEdit("First abc d")
        session.updateTextEdit("First abc de")
        try await session.save()
        XCTAssertEqual(text(of: session), "First abc de")

        session.undoAvailability.undo()
        XCTAssertEqual(text(of: session), "First abc", "One step took back what was typed after the second pause.")
        XCTAssertEqual(session.undoAvailability.undoActionName, "Edit Text")
        session.undoAvailability.undo()
        XCTAssertEqual(text(of: session), "First", "One step took back what was typed before the first pause.")
        XCTAssertFalse(session.undoAvailability.canUndo)
    }

    func testASaveWithNothingTypedAndNothingChangedWritesNothing() async throws {
        let session = try await openSession()
        session.beginEditingText(of: "1000000000000001")
        try await session.save()
        XCTAssertEqual(try fileText(), board)
        XCTAssertFalse(session.undoAvailability.canUndo)
    }
}
