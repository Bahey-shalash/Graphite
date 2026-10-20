import XCTest
import GraphiteApple
@testable import GraphiteVoices

@MainActor
final class RenderedPassagePlayerTests: XCTestCase {
    func testEverySpeedTheControlsOfferPlaysAtThatSpeed() {
        var speed = ReadAloudSession.speedRange.lowerBound
        while speed <= ReadAloudSession.speedRange.upperBound {
            XCTAssertEqual(Double(RenderedPassagePlayer.timePitchRate(forSpeed: speed)), speed, accuracy: 0.0001,
                           "The label says \(speed)× and the audio must play at \(speed)×.")
            speed += 0.25
        }
    }

    func testASpeedOutsideWhatTheControlsOfferIsHeldToTheNearestOffered() {
        XCTAssertEqual(Double(RenderedPassagePlayer.timePitchRate(forSpeed: 10)), ReadAloudSession.speedRange.upperBound, accuracy: 0.0001)
        XCTAssertEqual(Double(RenderedPassagePlayer.timePitchRate(forSpeed: 0.01)), ReadAloudSession.speedRange.lowerBound, accuracy: 0.0001)
    }
}
