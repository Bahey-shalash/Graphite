import XCTest
import AVFoundation
import Synchronization
import GraphiteCore
@testable import GraphiteApple

/// Recording publication and recovery, driven without a microphone: the controller adopts
/// an AAC file written by AVAudioFile, as if it had just recorded it.
@MainActor
final class AppleRecordingAccessRecordingTests: XCTestCase {
    private var workFolder: URL!
    private var recoveryFolder: URL!
    private var attachmentsFolder: URL!

    override func setUp() async throws {
        workFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        recoveryFolder = workFolder.appendingPathComponent("Recovery", isDirectory: true)
        attachmentsFolder = workFolder.appendingPathComponent("Vault/attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachmentsFolder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: recoveryFolder.path)
        try? FileManager.default.removeItem(at: workFolder)
    }

    /// Half a second of a quiet tone, in the same AAC-in-M4A format the recorder writes.
    private func makeRecoveryRecording() throws -> URL {
        let recordingURL = recoveryFolder.appendingPathComponent("\(UUID().uuidString).m4a")
        let audioFile = try AVAudioFile(forWriting: recordingURL, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ])
        let frameCount = AVAudioFrameCount(22_050)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frameIndex in 0..<Int(frameCount) { samples[frameIndex] = sin(Float(frameIndex) * 0.06) * 0.2 }
        try audioFile.write(from: buffer)
        audioFile.close()
        return recordingURL
    }

    private func waitUntil(_ condition: () -> Bool, timeoutSeconds: Double = 10) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else { return XCTFail("Timed out waiting for the recording controller.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testSuccessfulRetryClearsTheEarlierFailureMessage() async throws {
        let recordingURL = try makeRecoveryRecording()
        let destination = attachmentsFolder.appendingPathComponent("Lecture.m4a")
        let controller = RecordingController()
        controller.adoptRecording(at: recordingURL, destination: destination, state: .failed, message: "Recording did not finalize successfully. Your recording remains at \(recordingURL.path).")

        await controller.retryPublication()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.message)
        XCTAssertNil(controller.recoveryURL)
        XCTAssertEqual(controller.lastCompletedURL, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordingURL.path))
    }

    func testNewRecordingCannotReplaceAFailedRecordingUntilItIsDiscarded() async throws {
        let recordingURL = try makeRecoveryRecording()
        let controller = RecordingController()
        controller.adoptRecording(at: recordingURL, destination: attachmentsFolder.appendingPathComponent("Lecture.m4a"), state: .failed, message: "Saving failed.")
        XCTAssertTrue(controller.state.canStart)
        XCTAssertFalse(controller.canStartRecording)

        // Returns before asking for the microphone, and keeps the pending recording.
        let nextDestination = attachmentsFolder.appendingPathComponent("Next Lecture.m4a")
        await controller.start(destination: nextDestination, manifest: RecordingRecoveryManifest(vaultIdentifier: nil, destinationPath: "attachments/Next Lecture.m4a", notePath: nil, startedAt: .now))
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(controller.recoveryURL, recordingURL)
        XCTAssertEqual(controller.message, "Saving failed.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingURL.path))

        controller.discardRecoveredRecording()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.recoveryURL)
        XCTAssertNil(controller.message)
        XCTAssertTrue(controller.canStartRecording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordingURL.path))
    }

    func testRetryCanPublishToAReplacementAfterTheFolderWasRenamed() async throws {
        let recordingURL = try makeRecoveryRecording()
        let controller = RecordingController()
        controller.adoptRecording(at: recordingURL, destination: attachmentsFolder.appendingPathComponent("Lecture.m4a"), state: .failed, message: "Saving failed.")
        let renamedFolder = workFolder.appendingPathComponent("Vault/Files", isDirectory: true)
        try FileManager.default.moveItem(at: attachmentsFolder, to: renamedFolder)

        await controller.retryPublication()
        XCTAssertEqual(controller.state, .failed)
        let message = try XCTUnwrap(controller.message)
        XCTAssertTrue(message.contains("“attachments”"), message)
        XCTAssertFalse(message.contains("doesn’t exist"), "The folder, not the recording, is missing: \(message)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingURL.path))

        let replacement = renamedFolder.appendingPathComponent("Lecture.m4a")
        await controller.retryPublication(to: replacement)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.lastCompletedURL, replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.path))
    }

    func testTakenNameIsReportedAsTakenAndKeepsTheOtherFile() async throws {
        let recordingURL = try makeRecoveryRecording()
        let destination = attachmentsFolder.appendingPathComponent("Lecture.m4a")
        try Data("someone else's file".utf8).write(to: destination)
        let controller = RecordingController()
        controller.adoptRecording(at: recordingURL, destination: destination, state: .failed, message: "Saving failed.")

        await controller.retryPublication()

        XCTAssertEqual(controller.state, .failed)
        let message = try XCTUnwrap(controller.message)
        XCTAssertTrue(message.contains("already contains a file named “Lecture.m4a”"), message)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "someone else's file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingURL.path))
    }

    func testRecordingIsSavedEvenWhenItsRecoveryCopyCannotBeDeleted() async throws {
        let recordingURL = try makeRecoveryRecording()
        let destination = attachmentsFolder.appendingPathComponent("Lecture.m4a")
        // A read-only folder keeps its files from being deleted.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: recoveryFolder.path)
        let controller = RecordingController()
        controller.adoptRecording(at: recordingURL, destination: destination, state: .failed, message: "Saving failed.")

        await controller.retryPublication()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.message)
        XCTAssertNil(controller.recoveryURL)
        XCTAssertEqual(controller.lastCompletedURL, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingURL.path), "The recovery copy was expected to be undeletable.")
    }

    func testStopFinishesEvenWhenTheRecorderNeverReportsFinishing() async throws {
        let recordingURL = try makeRecoveryRecording()
        let destination = attachmentsFolder.appendingPathComponent("Lecture.m4a")
        let controller = RecordingController()
        controller.finalizationTimeout = .milliseconds(50)
        // No recorder exists, so no finish callback can arrive.
        controller.adoptRecording(at: recordingURL, destination: destination, state: .paused)

        controller.stop()
        XCTAssertEqual(controller.state, .finalizing)
        try await waitUntil { controller.state != .finalizing }

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.lastCompletedURL, destination)
        XCTAssertFalse(controller.state.isActive)
    }

    func testAbandonedRecorderLeavesTheAudioToSaveAgain() async throws {
        let recordingURL = try makeRecoveryRecording()
        let destination = attachmentsFolder.appendingPathComponent("Lecture.m4a")
        let controller = RecordingController()
        controller.adoptRecording(at: recordingURL, destination: destination, state: .recording)

        controller.abandonRecorder(reason: "Audio encoding failed.")

        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(controller.recoveryURL, recordingURL)
        XCTAssertEqual(controller.message, "Audio encoding failed. The audio recorded so far has been kept.")
        await controller.retryPublication()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testAbandoningIsIgnoredOnceNothingIsRecording() async throws {
        let controller = RecordingController()
        controller.abandonRecorder(reason: "Audio services restarted, so the recording stopped.")
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.message)
    }
}

