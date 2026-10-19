import XCTest
import GraphiteCore
@testable import GraphiteApple

/// The hosted app is a process that hosts tests, so its speech renders and discards: the
/// hosted Read Aloud tests make no sound on the Mac that runs the simulator.
@MainActor
final class AudioOutputRouteHostedTests: XCTestCase {
    func testTheHostedAppDoesNotPlayThroughTheSpeakers() {
        XCTAssertEqual(AudioOutputRoute.thisProcess, .silent)
        XCTAssertEqual(AppleReadAloudSpeech().output, .silent)
    }
}
