import XCTest
import AVFoundation
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
    var releaseCount = 0
    var leadingPauses: [Double] = []
    func speak(_ text: String, voiceIdentifier: String, speed: Double, leadingPauseSeconds: Double, requestIdentifier: UUID) throws {
        leadingPauses.append(leadingPauseSeconds)
        try speak(text, voiceIdentifier: voiceIdentifier, speed: speed, requestIdentifier: requestIdentifier)
    }
    func pause() -> Bool { true }
    func resume() -> Bool { canResume }
    func stop() {}
    func releaseAudio() { releaseCount += 1 }
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

    /// A call interrupts reading; when it ends and the system allows it, reading resumes at the
    /// same word. Reading the person had paused stays paused.
    func testReadingResumesAfterAnInterruptionOnlyIfItWasSpeaking() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.plainText("One sentence here. Another one."))
        session.play()
        let first = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(first, NSRange(location: 4, length: 8)))
        speech.eventHandler?(.interrupted)
        XCTAssertEqual(session.state, .paused)
        speech.eventHandler?(.interruptionEnded(shouldResume: false))
        XCTAssertEqual(session.state, .paused)
        session.play()
        XCTAssertEqual(speech.requests.last?.text, "sentence here. Another one.")
        speech.eventHandler?(.interrupted)
        speech.eventHandler?(.interruptionEnded(shouldResume: true))
        XCTAssertEqual(session.state, .speaking)
        session.pause()
        speech.eventHandler?(.interrupted)
        speech.eventHandler?(.interruptionEnded(shouldResume: true))
        XCTAssertEqual(session.state, .paused, "A reading the person paused must not start by itself.")
    }

    /// A heading is followed by a longer breath than a list item, and a heading is preceded by one.
    func testPausesBetweenPassagesFollowWhatTheyAre() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.markdown("# Title\n\nBody one.\n\n- First item\n- Second item\n\n## Next"))
        XCTAssertEqual(session.document?.passages.map(\.kind), [.heading, .paragraph, .listItem, .listItem, .heading])
        session.play()
        for _ in 0..<4 { speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier))) }
        XCTAssertEqual(speech.leadingPauses, [0, 0.6, 0.35, 0.25, 0.6])
        session.setSpeed(1.25)
        session.play()
        XCTAssertEqual(speech.leadingPauses.last, 0, "Resuming starts at once.")
    }

    func testAudioIsReleasedWhenReadingStopsOrFinishesButNotBetweenPDFPages() throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.plainText("Only."))
        session.play()
        session.didFinishDocument = { true }
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        XCTAssertEqual(session.state, .finished)
        let releasesWhileContinuing = speech.releaseCount
        session.load(try ReadAloudDocument.plainText("Last."))
        session.play()
        session.didFinishDocument = { false }
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        XCTAssertGreaterThan(speech.releaseCount, releasesWhileContinuing)
        let beforeStop = speech.releaseCount
        session.stop()
        XCTAssertEqual(speech.releaseCount, beforeStop + 1)
    }

    func testPersonalVoiceThenRegionThenSystemDefaultBreakTies() {
        let compactUS = ReadAloudVoice(id: "samantha", name: "Samantha", language: "en-US", quality: 1)
        let compactGB = ReadAloudVoice(id: "daniel", name: "Daniel", language: "en-GB", quality: 1)
        let otherCompactUS = ReadAloudVoice(id: "aaron", name: "Aaron", language: "en-US", quality: 1)
        XCTAssertEqual(ReadAloudVoice.preferred(in: [compactGB, compactUS], language: "en-GB")?.id, "daniel")
        XCTAssertEqual(ReadAloudVoice.preferred(in: [otherCompactUS, compactUS], language: "en-US", systemDefaultIdentifier: "samantha")?.id, "samantha")
        let personal = ReadAloudVoice(id: "mine", name: "My Voice", language: "en-US", quality: 1, isPersonalVoice: true)
        let premium = ReadAloudVoice(id: "ava", name: "Ava", language: "en-US", quality: 3)
        XCTAssertEqual(ReadAloudVoice.preferred(in: [premium, personal], language: "en-US")?.id, "mine")
        XCTAssertEqual(personal.qualityDescription, "Personal Voice")
        XCTAssertFalse(personal.isCompact)
    }

    /// Nothing chosen means the best installed voice, re-evaluated when a better one arrives,
    /// so downloading a Premium voice takes effect without a visit to the picker.
    func testAutomaticVoiceFollowsNewlyInstalledPremiumVoiceUntilThePersonChooses() throws {
        let speech = TestReadAloudSpeech()
        speech.voices = [ReadAloudVoice(id: "compact", name: "Samantha", language: "en-US", quality: 1)]
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ReadAloudTests-\(UUID().uuidString)"))
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.load(try ReadAloudDocument.plainText("The pull-down network uses nMOS transistors, and the pull-up network uses pMOS transistors."))
        XCTAssertTrue(session.readingLanguage.hasPrefix("en"))
        XCTAssertNil(session.chosenVoiceIdentifier)
        XCTAssertEqual(session.selectedVoiceIdentifier, "compact")
        XCTAssertTrue(session.canImproveVoiceByDownloading)
        speech.voices.append(ReadAloudVoice(id: "premium", name: "Ava", language: "en-US", quality: 3))
        session.refreshVoices()
        XCTAssertEqual(session.selectedVoiceIdentifier, "premium")
        XCTAssertFalse(session.canImproveVoiceByDownloading)
        session.chooseVoice("compact")
        XCTAssertEqual(ReadAloudSession(speech: speech, preferences: preferences).chosenVoiceIdentifier, "compact")
        session.chooseVoice(nil)
        XCTAssertEqual(session.selectedVoiceIdentifier, "premium")
        XCTAssertNil(ReadAloudSession(speech: speech, preferences: preferences).chosenVoiceIdentifier)
    }

    /// An English lecture is read with an English voice even when the device prefers French.
    func testReadingLanguageComesFromThePassageNotTheDevice() throws {
        let (session, speech) = try makeSession()
        speech.voices = [ReadAloudVoice(id: "thomas", name: "Thomas", language: "fr-FR", quality: 3),
                         ReadAloudVoice(id: "samantha", name: "Samantha", language: "en-US", quality: 1)]
        session.chooseVoice(nil)
        session.refreshVoices()
        session.load(try ReadAloudDocument.plainText("Le réseau de pull-down utilise des transistors nMOS, et le réseau de pull-up utilise des transistors pMOS."))
        XCTAssertEqual(session.automaticVoice?.id, "thomas")
        session.load(try ReadAloudDocument.plainText("Static gates draw almost no current while they are at rest, which keeps the power low."))
        XCTAssertEqual(session.automaticVoice?.id, "samantha")
    }

    /// The robotic MacinTalk and Eloquence voices are never offered, so they can never be the
    /// automatic choice (Fred used to win ties by identifier). Uses the voices this Mac has.
    func testRoboticSystemVoicesAreNotOffered() throws {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let robotic = installed.filter { voice in voice.identifier.hasPrefix("com.apple.speech.synthesis.voice.") || voice.identifier.hasPrefix("com.apple.eloquence.") }
        guard !robotic.isEmpty else { throw XCTSkip("This system lists no MacinTalk or Eloquence voices.") }
        XCTAssertFalse(robotic.contains(where: AppleReadAloudSpeech.isOffered))
        let offered = AppleReadAloudSpeech().voices
        XCTAssertFalse(offered.contains { voice in voice.id.contains(".eloquence.") || voice.id.contains(".speech.synthesis.voice.") })
        if let compact = installed.first(where: { voice in voice.identifier.hasPrefix("com.apple.voice.compact.en-US") }) {
            XCTAssertTrue(AppleReadAloudSpeech.isOffered(compact))
        }
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