@MainActor
final class AppleRecordingAccessFolderTests: XCTestCase {
    private var parentFolder: URL!

    override func setUp() async throws {
        parentFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parentFolder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: parentFolder)
    }

    func testRelativePathCoversTheEnclosingFolderItselfButNotItsSiblings() throws {
        let documents = parentFolder.appendingPathComponent("Documents", isDirectory: true)
        XCTAssertEqual(VaultLocator.relativePath(of: documents, inside: documents), "")
        XCTAssertEqual(VaultLocator.relativePath(of: documents.appendingPathComponent("Courses/Physics", isDirectory: true), inside: documents), "Courses/Physics")
        XCTAssertNil(VaultLocator.relativePath(of: parentFolder.appendingPathComponent("Documents 2", isDirectory: true), inside: documents))
        XCTAssertNil(VaultLocator.relativePath(of: parentFolder, inside: documents))
    }

    func testNewVaultWithoutAParentIsCreatedInTheGivenDocumentsFolder() throws {
        let location = try VaultLocator.createVaultFolder(named: "Chemistry", in: nil, applicationDocumentsFolder: parentFolder)
        XCTAssertEqual(location, VaultLocation(anchor: .applicationDocuments, relativePath: "Chemistry"))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentFolder.appendingPathComponent("Chemistry").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    #if !os(macOS)
    func testGraphitesOwnFolderPickedAsAVaultIsRememberedByPath() throws {
        let location = try VaultLocator.location(forPickedFolder: parentFolder, applicationDocumentsFolder: parentFolder)
        XCTAssertEqual(location, VaultLocation(anchor: .applicationDocuments, relativePath: ""))
    }

    func testNewVaultInsideGraphitesFolderIsRememberedByPath() throws {
        let coursesFolder = parentFolder.appendingPathComponent("Courses", isDirectory: true)
        try FileManager.default.createDirectory(at: coursesFolder, withIntermediateDirectories: true)
        let location = try VaultLocator.createVaultFolder(named: "Physics", in: coursesFolder, applicationDocumentsFolder: parentFolder)
        XCTAssertEqual(location, VaultLocation(anchor: .applicationDocuments, relativePath: "Courses/Physics"))
        let topLevel = try VaultLocator.createVaultFolder(named: "Chemistry", in: parentFolder, applicationDocumentsFolder: parentFolder)
        XCTAssertEqual(topLevel, VaultLocation(anchor: .applicationDocuments, relativePath: "Chemistry"))
    }
    #endif

    func testBackgroundAccessFindsTheSameFolder() async throws {
        let vaultFolder = parentFolder.appendingPathComponent("Biology", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: false)
        let location = try VaultLocator.location(forPickedFolder: vaultFolder)
        let opened = try await VaultLocator.accessInBackground(location)
        XCTAssertEqual(opened.access.root.standardizedFileURL.resolvingSymlinksInPath(), vaultFolder.standardizedFileURL.resolvingSymlinksInPath())

        try FileManager.default.removeItem(at: vaultFolder)
        do {
            _ = try await VaultLocator.accessInBackground(location)
            XCTFail("A deleted vault folder must not open.")
        } catch {}
    }
}

