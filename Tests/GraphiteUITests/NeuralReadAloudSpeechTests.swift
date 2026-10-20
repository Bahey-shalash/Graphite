import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteVoices
import GraphiteTestSupport

@MainActor
final class NeuralReadAloudSpeechTests: XCTestCase {
    func testHighQualityReadingWithADownloadedVoiceIsNotGovernedByTheSystemSpeakingRate() throws {
        let fixture = try InstalledNeuralVoiceFixture(testCase: self)
        fixture.quickSpeech.assistiveSpeechSettingsMayApply = true

        XCTAssertTrue(fixture.speech.readsWithDownloadedVoice)
        XCTAssertFalse(fixture.speech.assistiveSpeechSettingsMayApply,
                       "Rendered audio plays at Graphite's own speed, so the speed control must stay available.")
    }

    func testTheSessionKeepsTheSpeedControlWhileHighQualityReadsWithAssistiveSpeechOn() throws {
        let fixture = try InstalledNeuralVoiceFixture(testCase: self)
        fixture.quickSpeech.assistiveSpeechSettingsMayApply = true
        let preferences = try IsolatedDeviceState.make(prefix: "NeuralReadAloudSpeechTests", for: self).preferences
        let session = ReadAloudSession(speech: fixture.speech, preferences: preferences)

        XCTAssertTrue(session.followsSystemVoice)
        XCTAssertFalse(session.speedFollowsSystem)
    }

    func testQuickReadingStillFollowsTheSystemSpeakingRateWhileAssistiveSpeechIsOn() throws {
        let fixture = try InstalledNeuralVoiceFixture(testCase: self)
        fixture.library.chooseMode(.quick)
        fixture.quickSpeech.assistiveSpeechSettingsMayApply = true

        XCTAssertFalse(fixture.speech.readsWithDownloadedVoice)
        XCTAssertTrue(fixture.speech.assistiveSpeechSettingsMayApply)
    }

    func testReadingWithoutADownloadedVoiceStillFollowsTheSystemSpeakingRateWhileAssistiveSpeechIsOn() throws {
        let fixture = try InstalledNeuralVoiceFixture(isInstalled: false, testCase: self)
        fixture.quickSpeech.assistiveSpeechSettingsMayApply = true

        XCTAssertTrue(fixture.speech.assistiveSpeechSettingsMayApply)
    }

    func testALostAudioOutputInterruptsRenderedReadingSoTheSessionPauses() throws {
        let fixture = try InstalledNeuralVoiceFixture(testCase: self)
        var events: [ReadAloudSpeechEvent] = []
        fixture.speech.eventHandler = { event in events.append(event) }
        let request = ReadAloudUtteranceRequest(text: "One passage.", voiceIdentifier: "test", speed: 1, leadingPauseSeconds: 0, usesSystemSettings: false)
        try fixture.speech.speak(request, requestIdentifier: UUID())

        fixture.speech.audioOutputDidChange(.previousOutputUnavailable)

        XCTAssertEqual(events.count, 1)
        guard case .interrupted? = events.first else { return XCTFail("Expected an interruption, got \(events)") }
        fixture.speech.cancelPreparation()
    }

    func testALostAudioOutputWithNothingReadingChangesNothing() throws {
        let fixture = try InstalledNeuralVoiceFixture(testCase: self)
        var events: [ReadAloudSpeechEvent] = []
        fixture.speech.eventHandler = { event in events.append(event) }

        fixture.speech.audioOutputDidChange(.previousOutputUnavailable)
        fixture.speech.audioOutputDidChange(.engineConfigurationChanged)

        XCTAssertTrue(events.isEmpty)
    }

    func testANewlyConnectedOutputDoesNotInterruptRenderedReading() throws {
        let fixture = try InstalledNeuralVoiceFixture(testCase: self)
        var events: [ReadAloudSpeechEvent] = []
        fixture.speech.eventHandler = { event in events.append(event) }
        let request = ReadAloudUtteranceRequest(text: "One passage.", voiceIdentifier: "test", speed: 1, leadingPauseSeconds: 0, usesSystemSettings: false)
        try fixture.speech.speak(request, requestIdentifier: UUID())

        fixture.speech.audioOutputDidChange(.newOutputAvailable)

        XCTAssertTrue(events.isEmpty)
        fixture.speech.cancelPreparation()
    }
}
