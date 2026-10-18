import XCTest
@testable import GraphiteCore

final class ReadAloudAudioLossPolicyTests: XCTestCase {
    func testALostOutputPausesRenderedReading() {
        XCTAssertTrue(ReadAloudAudioLossPolicy.pausesReading(after: .previousOutputUnavailable, isPlayingRenderedAudio: true))
    }

    func testAnEngineThatChangedItsConfigurationPausesRenderedReading() {
        XCTAssertTrue(ReadAloudAudioLossPolicy.pausesReading(after: .engineConfigurationChanged, isPlayingRenderedAudio: true))
    }

    func testAnAddedOutputTakesOverTheSoundWithoutPausing() {
        XCTAssertFalse(ReadAloudAudioLossPolicy.pausesReading(after: .newOutputAvailable, isPlayingRenderedAudio: true))
    }

    func testNothingPausesWhenRenderedAudioIsNotPlaying() {
        for change in [ReadAloudAudioOutputChange.previousOutputUnavailable, .engineConfigurationChanged, .newOutputAvailable] {
            XCTAssertFalse(ReadAloudAudioLossPolicy.pausesReading(after: change, isPlayingRenderedAudio: false), "\(change)")
        }
    }
}