final class AppleRecordingAccessVaultMonitorTests: XCTestCase {
    private var parentFolder: URL!

    override func setUp() async throws {
        parentFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parentFolder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: parentFolder)
    }

    func testRenamedVaultFolderIsReportedAndFollowed() throws {
        let vaultFolder = parentFolder.appendingPathComponent("Vault", isDirectory: true)
        let renamedFolder = parentFolder.appendingPathComponent("Vault Renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: false)
        let moveReported = expectation(description: "The vault's move is reported")
        let reportedMoves = Mutex<[URL?]>([])
        let monitor = VaultMonitor(root: vaultFolder, onChange: { _ in }, onVaultMove: { newLocation in
            reportedMoves.withLock { moves in moves.append(newLocation) }
            moveReported.fulfill()
        })
        defer { monitor.stop() }

        var coordinationError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: vaultFolder, options: .forMoving, writingItemAt: renamedFolder, options: .forReplacing, error: &coordinationError) { source, destination in
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
            } catch { moveError = error }
        }
        XCTAssertNil(coordinationError)
        XCTAssertNil(moveError)
        wait(for: [moveReported], timeout: 10)

        let reportedLocation = try XCTUnwrap(reportedMoves.withLock { moves in moves.first } ?? nil)
        XCTAssertEqual(reportedLocation.standardizedFileURL.resolvingSymlinksInPath().path, renamedFolder.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(monitor.presentedItemURL?.standardizedFileURL.resolvingSymlinksInPath().path, renamedFolder.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testDeletedVaultFolderIsReportedWithoutALocation() {
        let reportedMoves = Mutex<[URL?]>([])
        let monitor = VaultMonitor(root: parentFolder, onChange: { _ in }, onVaultMove: { newLocation in
            reportedMoves.withLock { moves in moves.append(newLocation) }
        })
        defer { monitor.stop() }
        var deletionError: Error? = GraphiteError.conflict
        monitor.accommodatePresentedItemDeletion { error in deletionError = error }
        XCTAssertNil(deletionError)
        XCTAssertEqual(reportedMoves.withLock { moves in moves }, [nil])
    }

    func testGraphitesOwnStagingFilesAreNotReportedAsVaultChanges() {
        let reportedChanges = Mutex<[URL?]>([])
        let monitor = VaultMonitor(root: parentFolder) { changedLocation in
            reportedChanges.withLock { changes in changes.append(changedLocation) }
        }
        defer { monitor.stop() }
        let stagingFile = parentFolder.appendingPathComponent(".\(UUID().uuidString).tmp")
        let note = parentFolder.appendingPathComponent("Lecture.m4a")
        let hiddenNote = parentFolder.appendingPathComponent(".draft.tmp")

        monitor.presentedSubitemDidAppear(at: stagingFile)
        monitor.presentedSubitemDidChange(at: stagingFile)
        monitor.presentedSubitem(at: stagingFile, didMoveTo: note)
        monitor.accommodatePresentedSubitemDeletion(at: stagingFile) { _ in }
        monitor.presentedSubitemDidChange(at: hiddenNote)

        XCTAssertEqual(reportedChanges.withLock { changes in changes }, [note, hiddenNote])
    }
}
