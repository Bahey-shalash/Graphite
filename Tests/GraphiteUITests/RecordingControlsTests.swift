import XCTest
import SwiftUI
import AVFoundation
import GraphiteCore
@testable import GraphiteIndex
@testable import GraphiteApple
@testable import GraphiteUI

/// The recording control's choices and wording, the camera preview's place and size, and
/// video recordings in the workspace: where they are saved and how they are recovered.
@MainActor
final class RecordingControlsTests: XCTestCase {
    private var temporaryFolders: [URL] = []

    override func tearDown() async throws {
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) }
        temporaryFolders = []
    }

    // MARK: The control

    func testTheOtherCameraIsOfferedOnlyWhenThereIsOne() {
        XCTAssertEqual(RecordingControlModel.cameraToSwitchTo(from: .back, available: [.back, .front]), .front)
        XCTAssertEqual(RecordingControlModel.cameraToSwitchTo(from: .front, available: [.back, .front]), .back)
        XCTAssertNil(RecordingControlModel.cameraToSwitchTo(from: .back, available: [.back]))
        XCTAssertNil(RecordingControlModel.cameraToSwitchTo(from: .back, available: []))
    }

    func testOnlyMessagesThatReportWhatHappenedCanBeDismissed() {
        XCTAssertTrue(RecordingControlModel.canDismissMessage(state: .recording, message: "The video was paused for 5 seconds and is recording again.", hasRecordingToSave: true))
        XCTAssertTrue(RecordingControlModel.canDismissMessage(state: .idle, message: "Storage is almost full, so the video recording stopped.", hasRecordingToSave: false))
        XCTAssertTrue(RecordingControlModel.canDismissMessage(state: .failed, message: "This device has no camera Graphite can record with.", hasRecordingToSave: false))
        XCTAssertFalse(RecordingControlModel.canDismissMessage(state: .interrupted, message: "Another app is using the camera.", hasRecordingToSave: true), "A paused recording waits for a decision.")
        XCTAssertFalse(RecordingControlModel.canDismissMessage(state: .failed, message: "Saving failed.", hasRecordingToSave: true), "A recording that was not saved waits for Try Saving Again or Discard.")
        XCTAssertFalse(RecordingControlModel.canDismissMessage(state: .recording, message: nil, hasRecordingToSave: true))
    }

    func testTheControlDescribesTheRecordingToVoiceOver() {
        XCTAssertEqual(RecordingControlModel.accessibilityDescription(state: .recording, kind: .video, hasMessage: false), "Video recording")
        XCTAssertEqual(RecordingControlModel.accessibilityDescription(state: .recording, kind: .video, hasMessage: true), "Video recording, with a message")
        XCTAssertEqual(RecordingControlModel.accessibilityDescription(state: .interrupted, kind: .video, hasMessage: true), "Video recording paused")
        XCTAssertEqual(RecordingControlModel.accessibilityDescription(state: .paused, kind: .audio, hasMessage: false), "Recording paused")
        XCTAssertEqual(RecordingControlModel.accessibilityDescription(state: .failed, kind: .video, hasMessage: true), "Recording message")
    }

    func testEveryInterruptionIsExplainedWithoutJargon() {
        let reasons: [CaptureInterruptionReason] = [.applicationOffScreen, .cameraInUseByAnotherApplication, .microphoneInUseByAnotherApplication,
                                                    .cameraUnavailableWhileSharingScreen, .systemPressure, .captureStopped, .unknown]
        for reason in reasons {
            XCTAssertFalse(reason.explanation.isEmpty)
            XCTAssertFalse(reason.explanation.localizedCaseInsensitiveContains("session"), reason.explanation)
            XCTAssertFalse(reason.explanation.localizedCaseInsensitiveContains("AVFoundation"), reason.explanation)
        }
        XCTAssertTrue(CaptureInterruptionReason.applicationOffScreen.explanation.contains("not even sound"), "The person is told that nothing at all is recorded meanwhile.")
    }

    func testMissingHardwareOffersNoWayToSettings() {
        XCTAssertTrue(CaptureAccessProblem.cameraDenied.canBeChangedInSettings)
        XCTAssertTrue(CaptureAccessProblem.microphoneDenied.canBeChangedInSettings)
        XCTAssertFalse(CaptureAccessProblem.noCamera.canBeChangedInSettings)
        XCTAssertFalse(CaptureAccessProblem.noMicrophone.canBeChangedInSettings)
    }

    // MARK: The preview

    func testThePreviewIsShownOnlyForAVideoThatIsBeingRecorded() {
        XCTAssertTrue(RecordingPreviewLayout.isShown(kind: .video, state: .recording, showsPreview: true))
        XCTAssertTrue(RecordingPreviewLayout.isShown(kind: .video, state: .paused, showsPreview: true))
        XCTAssertTrue(RecordingPreviewLayout.isShown(kind: .video, state: .interrupted, showsPreview: true))
        XCTAssertFalse(RecordingPreviewLayout.isShown(kind: .video, state: .recording, showsPreview: false), "Hidden by the person.")
        XCTAssertFalse(RecordingPreviewLayout.isShown(kind: .audio, state: .recording, showsPreview: true))
        XCTAssertFalse(RecordingPreviewLayout.isShown(kind: .video, state: .finalizing, showsPreview: true))
        XCTAssertFalse(RecordingPreviewLayout.isShown(kind: .video, state: .idle, showsPreview: true))
    }

    func testThePreviewTakesTheCamerasShapeAndFitsItsSpace() {
        let space = CGSize(width: 1_000, height: 700)
        let landscape = RecordingPreviewLayout.size(width: 320, aspectRatio: 16.0 / 9.0, in: space)
        XCTAssertEqual(landscape.width, 320)
        XCTAssertEqual(landscape.height, 180, accuracy: 0.01)
        let portrait = RecordingPreviewLayout.size(width: 320, aspectRatio: 9.0 / 16.0, in: space)
        XCTAssertEqual(portrait.width / portrait.height, 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(RecordingPreviewLayout.size(width: 320, aspectRatio: nil, in: space), landscape, "Until the first frame, the shape of most cameras.")

        XCTAssertEqual(RecordingPreviewLayout.clampedWidth(20), RecordingPreviewLayout.minimumWidth)
        XCTAssertEqual(RecordingPreviewLayout.clampedWidth(5_000), RecordingPreviewLayout.maximumWidth)
        let narrowSpace = CGSize(width: 300, height: 200)
        let fitted = RecordingPreviewLayout.size(width: 640, aspectRatio: 16.0 / 9.0, in: narrowSpace)
        XCTAssertLessThanOrEqual(fitted.width, narrowSpace.width - 2 * RecordingPreviewLayout.margin)
        XCTAssertLessThanOrEqual(fitted.height, narrowSpace.height - 2 * RecordingPreviewLayout.margin)
    }

    func testThePreviewIsMovedWithinItsSpaceAndKeepsItsPlaceWhenTheWindowChanges() {
        let space = CGSize(width: 1_000, height: 700)
        let size = CGSize(width: 320, height: 180)
        let margin = RecordingPreviewLayout.margin
        let bottomTrailing = RecordingPreviewLayout.center(at: UnitPoint(x: 1, y: 1), size: size, in: space)
        XCTAssertEqual(bottomTrailing, CGPoint(x: space.width - margin - size.width / 2, y: space.height - margin - size.height / 2))

        // The room left around the preview is 648 by 488 points; half of it is the middle.
        let dragged = RecordingPreviewLayout.position(UnitPoint(x: 1, y: 1), movedBy: CGSize(width: -324, height: -244), size: size, in: space)
        XCTAssertEqual(dragged.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(dragged.y, 0.5, accuracy: 0.001)
        let draggedAway = RecordingPreviewLayout.position(dragged, movedBy: CGSize(width: -5_000, height: 5_000), size: size, in: space)
        XCTAssertEqual(draggedAway, UnitPoint(x: 0, y: 1), "It cannot leave the space.")
        XCTAssertEqual(RecordingPreviewLayout.center(at: draggedAway, size: size, in: space), CGPoint(x: margin + size.width / 2, y: space.height - margin - size.height / 2))

        // The same place, as a share of the space, in a narrower window.
        let narrower = CGSize(width: 600, height: 700)
        XCTAssertEqual(RecordingPreviewLayout.center(at: UnitPoint(x: 1, y: 1), size: size, in: narrower).x, narrower.width - margin - size.width / 2)
    }

    // MARK: Video recordings in the workspace

    func testAVideoSavedAgainKeepsItsExtensionAndGetsAFreshPlace() async throws {
        let vault = try makeVault(files: ["Lecture.mp4": "someone else's file"])
        let workspace = try await makeWorkspace(vault)
        let recording = try makeMovie(in: try makeFolder("VideoRecovery"))
        workspace.recording.adoptRecording(at: recording, destination: vault.appendingPathComponent("Renamed away/Lecture.mp4"),
                                           state: .failed, message: "Saving failed.", kind: .video)

        await workspace.retryRecordingPublication()

        XCTAssertEqual(workspace.recording.state, .idle, workspace.recording.message ?? "")
        let saved = try XCTUnwrap(workspace.recording.lastCompletedURL)
        XCTAssertEqual(saved.pathExtension, "mp4")
        XCTAssertEqual(saved.lastPathComponent, "Lecture 1.mp4", "The name that is taken is left to its file.")
        XCTAssertEqual(saved.deletingLastPathComponent().resolvingSymlinksInPath(), vault)
        XCTAssertEqual(String(decoding: try Data(contentsOf: vault.appendingPathComponent("Lecture.mp4")), as: UTF8.self), "someone else's file")
        let isPlayable = try await AVURLAsset(url: saved).load(.isPlayable)
        XCTAssertTrue(isPlayable)
    }

    func testAnUnfinishedVideoIsOfferedAndSavedWhereItBelongs() async throws {
        let vault = try makeVault(files: ["Course/Lecture.md": "# Lecture\n"])
        let workspace = try await makeWorkspace(vault)
        let recoveryFolder = try makeFolder("VideoRecovery")
        workspace.recording.recoveryFolderLocation = { recoveryFolder }
        let recording = try makeMovie(in: recoveryFolder)
        try RecordingRecoveryFolder.write(RecordingRecoveryManifest(vaultIdentifier: nil, destinationPath: "Course/attachments/Lecture Recording 2026-09-30 10-15.mp4",
                                                                    notePath: "Course/Lecture.md", startedAt: .now), for: recording)

        workspace.checkForUnfinishedRecordings()
        let offer = try XCTUnwrap(workspace.recordingRecoveryOffer)
        XCTAssertEqual(offer.kind, .video)
        await workspace.recover(offer)

        XCTAssertNil(workspace.errorMessage)
        let saved = vault.appendingPathComponent("Course/attachments/Lecture Recording 2026-09-30 10-15.mp4")
        let isPlayable = try await AVURLAsset(url: saved).load(.isPlayable)
        XCTAssertTrue(isPlayable)
        XCTAssertEqual(workspace.selection, try VaultPath("Course/attachments/Lecture Recording 2026-09-30 10-15.mp4"), "The saved video opens.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recoveryFolder.path), [])
        XCTAssertNil(workspace.recordingRecoveryOffer)
    }

    // MARK: Helpers

    private func makeFolder(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        temporaryFolders.append(folder)
        return folder.resolvingSymlinksInPath()
    }

    private func makeVault(files: [String: String]) throws -> URL {
        let vault = try makeFolder("RecordingVault")
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        return vault
    }

    private func makeWorkspace(_ vault: URL) async throws -> WorkspaceModel {
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        let store = VaultStore(root: vault)
        workspace.store = store
        workspace.vaultSettings = try await store.settings()
        workspace.index = try VaultIndex(databaseURL: try makeFolder("RecordingIndex").appendingPathComponent("index.sqlite"))
        return workspace
    }

    /// A second of H.264 video, as a finished recording part would be.
    private func makeMovie(in folder: URL) throws -> URL {
        let location = folder.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: location, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frameIndex in 0..<30 {
            var pixelBuffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else {
                throw GraphiteError.unavailable("No pixel buffer.")
            }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            // Noise, so the file is as large as a real recording's first second.
            if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) { arc4random_buf(baseAddress, CVPixelBufferGetDataSize(pixelBuffer)) }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: 30))
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        XCTAssertEqual(writer.status, .completed)
        return location
    }
}
