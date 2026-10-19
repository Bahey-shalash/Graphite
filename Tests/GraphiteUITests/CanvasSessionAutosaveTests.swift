import XCTest
import CoreGraphics
import GraphiteCore
@testable import GraphiteUI

/// Canvas autosave fires 900 ms after the last edit or keystroke; each pause in typing
/// commits one "Edit Text" step. The autosave task sleeps on the real clock, so these tests
/// pin the delay and drive the save it runs (`save()`) instead of waiting for it.
@MainActor
final class CanvasSessionAutosaveTests: XCTestCase {
    private var vault: URL!
    private var store: VaultStore!
    private var canvasPath: VaultPath!

    private let board = "{\n\t\"nodes\":[\n"
        + "\t\t{\"id\":\"1000000000000001\",\"type\":\"text\",\"text\":\"First\",\"x\":0,\"y\":0,\"width\":250,\"height\":200}\n"
        + "\t]\n}"

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasSessionAutosave-\(UUID().uuidString)")
        canvasPath = try VaultPath("Board.canvas")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try Data(board.utf8).write(to: vault.appendingPathComponent(canvasPath.rawValue))
        store = VaultStore(root: vault)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func openSession() async throws -> CanvasSession {
        let session = try CanvasSession(path: canvasPath, snapshot: try await store.read(canvasPath), store: store) { _ in }
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
