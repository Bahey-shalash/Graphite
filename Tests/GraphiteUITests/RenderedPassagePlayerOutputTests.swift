import XCTest
import GraphiteCore
@testable import GraphiteVoices

/// A rendered passage is played through the real engine and timed as for the speakers, and
/// nothing is heard in a test run.
@MainActor
final class RenderedPassagePlayerOutputTests: XCTestCase {
    func testAPlayerBuiltInATestRunIsSilent() {
        XCTAssertTrue(RenderedPassagePlayer().isSilent)
    }

    func testOnlyThePlayerOfAPersonsLaunchIsHeard() {
        XCTAssertFalse(RenderedPassagePlayer(output: AudioOutputRoute(launchMode: .normal)).isSilent)
        XCTAssertTrue(RenderedPassagePlayer(output: .silent).isSilent)
    }
}
