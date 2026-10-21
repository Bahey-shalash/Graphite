import XCTest
import GraphiteCore
@testable import GraphiteApple
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

/// One recording and one Read Aloud at a time across the windows of a process: the device
/// has one microphone, one audio output and one Now Playing entry. Starting one in a second
/// window says where the first is running.
@MainActor
final class OneActivityAcrossWindowsTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
        processServices.preferences.setEnabled(.readAloud, true)
    }

    private func makeWindow(on vault: URL) async throws -> WorkspaceModel {
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await window.openFolderAsVault(vault)
        return window
    }

    private func makeVault(named name: String) throws -> URL {
        let vault = try TemporaryVault.make(prefix: name, for: self).root
        try Data("A note to read.".utf8).write(to: vault.appendingPathComponent("Note.md"))
        return vault.resolvingSymlinksInPath()
    }

    func testReadAloudStartedInASecondWindowSaysWhereTheFirstReads() async throws {
        let vault = try makeVault(named: "ReadingVault")
        let firstWindow = try await makeWindow(on: vault)
        let secondWindow = try await makeWindow(on: vault)
        let firstReader = try XCTUnwrap(firstWindow.readAloud)
        let secondReader = try XCTUnwrap(secondWindow.readAloud)
        XCTAssertNotIdentical(firstReader, secondReader, "Each window has its own controls.")

        firstReader.readMarkdown("A note to read.", path: try VaultPath("Note.md"))
        secondReader.readMarkdown("A note to read.", path: try VaultPath("Note.md"))

        XCTAssertTrue(firstReader.isReading)
        XCTAssertFalse(secondReader.isReading)
        XCTAssertEqual(secondReader.errorMessage, OtherWindowActivity.readingAloud(windowName: firstWindow.windowName).errorDescription)
        XCTAssertTrue(secondReader.errorMessage?.contains(firstWindow.title) == true, "The message names the window.")

        firstReader.clear()
        secondReader.readMarkdown("A note to read.", path: try VaultPath("Note.md"))

        XCTAssertTrue(secondReader.isReading, "Once the first window stops, the second may read.")
        XCTAssertNil(secondReader.errorMessage)
    }

    func testARecordingInOneWindowRefusesARecordingAndReadAloudInAnother() async throws {
        let firstWindow = try await makeWindow(on: try makeVault(named: "LectureVault"))
        let secondWindow = try await makeWindow(on: try makeVault(named: "OtherVault"))
        let recordingFolder = try TemporaryVault.make(prefix: "Recording", for: self).root
        firstWindow.recording.adoptRecording(at: recordingFolder.appendingPathComponent("recording.m4a"),
                                             destination: recordingFolder.appendingPathComponent("Lecture.m4a"), state: .recording)

        XCTAssertTrue(secondWindow.isRecordingInAnyWindow)
        await secondWindow.startRecording()

        XCTAssertEqual(secondWindow.recording.state, .idle)
        XCTAssertEqual(secondWindow.errorMessage, OtherWindowActivity.recording(windowName: firstWindow.windowName).errorDescription)
        let secondReader = try XCTUnwrap(secondWindow.readAloud)
        secondReader.readMarkdown("A note to read.", path: try VaultPath("Note.md"))
        XCTAssertFalse(secondReader.isReading)
        XCTAssertEqual(secondReader.errorMessage, OtherWindowActivity.recording(windowName: firstWindow.windowName).errorDescription)
    }

    func testAClosedWindowNoLongerHoldsWhatItRan() async throws {
        let vault = try makeVault(named: "ClosingVault")
        let firstWindow = try await makeWindow(on: vault)
        let secondWindow = try await makeWindow(on: vault)
        try XCTUnwrap(firstWindow.readAloud).readMarkdown("A note to read.", path: try VaultPath("Note.md"))

        firstWindow.windowDidClose()
        let secondReader = try XCTUnwrap(secondWindow.readAloud)
        secondReader.readMarkdown("A note to read.", path: try VaultPath("Note.md"))

        XCTAssertTrue(secondReader.isReading)
        XCTAssertEqual(processServices.openWindows.all.count, 1)
    }
}
