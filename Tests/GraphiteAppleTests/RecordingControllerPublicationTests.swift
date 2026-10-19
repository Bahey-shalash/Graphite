import XCTest
import AVFoundation
import GraphiteCore
@testable import GraphiteApple

/// Saving a finished recording into the vault: nothing already there is overwritten, the
/// folder is checked first, the recovery copy is removed only once the file is in place, and a
/// recording that could not be saved blocks a new one because it is the only copy.
@MainActor
final class RecordingControllerPublicationTests: XCTestCase {
    private var workFolder: URL!
    private var recoveryFolder: URL!
    private var attachmentsFolder: URL!

    override func setUp() async throws {
        workFolder = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingPublication-\(UUID().uuidString)", isDirectory: true)
        recoveryFolder = workFolder.appendingPathComponent("Recovery", isDirectory: true)
        attachmentsFolder = workFolder.appendingPathComponent("Vault/attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachmentsFolder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workFolder) // Best-effort removal of a temporary folder.
    }

    /// Half a second of a quiet tone as an M4A in the recovery folder.
    private func makeRecoveryRecording() throws -> URL {
        let location = recoveryFolder.appendingPathComponent("\(UUID().uuidString).m4a")
        let file = try AVAudioFile(forWriting: location, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
        let frameCount = AVAudioFrameCount(22_050)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) { samples[frame] = sin(Float(frame) * 0.06) * 0.2 }
        try file.write(from: buffer)
        file.close()
        return location
    }

    func testAFileAlreadyNamedLikeTheRecordingSurvivesAndTheRecordingStaysTheOnlyCopyThatBlocksANewOne() async throws {
        let recording = try makeRecoveryRecording()
        let recordingBytes = try Data(contentsOf: recording)
        let destination = attachmentsFolder.appendingPathComponent("Lecture.m4a")
        try Data("someone else's file".utf8).write(to: destination)
        let controller = RecordingController()
        controller.adoptRecording(at: recording, destination: destination, state: .failed, message: "Saving failed.")

        await controller.retryPublication()

        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "someone else's file", "Publication never overwrites.")
        XCTAssertEqual(try Data(contentsOf: recording), recordingBytes, "The recording is still at its recovery place.")
        XCTAssertEqual(controller.recoveryURL, recording)
        XCTAssertNil(controller.lastCompletedURL)
        XCTAssertFalse(controller.canStartRecording, "A failed recording is the only copy of that lecture.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: attachmentsFolder.path), ["Lecture.m4a"], "No staging file is left beside it.")
    }

    func testAMissingFolderIsReportedBeforeAnythingIsCopiedAndTheRecordingIsKept() async throws {
        let recording = try makeRecoveryRecording()
        let missingFolder = workFolder.appendingPathComponent("Vault/renamed away", isDirectory: true)
        let controller = RecordingController()
        controller.adoptRecording(at: recording, destination: missingFolder.appendingPathComponent("Lecture.m4a"), state: .failed, message: "Saving failed.")

        await controller.retryPublication()

        XCTAssertEqual(controller.state, .failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingFolder.path), "The folder is not created for it.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path))
        XCTAssertFalse(controller.canStartRecording)
    }

    func testTheRecoveryCopyIsRemovedOnlyAfterTheFileIsInPlaceAndThenANewRecordingMayStart() async throws {
        let recording = try makeRecoveryRecording()
        let destination = attachmentsFolder.appendingPathComponent("Lecture.m4a")
        let controller = RecordingController()
        controller.adoptRecording(at: recording, destination: destination, state: .failed, message: "Saving failed.")
        XCTAssertFalse(controller.canStartRecording)

        await controller.retryPublication()

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.path))
        XCTAssertNil(controller.recoveryURL)
        XCTAssertTrue(controller.canStartRecording)
    }
}
