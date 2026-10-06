import XCTest
import AVFoundation
import GraphiteCore
@testable import GraphiteApple

/// Video recording driven without a camera: `SyntheticCaptureSource` delivers real frames
/// and sound, which go through the writer the app uses, and an independent reader checks
/// the MP4 files that come out.
@MainActor
final class VideoRecordingTests: XCTestCase {
    private var workFolder: URL!
    private var recoveryFolder: URL!
    private var attachmentsFolder: URL!

    override func setUp() async throws {
        workFolder = FileManager.default.temporaryDirectory.appendingPathComponent("VideoRecording-\(UUID().uuidString)", isDirectory: true)
        recoveryFolder = workFolder.appendingPathComponent("Recovery", isDirectory: true)
        attachmentsFolder = workFolder.appendingPathComponent("Vault/attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachmentsFolder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: recoveryFolder.path)
        try? FileManager.default.removeItem(at: workFolder)
    }

    // MARK: The file

    func testAVideoRecordingIsAnOrdinaryMP4WithH264VideoAndAACSound() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Lecture Recording 2026-09-30 10-15.mp4")
        await start(controller, destination: destination)
        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(controller.kind, .video)

        await source.deliver(seconds: 3)
        XCTAssertEqual(controller.elapsedSeconds, 3, accuracy: 0.1)
        controller.stop()
        try await waitUntil { controller.state == .idle }

        XCTAssertEqual(controller.lastCompletedURL, destination)
        XCTAssertNil(controller.message)
        let movie = try await MovieInspection.of(destination)
        XCTAssertTrue(movie.isPlayable)
        XCTAssertEqual(movie.durationSeconds, 3, accuracy: 0.1)
        XCTAssertEqual(movie.videoCodec, "avc1", "H.264")
        XCTAssertEqual(movie.audioCodec, "aac", "AAC")
        XCTAssertEqual([movie.videoWidth, movie.videoHeight], [640, 360])
        XCTAssertEqual(movie.audioSampleRate, 44_100)
        XCTAssertEqual(movie.audioChannelCount, 1)
        XCTAssertEqual(movie.decodedFrameCount, 90, accuracy: 2, "Every frame delivered can be decoded again.")
        XCTAssertEqual(Double(movie.decodedAudioSampleCount) / 44_100, 3, accuracy: 0.15)
        XCTAssertFalse(movie.containsFragments, "Stopping leaves an ordinary MP4 with one index.")
        XCTAssertEqual(Set(movie.boxNames), ["ftyp", "mdat", "moov"], "No movie fragments are left in the saved file.")
        XCTAssertTrue(MovieInspection.colors(movie.firstFrameColor, match: SyntheticCaptureSource.backCameraColor), "\(movie.firstFrameColor)")
        XCTAssertEqual(try recoveryFolderContents(), [], "Nothing stays behind once the video is in the vault.")
        XCTAssertEqual(source.stopCount, 1, "The camera is let go.")
    }

