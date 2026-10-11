import XCTest
import GraphiteCore
@testable import GraphiteApple

@MainActor
private final class TestReadAloudSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    var voices = [ReadAloudVoice(id: "test-voice", name: "Study", language: "en-US", quality: 3)]
    var requests: [(text: String, identifier: UUID)] = []
    var canResume = true
    var failure: Error?
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {
        if let failure { throw failure }
        requests.append((text, requestIdentifier))
    }
    func pause() -> Bool { true }
    func resume() -> Bool { canResume }
    func stop() {}
}

@MainActor
final class ReadAloudSessionTests: XCTestCase {
    private func makeSession() throws -> (ReadAloudSession, TestReadAloudSpeech) {
        let speech = TestReadAloudSpeech()
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ReadAloudTests-\(UUID().uuidString)"))
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test-voice")
        return (session, speech)
    }

    func testCompletionAdvancesOnePassageAndStaleCallbacksCannotAdvanceReplacement() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.markdown("# One\n\nTwo."))
        session.play()
        let firstIdentifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.finished(firstIdentifier))
        XCTAssertEqual(session.passageIndex, 1)
        XCTAssertEqual(speech.requests.count, 2)
        speech.eventHandler?(.finished(firstIdentifier))
        XCTAssertEqual(session.passageIndex, 1)
        session.load(try ReadAloudDocument.plainText("Replacement."))
        session.play()
        speech.eventHandler?(.finished(firstIdentifier))
        XCTAssertEqual(session.state, .speaking)
        XCTAssertEqual(session.passageIndex, 0)
    }

    func testRealSpokenRangesAreValidatedAndMappedWithoutChangingTheDocument() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.markdown("## Read this."))
        session.play()
        let identifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(identifier, NSRange(location: 5, length: 4)))
        XCTAssertEqual(session.sourceRange, NSRange(location: 8, length: 4))
        speech.eventHandler?(.spoken(identifier, NSRange(location: Int.max, length: 2)))
        XCTAssertEqual(session.spokenRange, NSRange(location: 5, length: 4))
        session.stop()
        speech.eventHandler?(.spoken(identifier, NSRange(location: 0, length: 4)))
        XCTAssertNil(session.spokenRange)
    }

    func testSpeedChangePausesAndResumesFromCurrentWord() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.plainText("Read this passage."))
        session.play()
        let identifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(identifier, NSRange(location: 5, length: 4)))
        session.setSpeed(1.25)
        XCTAssertEqual(session.state, .paused)
        session.play()
        XCTAssertEqual(speech.requests.last?.text, "this passage.")
        let resumedIdentifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(resumedIdentifier, NSRange(location: 0, length: 4)))
        XCTAssertEqual(session.spokenRange, NSRange(location: 5, length: 4))
    }

    func testInterruptionPreservesPositionAndRequiresExplicitResume() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.plainText("Read this passage."))
        session.play()
        let identifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(identifier, NSRange(location: 5, length: 4)))
        speech.eventHandler?(.interrupted)
        XCTAssertEqual(session.state, .paused)
        XCTAssertNotNil(session.message)
        speech.eventHandler?(.finished(identifier))
        XCTAssertEqual(session.state, .paused)
        session.play()
        XCTAssertEqual(speech.requests.last?.text, "this passage.")
    }

    func testMissingPreferredVoiceNeverSilentlySubstitutesAnotherVoice() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.plainText("Text."))
        speech.voices = [ReadAloudVoice(id: "other", name: "Other", language: "en-US", quality: 1)]
        session.refreshVoices()
        session.play()
        XCTAssertEqual(session.selectedVoiceIdentifier, "test-voice")
        XCTAssertEqual(speech.requests.count, 0)
        XCTAssertEqual(session.state, .paused)
        XCTAssertNotNil(session.message)
    }

    func testVoicePreferenceRanksQualityAndMatchesLanguage() {
        let voices = [ReadAloudVoice(id: "standard", name: "A", language: "en-US", quality: 1),
                      ReadAloudVoice(id: "premium", name: "B", language: "en-GB", quality: 3),
                      ReadAloudVoice(id: "french", name: "C", language: "fr-FR", quality: 3)]
        XCTAssertEqual(ReadAloudVoice.preferred(in: voices, language: "en-US")?.id, "premium")
        XCTAssertNil(ReadAloudVoice.preferred(in: voices, language: "de-DE"))
    }

    func testFinishedPlaybackRestartsAtBeginningAndNavigationStaysPaused() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.plainText("Text."))
        session.play()
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        XCTAssertEqual(session.state, .finished)
        session.play()
        XCTAssertEqual(session.state, .speaking)
        let resumedIdentifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.paused(resumedIdentifier))
        XCTAssertEqual(session.state, .speaking, "A delayed pause confirmation cannot undo Resume.")
        session.pause()
        speech.eventHandler?(.continued(resumedIdentifier))
        XCTAssertEqual(session.state, .paused, "A delayed resume confirmation cannot undo Pause.")
        speech.eventHandler?(.finished(resumedIdentifier))
        XCTAssertEqual(session.state, .paused, "Finishing while paused must not start the next passage.")
        session.move(to: 0)
        XCTAssertEqual(session.state, .paused)
    }

    func testSentenceNavigationRepeatAndStaleCallbacksKeepExactOffsets() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.plainText("First sentence. Second sentence! Third sentence?"))
        XCTAssertFalse(session.canMoveToPreviousSentence)
        XCTAssertTrue(session.canMoveToNextSentence)
        session.play()
        let oldIdentifier = try XCTUnwrap(speech.requests.last?.identifier)
        session.moveToNextSentence()
        XCTAssertEqual(speech.requests.last?.text, "Second sentence! Third sentence?")
        let secondIdentifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(oldIdentifier, NSRange(location: 0, length: 5)))
        XCTAssertNil(session.spokenRange)
        speech.eventHandler?(.spoken(secondIdentifier, NSRange(location: 0, length: 6)))
        XCTAssertEqual(session.sourceRange, NSRange(location: 16, length: 6))
        session.pause()
        session.moveToNextSentence()
        XCTAssertEqual(session.state, .paused)
        XCTAssertFalse(session.canMoveToNextSentence)
        session.play()
        XCTAssertEqual(speech.requests.last?.text, "Third sentence?")
        session.moveToPreviousSentence()
        XCTAssertEqual(speech.requests.last?.text, "Second sentence! Third sentence?")
        session.repeatPassage()
        XCTAssertEqual(speech.requests.last?.text, "First sentence. Second sentence! Third sentence?")
    }

    func testPreviousSentenceCanCrossPreparedPassagesWithoutStartingPausedAudio() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.markdown("First one. Last one.\n\nNext paragraph."))
        session.move(to: 1)
        XCTAssertTrue(session.canMoveToPreviousSentence)
        session.moveToPreviousSentence()
        XCTAssertEqual(session.passageIndex, 0)
        XCTAssertEqual(session.state, .paused)
        XCTAssertTrue(speech.requests.isEmpty)
        session.play()
        XCTAssertEqual(speech.requests.last?.text, "Last one.")
    }
}
