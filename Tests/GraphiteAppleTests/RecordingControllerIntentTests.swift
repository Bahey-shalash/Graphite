import XCTest
import AVFoundation
import GraphiteCore
@testable import GraphiteApple

/// What pause, resume, stop and start do in each recording state, and how long a stop waits
/// for the recorder to report before it saves the recording anyway.
@MainActor
final class RecordingControllerIntentTests: XCTestCase {
    private var workFolder: URL!
    private let everyState: [RecordingState] = [.idle, .requestingPermission, .recording, .paused, .interrupted, .finalizing, .failed]

    override func setUp() async throws {
        workFolder = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingIntents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workFolder) // Best-effort removal of a temporary folder.
    }

    /// A controller in `state` for a recording at a place that holds no audio: only the state machine is exercised.
    private func makeController(in state: RecordingState, withRecorder: Bool = false) throws -> RecordingController {
        let controller = RecordingController()
        // A stop that is never answered saves after this long; far beyond a test.
        controller.finalizationTimeout = .seconds(3_600)
        let recorder = withRecorder
            ? try AVAudioRecorder(url: workFolder.appendingPathComponent("\(UUID().uuidString).caf"), settings: RecordingController.recordingSettings)
            : nil
        controller.adoptRecording(at: workFolder.appendingPathComponent("recording.m4a"), destination: workFolder.appendingPathComponent("Lecture.m4a"),
                                  state: state, recorder: recorder)
        return controller
    }

    func testAStopWithoutTheRecordersReportSavesAfterThirtySecondsByDefault() {
        XCTAssertEqual(RecordingController().finalizationTimeout, .seconds(30))
    }

    func testPauseOnlyActsOnARecordingInProgress() throws {
        for state in everyState {
            let controller = try makeController(in: state)

            controller.pause()

            XCTAssertEqual(controller.state, state == .recording ? .paused : state, "pause from \(state.rawValue)")
        }
    }

    func testStopActsOnARecordingInProgressPausedOrInterruptedAndStartsFinalizing() throws {
        let stoppable: Set<RecordingState> = [.recording, .paused, .interrupted]
        for state in everyState {
            let controller = try makeController(in: state)

            controller.stop()

            XCTAssertEqual(controller.state, stoppable.contains(state) ? .finalizing : state, "stop from \(state.rawValue)")
        }
    }

    func testResumeLeavesEveryStateThatIsNeitherPausedNorInterruptedAsItIs() throws {
        for state in everyState where state != .paused && state != .interrupted {
            let controller = try makeController(in: state, withRecorder: true)

            controller.resume()

            XCTAssertEqual(controller.state, state, "resume from \(state.rawValue)")
            XCTAssertNil(controller.message)
        }
    }

    func testStartingIsRefusedInEveryStateWhileARecordingWaitsToBeSavedAndChangesNothing() async throws {
        let manifest = RecordingRecoveryManifest(vaultIdentifier: nil, destinationPath: "Lecture.m4a", notePath: nil, startedAt: .now)
        for state in everyState {
            let controller = try makeController(in: state)
            // The recording adopted above is the only copy of the lecture, so even idle and failed may not start.
            XCTAssertFalse(controller.canStartRecording, "start from \(state.rawValue) with a recording waiting")

            await controller.start(destination: workFolder.appendingPathComponent("Next.m4a"), manifest: manifest)

            XCTAssertEqual(controller.state, state, "start from \(state.rawValue)")
            XCTAssertEqual(controller.recoveryURL, workFolder.appendingPathComponent("recording.m4a"))
        }
    }

    func testANewControllerMayStartBecauseNoRecordingWaitsToBeSaved() {
        let controller = RecordingController()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.canStartRecording)
    }
}