    func testPausedTimeIsLeftOutWithoutAGap() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Paused.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 2)

        controller.pause()
        XCTAssertEqual(controller.state, .paused)
        await source.deliver(seconds: 1)
        source.advanceClock(bySeconds: 600)
        XCTAssertEqual(controller.elapsedSeconds, 2, accuracy: 0.1, "The time stands still while paused.")

        controller.resume()
        try await waitUntil { controller.state == .recording }
        await source.deliver(seconds: 2)
        XCTAssertEqual(controller.elapsedSeconds, 4, accuracy: 0.15)
        controller.stop()
        try await waitUntil { controller.state == .idle }

        XCTAssertNil(controller.message)
        let movie = try await MovieInspection.of(destination)
        XCTAssertEqual(movie.durationSeconds, 4, accuracy: 0.15, "Ten minutes of pause add nothing to the file.")
        XCTAssertEqual(Double(movie.decodedAudioSampleCount) / 44_100, 4, accuracy: 0.15, "The sound goes on without a gap either.")
        XCTAssertEqual(movie.decodedFrameCount, 120, accuracy: 3)
        XCTAssertLessThan(movie.longestSecondsBetweenFrames, 0.12, "The picture goes straight on where the pause began.")
        XCTAssertEqual(Set(movie.boxNames), ["ftyp", "mdat", "moov"], "A pause stays in one file, which needs no joining.")
    }

    /// A camera drops frames when the device is busy, and its frames are not evenly spaced.
    /// With H.264 frame reordering left on, the writer failed at the next fragment.
    func testFramesThatNeverArriveDoNotEndTheRecording() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Dropped frames.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 2)
        source.advanceClock(bySeconds: 0.5)
        await source.deliver(seconds: 2)
        source.advanceClock(bySeconds: 0.1)
        await source.deliver(seconds: 2)

        XCTAssertEqual(controller.state, .recording)
        XCTAssertNil(controller.message)
        controller.stop()
        try await waitUntil { controller.state == .idle }
        XCTAssertNil(controller.message)
        let movie = try await MovieInspection.of(destination)
        XCTAssertEqual(movie.durationSeconds, 6.6, accuracy: 0.15, "The time without frames stays in the recording, which was not paused.")
        XCTAssertEqual(movie.decodedFrameCount, 180, accuracy: 4)
    }

    func testChangingCameraKeepsOneFile() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Two cameras.mp4")
        await start(controller, destination: destination)
        XCTAssertEqual(controller.availableCameras, [.back, .front])
        await source.deliver(seconds: 1)

        controller.switchCamera(to: .front)
        try await waitUntil { controller.camera == .front }
        await source.deliver(seconds: 1)
        controller.stop()
        try await waitUntil { controller.state == .idle }

        let movie = try await MovieInspection.of(destination)
        XCTAssertEqual(movie.durationSeconds, 2, accuracy: 0.1)
        XCTAssertTrue(MovieInspection.colors(movie.firstFrameColor, match: SyntheticCaptureSource.backCameraColor), "\(movie.firstFrameColor)")
        XCTAssertTrue(MovieInspection.colors(movie.lastFrameColor, match: SyntheticCaptureSource.frontCameraColor), "\(movie.lastFrameColor)")
    }

    func testACameraTheDeviceLacksLeavesTheRecordingOnItsCamera() async throws {
        let source = SyntheticCaptureSource(cameras: [.back])
        let controller = makeController(source: source)
        await start(controller, destination: attachmentsFolder.appendingPathComponent("One camera.mp4"))
        XCTAssertEqual(controller.availableCameras, [.back])

        controller.switchCamera(to: .front)
        try await waitUntil { controller.message != nil }
        XCTAssertEqual(controller.camera, .back)
        XCTAssertEqual(controller.state, .recording, "The recording goes on.")
    }

    func testFramesOfATurnedDeviceAreFittedInsideTheVideo() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Turned.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 1)
        try await waitUntil { controller.videoAspectRatio != nil }
        XCTAssertEqual(try XCTUnwrap(controller.videoAspectRatio), 640.0 / 360.0, accuracy: 0.01)

        source.turnDevice()
        await source.deliver(seconds: 1)
        try await waitUntil { (controller.videoAspectRatio ?? 2) < 1 }
        XCTAssertEqual(try XCTUnwrap(controller.videoAspectRatio), 360.0 / 640.0, accuracy: 0.01, "The preview follows the camera's shape.")
        controller.stop()
        try await waitUntil { controller.state == .idle }

        let movie = try await MovieInspection.of(destination)
        XCTAssertEqual([movie.videoWidth, movie.videoHeight], [640, 360], "The file keeps the shape it started with.")
        XCTAssertEqual(movie.durationSeconds, 2, accuracy: 0.1)
        XCTAssertTrue(MovieInspection.colors(movie.lastFrameColor, match: SyntheticCaptureSource.backCameraColor), "The upright picture is in the middle: \(movie.lastFrameColor)")
        XCTAssertTrue(MovieInspection.colors(movie.lastFrameLeftEdgeColor, match: [0, 0, 0]), "With black beside it: \(movie.lastFrameLeftEdgeColor)")
    }

    // MARK: Interruptions

    func testLeavingTheScreenClosesTheFileAndTheVideoGoesOnInOneFileAfterwards() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Interrupted.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 2)

        await source.interrupt(.applicationOffScreen)
        try await waitUntil { controller.state == .interrupted }
        XCTAssertEqual(controller.message, CaptureInterruptionReason.applicationOffScreen.explanation, "The person is told why the video paused.")
        // What was recorded is a complete file at once: the system may end the app now.
        let recoveryURL = try XCTUnwrap(controller.recoveryURL)
        try await waitUntilClosed(recoveryURL)
        let firstPart = try await MovieInspection.of(recoveryURL)
        XCTAssertEqual(firstPart.durationSeconds, 2, accuracy: 0.1, "Nothing of the two seconds is lost, not even the last fragment.")
        XCTAssertFalse(firstPart.containsFragments)

        await source.deliver(seconds: 5)
        source.advanceClock(bySeconds: 120)
        XCTAssertEqual(controller.elapsedSeconds, 2, accuracy: 0.1, "Nothing is recorded while the camera is away.")

        await source.endInterruption()
        try await waitUntil { controller.state == .recording }
        XCTAssertTrue(try XCTUnwrap(controller.message).contains("recording again"), "The person is told that it went on: \(controller.message ?? "")")
        await source.deliver(seconds: 2)
        XCTAssertEqual(try recoveryFolderContents().filter { name in name.hasSuffix(".mp4") }.count, 2, "The video goes on in a second part.")
        controller.stop()
        try await waitUntil { controller.state == .idle }

        let movie = try await MovieInspection.of(destination)
        XCTAssertEqual(movie.durationSeconds, 4, accuracy: 0.2, "Both parts are in the one file that is saved.")
        XCTAssertEqual(movie.decodedFrameCount, 120, accuracy: 4)
        XCTAssertEqual(movie.videoCodec, "avc1")
        XCTAssertEqual(movie.audioCodec, "aac")
        XCTAssertEqual(Set(movie.boxNames), ["ftyp", "mdat", "moov"])
        XCTAssertEqual(try recoveryFolderContents(), [], "The parts go once the joined video is in the vault.")
    }

    func testAVideoPausedByThePersonStaysPausedAfterAnInterruption() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Paused then interrupted.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 1)
        controller.pause()

        await source.interrupt(.cameraInUseByAnotherApplication)
        try await waitUntil { controller.state == .interrupted }
        await source.endInterruption()
        try await waitUntil { controller.state == .paused }
        XCTAssertNil(controller.message)

        controller.resume()
        try await waitUntil { controller.state == .recording }
        await source.deliver(seconds: 1)
        controller.stop()
        try await waitUntil { controller.state == .idle }
        let savedSeconds = try await MovieInspection.of(destination).durationSeconds
        XCTAssertEqual(savedSeconds, 2, accuracy: 0.15)
    }

    func testResumingByHandWorksWhenTheSystemDoesNotRestartTheCamera() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Resumed by hand.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 1)
        await source.interrupt(.captureStopped)
        try await waitUntil { controller.state == .interrupted }

        source.failResuming(with: GraphiteError.unavailable("The camera is still not available."))
        controller.resume()
        try await waitUntil { controller.message == "The camera is still not available." }
        XCTAssertEqual(controller.state, .interrupted, "The recording waits; Stop still saves it.")

        source.failResuming(with: nil)
        controller.resume()
        try await waitUntil { controller.state == .recording }
        await source.deliver(seconds: 1)
        controller.stop()
        try await waitUntil { controller.state == .idle }
        let savedSeconds = try await MovieInspection.of(destination).durationSeconds
        XCTAssertEqual(savedSeconds, 2, accuracy: 0.15)
    }

    func testStoppingWhileInterruptedSavesWhatWasRecorded() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Stopped while away.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 2)
        await source.interrupt(.microphoneInUseByAnotherApplication)
        try await waitUntil { controller.state == .interrupted }

        controller.stop()
        try await waitUntil { controller.state == .idle }
        let movie = try await MovieInspection.of(destination)
        XCTAssertEqual(movie.durationSeconds, 2, accuracy: 0.1)
        XCTAssertEqual(try recoveryFolderContents(), [])
    }

    // MARK: Recovery

    func testAVideoNobodyClosedIsRecoveredUpToItsLastFragment() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        await start(controller, destination: attachmentsFolder.appendingPathComponent("Lecture.mp4"), destinationPath: "attachments/Lecture.mp4")
        await source.deliver(seconds: 4)
        // The file as it is on disk while recording, which is what is left when the app is ended.
        let leftBehind = workFolder.appendingPathComponent("After a crash", isDirectory: true)
        try copyRecoveryFolder(to: leftBehind)
        controller.stop()
        try await waitUntil { controller.state == .idle }

        let found = RecordingRecoveryFolder.recordings(in: leftBehind)
        XCTAssertEqual(found.count, 1)
        let unfinished = try XCTUnwrap(found.first)
        XCTAssertEqual(unfinished.kind, .video)
        XCTAssertEqual(unfinished.destination, try VaultPath("attachments/Lecture.mp4"))
        let cutOff = try await MovieInspection.of(unfinished.mediaLocation)
        XCTAssertTrue(cutOff.isPlayable, "The file left behind plays as it is.")
        XCTAssertTrue(cutOff.containsFragments)
        XCTAssertGreaterThan(cutOff.durationSeconds, 2.4, "At most the fragment being written, about a second, and what the encoder still held are lost.")
        XCTAssertLessThanOrEqual(cutOff.durationSeconds, 4.05)

        let recovered = attachmentsFolder.appendingPathComponent("Recovered.mp4")
        try await RecordingController().recover(unfinished, to: recovered)
        let movie = try await MovieInspection.of(recovered)
        XCTAssertEqual(movie.durationSeconds, cutOff.durationSeconds, accuracy: 0.1)
        XCTAssertEqual(movie.decodedFrameCount, cutOff.decodedFrameCount)
        XCTAssertFalse(movie.containsFragments, "Recovery saves an ordinary MP4.")
        XCTAssertEqual(Set(movie.boxNames), ["ftyp", "mdat", "moov"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: leftBehind.path), [], "Its parts and manifest are removed once it is saved.")
    }

    func testAVideoInTwoPartsIsRecoveredAsOneFile() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        await start(controller, destination: attachmentsFolder.appendingPathComponent("Lecture.mp4"))
        await source.deliver(seconds: 2)
        await source.interrupt(.applicationOffScreen)
        try await waitUntil { controller.state == .interrupted }
        await source.endInterruption()
        try await waitUntil { controller.state == .recording }
        await source.deliver(seconds: 3)
        let leftBehind = workFolder.appendingPathComponent("After a crash", isDirectory: true)
        try copyRecoveryFolder(to: leftBehind)
        controller.stop()
        try await waitUntil { controller.state == .idle }

        let found = RecordingRecoveryFolder.recordings(in: leftBehind)
        XCTAssertEqual(found.count, 1, "The second part is not a recording of its own.")
        let unfinished = try XCTUnwrap(found.first)
        XCTAssertEqual(unfinished.laterPartLocations.count, 1)

        let recovered = attachmentsFolder.appendingPathComponent("Recovered.mp4")
        try await RecordingController().recover(unfinished, to: recovered)
        let movie = try await MovieInspection.of(recovered)
        XCTAssertGreaterThan(movie.durationSeconds, 3.4, "The whole first part and the second up to its last fragment.")
        XCTAssertLessThanOrEqual(movie.durationSeconds, 5.1)
        XCTAssertFalse(movie.containsFragments)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: leftBehind.path), [])
    }

    func testAVideoFileWithNothingToPlayIsRefusedAndKept() async throws {
        let broken = recoveryFolder.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data(repeating: 0, count: 20_000).write(to: broken)
        let unfinished = try XCTUnwrap(RecordingRecoveryFolder.recordings(in: recoveryFolder).first)
        do {
            try await RecordingController().recover(unfinished, to: attachmentsFolder.appendingPathComponent("Recovered.mp4"))
            XCTFail("There is nothing to play.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The recording contains no playable video.")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path), "Nothing is deleted.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: attachmentsFolder.path), [])
    }

    // MARK: Saving into the vault

    func testATakenNameIsReportedAndTheVideoCanBeSavedUnderAnother() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Lecture.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 1)
        try Data("another file".utf8).write(to: destination)
        controller.stop()
        try await waitUntil { controller.state == .failed }

        XCTAssertTrue(try XCTUnwrap(controller.message).contains("already contains a file named “Lecture.mp4”"), controller.message ?? "")
        XCTAssertEqual(try Data(contentsOf: destination), Data("another file".utf8), "The file that was there is untouched.")
        XCTAssertFalse(controller.canStartRecording, "The video is the only copy, so no new recording replaces it.")
        controller.dismissMessage()
        XCTAssertEqual(controller.state, .failed, "A video waiting to be saved cannot be waved away.")
        XCTAssertNotNil(controller.message)
        let keptRecording = try XCTUnwrap(controller.recoveryURL)
        let keptSeconds = try await MovieInspection.of(keptRecording).durationSeconds
        XCTAssertEqual(keptSeconds, 1, accuracy: 0.1)

        let freeDestination = attachmentsFolder.appendingPathComponent("Lecture 1.mp4")
        await controller.retryPublication(to: freeDestination)
        XCTAssertEqual(controller.state, .idle, controller.message ?? "")
        let savedSeconds = try await MovieInspection.of(freeDestination).durationSeconds
        XCTAssertEqual(savedSeconds, 1, accuracy: 0.1)
        XCTAssertEqual(try recoveryFolderContents(), [])
    }

    func testDiscardingAVideoThatCouldNotBeSavedRemovesEveryPart() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Lecture.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 1)
        await source.interrupt(.applicationOffScreen)
        try await waitUntil { controller.state == .interrupted }
        await source.endInterruption()
        try await waitUntil { controller.state == .recording }
        await source.deliver(seconds: 1)
        try Data("another file".utf8).write(to: destination)
        controller.stop()
        try await waitUntil { controller.state == .failed }
        XCTAssertEqual(try recoveryFolderContents().filter { name in name.hasSuffix(".mp4") }.count, 2)

        controller.discardRecoveredRecording()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(try recoveryFolderContents(includingHidden: true), [])
        XCTAssertTrue(controller.canStartRecording)
    }

    // MARK: Permissions and hardware

    func testRefusedCameraAccessIsExplainedAndLeavesNothingBehind() async throws {
        for (problem, canBeChangedInSettings) in [(CaptureAccessProblem.cameraDenied, true), (.microphoneDenied, true), (.cameraRestricted, true), (.noCamera, false)] {
            let source = SyntheticCaptureSource(problemOnStart: problem)
            let controller = makeController(source: source)
            await start(controller, destination: attachmentsFolder.appendingPathComponent("Lecture.mp4"))

            XCTAssertEqual(controller.state, .failed)
            XCTAssertEqual(controller.message, problem.errorDescription)
            XCTAssertEqual(controller.accessProblem, problem)
            XCTAssertEqual(controller.accessProblem?.canBeChangedInSettings, canBeChangedInSettings)
            XCTAssertNil(controller.recoveryURL)
            XCTAssertTrue(controller.canStartRecording, "Nothing was recorded, so another recording can start.")
            XCTAssertEqual(try recoveryFolderContents(), [], "A recording that never started leaves no file and no manifest.")
            controller.dismissMessage()
            XCTAssertEqual(controller.state, .idle, "The explanation can be put away.")
            XCTAssertNil(controller.message)
            XCTAssertNil(controller.accessProblem)
        }
    }

    func testAStartCancelledWhileTheCameraAnswersLeavesNothingBehind() async throws {
        let source = SyntheticCaptureSource()
        source.holdStart()
        let controller = makeController(source: source)
        let starting = Task { await self.start(controller, destination: self.attachmentsFolder.appendingPathComponent("Lecture.mp4")) }
        try await waitUntil { source.startCount == 1 }
        XCTAssertEqual(controller.state, .requestingPermission)

        controller.cancelStart()
        XCTAssertEqual(controller.state, .idle)
        source.releaseStart()
        await starting.value

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.recoveryURL)
        XCTAssertEqual(try recoveryFolderContents(), [])
        XCTAssertEqual(source.stopCount, 1, "The camera that answered late is let go.")
    }

    // MARK: Storage

    func testAVideoDoesNotStartWithoutRoomForIt() async throws {
        let controller = makeController(source: SyntheticCaptureSource())
        controller.videoStorage = RecordingStorage { _ in RecordingStorage.minimumBytesToStart - 1 }
        await start(controller, destination: attachmentsFolder.appendingPathComponent("Lecture.mp4"))

        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(controller.message, "There is not enough free storage to record video. Free some space, then try again.")
        XCTAssertNil(controller.accessProblem)
        XCTAssertEqual(try recoveryFolderContents(), [])
    }

    func testAVideoStopsItselfAndIsSavedWhenStorageRunsLow() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let freeBytes = FreeBytes(RecordingStorage.minimumBytesToStart * 2)
        controller.videoStorage = RecordingStorage { _ in freeBytes.byteCount }
        let destination = attachmentsFolder.appendingPathComponent("Lecture.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 3)
        XCTAssertEqual(controller.state, .recording)

        freeBytes.byteCount = RecordingStorage.minimumBytesWhileRecording - 1
        await source.deliver(seconds: 3)
        try await waitUntil { controller.state == .idle }

        XCTAssertEqual(controller.message, "Storage is almost full, so the video recording stopped. What was recorded has been saved.")
        let movie = try await MovieInspection.of(destination)
        XCTAssertGreaterThan(movie.durationSeconds, 3, "Everything up to the stop is in the file.")
        XCTAssertLessThan(movie.durationSeconds, 5.5, "It stops within two seconds of storage running low.")
        XCTAssertFalse(movie.containsFragments)
        XCTAssertEqual(source.stopCount, 1)
    }

    func testAPartThatCannotBeWrittenStopsTheRecordingAndKeepsTheRest() async throws {
        let source = SyntheticCaptureSource()
        let controller = makeController(source: source)
        let destination = attachmentsFolder.appendingPathComponent("Lecture.mp4")
        await start(controller, destination: destination)
        await source.deliver(seconds: 2)
        await source.interrupt(.applicationOffScreen)
        try await waitUntil { controller.state == .interrupted }
        try await waitUntilClosed(try XCTUnwrap(controller.recoveryURL))

        // The next part cannot be created.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: recoveryFolder.path)
        await source.endInterruption()
        try await waitUntil { controller.state == .recording }
        await source.deliver(seconds: 1)
        try await waitUntil { controller.state == .idle || controller.state == .failed }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: recoveryFolder.path)

        XCTAssertEqual(controller.state, .idle, controller.message ?? "")
        XCTAssertTrue(try XCTUnwrap(controller.message).hasPrefix("The video recording stopped:"), controller.message ?? "")
        let savedSeconds = try await MovieInspection.of(destination).durationSeconds
        XCTAssertEqual(savedSeconds, 2, accuracy: 0.1, "The part recorded before is saved.")
    }

    // MARK: Helpers

    private func makeController(source: SyntheticCaptureSource) -> RecordingController {
        let controller = RecordingController()
        let recoveryFolder = recoveryFolder!
        controller.recoveryFolderLocation = { recoveryFolder }
        controller.makeVideoCaptureSource = { source }
        controller.videoStorage = RecordingStorage { _ in nil }
        return controller
    }

    private func start(_ controller: RecordingController, destination: URL, destinationPath: String? = nil) async {
        let manifest = RecordingRecoveryManifest(vaultIdentifier: UUID(), destinationPath: destinationPath ?? "attachments/" + destination.lastPathComponent,
                                                 notePath: "Lecture.md", startedAt: .now)
        await controller.startVideo(destination: destination, manifest: manifest, camera: .back)
    }

    private func recoveryFolderContents(includingHidden: Bool = false) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: recoveryFolder, includingPropertiesForKeys: nil, options: includingHidden ? [] : [.skipsHiddenFiles])
            .map(\.lastPathComponent).sorted()
    }

    private func copyRecoveryFolder(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in try recoveryFolderContents() {
            try FileManager.default.copyItem(at: recoveryFolder.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
    }

    /// Waits until a part's writer has closed it: the file then has one index and no fragments.
    private func waitUntilClosed(_ partLocation: URL, timeoutSeconds: Double = 20) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while (try? await AVURLAsset(url: partLocation).load(.containsFragments)) != false || MovieInspection.topLevelBoxNames(of: partLocation).last != "moov" {
            guard Date.now < deadline else { return XCTFail("Timed out waiting for the part to be closed.") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitUntil(_ condition: () -> Bool, timeoutSeconds: Double = 20) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else { return XCTFail("Timed out waiting for the recording controller.") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Free storage a test changes while a recording runs.
private final class FreeBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var storedByteCount: Int64
    init(_ byteCount: Int64) { storedByteCount = byteCount }
    var byteCount: Int64 {
        get { lock.withLock { storedByteCount } }
        set { lock.withLock { storedByteCount = newValue } }
    }
}

private func XCTAssertEqual(_ value: Int, _ expected: Int, accuracy: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(value - expected), accuracy, "\(value) is not within \(accuracy) of \(expected). \(message)", file: file, line: line)
}
