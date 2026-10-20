import XCTest
import MediaPlayer
import GraphiteApple
@testable import GraphiteUI

/// What Read Aloud shows on the lock screen and in Control Center, and the skip step the media
/// controls offer.
@MainActor
final class ReadAloudNowPlayingTests: XCTestCase {
    private let nowPlaying = ReadAloudNowPlaying()

    override func tearDown() async throws {
        nowPlaying.clear()
    }

    private func publish(title: String?, state: ReadAloudSession.State = .speaking, progress: Double? = 0.25) {
        nowPlaying.update(title: title, detail: "Lecture notes", state: state, progress: progress,
                          commands: ReadAloudNowPlaying.Commands(play: { true }, pause: { true }, nextSentence: { true }, previousSentence: { true }))
    }

    func testTheSkipButtonsStepByTenSecondsOnceAPassageIsLoaded() {
        publish(title: "Lecture")

        XCTAssertEqual(MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals, [10])
        XCTAssertEqual(MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals, [10])
    }

    func testALoadedPassageIsShownWithItsTitleDetailAndProgress() throws {
        publish(title: "Lecture", state: .speaking, progress: 0.25)

        let information = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(information[MPMediaItemPropertyTitle] as? String, "Lecture")
        XCTAssertEqual(information[MPMediaItemPropertyArtist] as? String, "Lecture notes")
        XCTAssertEqual(information[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)
        XCTAssertEqual(information[MPNowPlayingInfoPropertyPlaybackProgress] as? Float, 0.25)
    }

    func testPausedReadingIsShownAsNotPlayingAndProgressIsKeptWithinZeroAndOne() throws {
        publish(title: "Lecture", state: .paused, progress: 7)

        let information = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(information[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertEqual(information[MPNowPlayingInfoPropertyPlaybackProgress] as? Float, 1)
    }

    func testWithoutATitleNothingIsShown() {
        publish(title: "Lecture")

        publish(title: nil)

        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }
}
