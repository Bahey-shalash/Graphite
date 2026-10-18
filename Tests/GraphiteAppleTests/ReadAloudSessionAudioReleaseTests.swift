import XCTest
import GraphiteCore
@testable import GraphiteApple

@MainActor
private final class ReleaseCountingSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "test-voice", name: "Study", language: "en-US", quality: 3)]
    var requestIdentifiers: [UUID] = []
    var audioReleaseCount = 0
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws { requestIdentifiers.append(requestIdentifier) }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
    func releaseAudio() { audioReleaseCount += 1 }
}

/// The audio session is given back to other apps only when reading really ends: the person
/// stops it, it is cleared, or the last passage finishes with nothing to continue to. Moving
/// around inside reading, or loading the next PDF page, keeps it.
@MainActor
final class ReadAloudSessionAudioReleaseTests: XCTestCase {
    private func makeSpeakingSession(markdown: String) throws -> (ReadAloudSession, ReleaseCountingSpeech) {
        let speech = ReleaseCountingSpeech()
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ReadAloudSessionAudioReleaseTests-\(UUID().uuidString)"))
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test-voice")
        session.load(try ReadAloudDocument.markdown(markdown))
        session.play()
        return (session, speech)
    }

    func testSkippingToTheNextSentenceKeepsTheAudioSession() throws {
        let (session, speech) = try makeSpeakingSession(markdown: "First sentence. Second sentence. Third sentence.")
        let releasesBefore = speech.audioReleaseCount

        session.moveToNextSentence()
        session.moveToPreviousSentence()

        XCTAssertEqual(session.state, .speaking)
        XCTAssertEqual(speech.audioReleaseCount, releasesBefore)
    }

    func testJumpingToAnotherPassageKeepsTheAudioSession() throws {
        let (session, speech) = try makeSpeakingSession(markdown: "# One\n\nTwo.\n\nThree.")
        let releasesBefore = speech.audioReleaseCount

        session.move(to: 2)
        session.move(to: 1, offset: 0)
        session.repeatPassage()

        XCTAssertEqual(speech.audioReleaseCount, releasesBefore)
    }

    func testLoadingTheNextPageAfterTheLastPassageKeepsTheAudioSessionThatTheContinuationAsked() throws {
        let (session, speech) = try makeSpeakingSession(markdown: "Only passage.")
        session.didFinishDocument = { true }
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requestIdentifiers.last)))
        XCTAssertEqual(session.state, .finished)
        let releasesBefore = speech.audioReleaseCount

        session.load(try ReadAloudDocument.markdown("Next page."))
        session.play()

        XCTAssertEqual(speech.audioReleaseCount, releasesBefore)
    }

    func testFinishingTheLastPassageWithNothingToContinueToReleasesTheAudioSession() throws {
        let (session, speech) = try makeSpeakingSession(markdown: "Only passage.")
        session.didFinishDocument = { false }
        let releasesBefore = speech.audioReleaseCount

        speech.eventHandler?(.finished(try XCTUnwrap(speech.requestIdentifiers.last)))

        XCTAssertEqual(speech.audioReleaseCount, releasesBefore + 1)
    }

    func testTheStopTheUserTapsReleasesTheAudioSessionOnce() throws {
        let (session, speech) = try makeSpeakingSession(markdown: "First sentence. Second sentence.")
        let releasesBefore = speech.audioReleaseCount

        session.stop()

        XCTAssertEqual(speech.audioReleaseCount, releasesBefore + 1)
    }

    func testClosingReadingReleasesTheAudioSession() throws {
        let (session, speech) = try makeSpeakingSession(markdown: "First sentence. Second sentence.")
        let releasesBefore = speech.audioReleaseCount

        session.clear()

        XCTAssertGreaterThan(speech.audioReleaseCount, releasesBefore)
    }
}
