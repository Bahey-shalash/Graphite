import XCTest
import AVFoundation
import GraphiteCore
@testable import GraphiteVoices
import GraphiteTestSupport

/// A rendered passage is timed as for the speakers and nothing is heard in a test run: on the silent route the player has no
/// engine at all (a running engine holds the audio output open, even at zero volume), and the passage is played by the clock.
@MainActor
final class RenderedPassagePlayerOutputTests: XCTestCase {
    private final class Finish { var count = 0 }

    func testAPlayerBuiltInATestRunHasNoEngineAndHoldsNoAudioDevice() {
        XCTAssertTrue(RenderedPassagePlayer().isSilent)
    }

    func testOnlyThePlayerOfAPersonsLaunchHasAnEngine() {
        XCTAssertFalse(RenderedPassagePlayer(output: AudioOutputRoute(launchMode: .normal)).isSilent)
        XCTAssertTrue(RenderedPassagePlayer(output: .silent).isSilent)
    }

    /// A silent file of `seconds` at 8 kHz.
    private func passage(seconds: Double) throws -> URL {
        let location = try TemporaryVault.make(prefix: "SilentPassage", for: self).root.appendingPathComponent("Passage.caf")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8_000.0, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        let file = try AVAudioFile(forWriting: location, settings: settings)
        let frames = AVAudioFrameCount(seconds * 8_000)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
        return location
    }

    private func advance(_ clock: ManualClock, by seconds: Double) async {
        clock.advance(by: .seconds(seconds))
        await ManualClock.letResumedTasksRun()
    }

    func testAPassageFinishesWhenItsLastSampleWouldHaveBeenHeard() async throws {
        let clock = ManualClock()
        let player = RenderedPassagePlayer(output: .silent, clock: clock)
        let finish = Finish()
        try player.play(try passage(seconds: 2), from: 0, rate: 1) { finish.count += 1 }
        try await clock.awaitPendingSleepers()

        await advance(clock, by: 1.9)
        XCTAssertEqual(finish.count, 0)
        XCTAssertEqual(try XCTUnwrap(player.currentSeconds), 1.9, accuracy: 0.01, "The position follows the clock.")
        await advance(clock, by: 0.2)
        XCTAssertEqual(finish.count, 1)
        XCTAssertNil(player.currentSeconds, "Nothing plays once it finished.")
    }

    func testTheRateSetsHowFastThePassageGoes() async throws {
        let clock = ManualClock()
        let player = RenderedPassagePlayer(output: .silent, clock: clock)
        let finish = Finish()
        try player.play(try passage(seconds: 2), from: 0, rate: 2) { finish.count += 1 }
        try await clock.awaitPendingSleepers()
        await advance(clock, by: 0.9)
        XCTAssertEqual(finish.count, 0)
        XCTAssertEqual(try XCTUnwrap(player.currentSeconds), 1.8, accuracy: 0.01)
        await advance(clock, by: 0.2)
        XCTAssertEqual(finish.count, 1, "Two seconds at twice the speed.")
    }

    func testStartingPartWayPlaysOnlyWhatIsLeft() async throws {
        let clock = ManualClock()
        let player = RenderedPassagePlayer(output: .silent, clock: clock)
        let finish = Finish()
        try player.play(try passage(seconds: 2), from: 1.5, rate: 1) { finish.count += 1 }
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(try XCTUnwrap(player.currentSeconds), 1.5, accuracy: 0.01)
        await advance(clock, by: 0.6)
        XCTAssertEqual(finish.count, 1)
    }

    func testPausingHoldsThePositionAndResumingGoesOnFromIt() async throws {
        let clock = ManualClock()
        let player = RenderedPassagePlayer(output: .silent, clock: clock)
        let finish = Finish()
        try player.play(try passage(seconds: 2), from: 0, rate: 1) { finish.count += 1 }
        try await clock.awaitPendingSleepers()
        await advance(clock, by: 0.5)

        player.pause()
        XCTAssertTrue(player.isPaused)
        await advance(clock, by: 60)
        XCTAssertEqual(finish.count, 0)
        XCTAssertEqual(try XCTUnwrap(player.currentSeconds), 0.5, accuracy: 0.01, "Paused, the position stays.")

        try player.resume()
        try await clock.awaitPendingSleepers()
        await advance(clock, by: 1.4)
        XCTAssertEqual(finish.count, 0)
        await advance(clock, by: 0.2)
        XCTAssertEqual(finish.count, 1)
    }

    func testChangingTheRateMidwayCountsWhatWasPlayedAtTheOldRate() async throws {
        let clock = ManualClock()
        let player = RenderedPassagePlayer(output: .silent, clock: clock)
        let finish = Finish()
        try player.play(try passage(seconds: 2), from: 0, rate: 1) { finish.count += 1 }
        try await clock.awaitPendingSleepers()
        await advance(clock, by: 1)
        player.setRate(2)
        try await clock.awaitPendingSleepers()
        await advance(clock, by: 0.45)
        XCTAssertEqual(finish.count, 0, "One second is left at twice the speed: half a second.")
        await advance(clock, by: 0.1)
        XCTAssertEqual(finish.count, 1)
    }

    func testStoppingEndsThePassageWithoutFinishing() async throws {
        let clock = ManualClock()
        let player = RenderedPassagePlayer(output: .silent, clock: clock)
        let finish = Finish()
        try player.play(try passage(seconds: 2), from: 0, rate: 1) { finish.count += 1 }
        try await clock.awaitPendingSleepers()
        player.stop()
        await advance(clock, by: 60)
        XCTAssertEqual(finish.count, 0)
        XCTAssertNil(player.currentSeconds)
    }
}
