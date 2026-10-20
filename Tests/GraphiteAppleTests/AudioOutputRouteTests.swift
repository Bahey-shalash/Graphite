import XCTest
import GraphiteCore
@testable import GraphiteApple

/// A test run is silent. Speech, rendered voices and embedded media take their route from the
/// process, and a process that hosts tests renders and discards (`AudioOutputRoute`).
@MainActor
final class AudioOutputRouteTests: XCTestCase {
    func testAProcessThatHostsTestsDoesNotPlayThroughTheSpeakers() {
        XCTAssertEqual(AudioOutputRoute.thisProcess, .silent)
    }

    func testTheSystemVoiceBuiltWithoutARouteIsSilentInATestRun() {
        XCTAssertEqual(AppleReadAloudSpeech().output, .silent)
    }

    func testOnlyAPersonsLaunchPlaysThroughTheSpeakers() {
        XCTAssertEqual(AudioOutputRoute(launchMode: .normal), .speakers)
        XCTAssertEqual(AudioOutputRoute(launchMode: .hostedTests), .silent)
        XCTAssertEqual(AudioOutputRoute(launchMode: LaunchMode(arguments: [], environment: ["XCTestConfigurationFilePath": "/tmp/x"])), .silent)
    }
}
