import XCTest
import AVFoundation
import GraphiteCore
@testable import GraphiteApple

@MainActor
private final class TestReadAloudSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    var installedVoices = [ReadAloudVoice(id: "test-voice", name: "Study", language: "en-US", quality: 3)]
    /// How many times the session asked for the installed voices.
    var voiceListings = 0
    var voices: [ReadAloudVoice] {
        get { voiceListings += 1; return installedVoices }
        set { installedVoices = newValue }
    }
    var requests: [(text: String, identifier: UUID)] = []
    var canResume = true
    var failure: Error?
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {
        if let failure { throw failure }
        requests.append((text, requestIdentifier))
    }
    var releaseCount = 0
    var leadingPauses: [Double] = []
    var phoneticRequests: [[ReadAloudPhoneticRange]] = []
    func speak(_ utterance: ReadAloudUtteranceRequest, requestIdentifier: UUID) throws {
        phoneticRequests.append(utterance.phoneticRanges)
        try speak(utterance.text, voiceIdentifier: utterance.voiceIdentifier, speed: utterance.speed,
                  leadingPauseSeconds: utterance.leadingPauseSeconds, usesSystemSettings: utterance.usesSystemSettings,
                  requestIdentifier: requestIdentifier)
    }
    var usedSystemSettings: [Bool] = []
    var spokenVoices: [String] = []
    var systemVoicesByLanguage: [String: ReadAloudVoice] = [:]
    var assistiveSpeechSettingsMayApply = false
    func systemVoice(language: String) -> ReadAloudVoice? { systemVoicesByLanguage[language] }
    func speak(_ text: String, voiceIdentifier: String, speed: Double, leadingPauseSeconds: Double,
               usesSystemSettings: Bool, requestIdentifier: UUID) throws {
        leadingPauses.append(leadingPauseSeconds)
        usedSystemSettings.append(usesSystemSettings)
        spokenVoices.append(voiceIdentifier)
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

    /// Listing the system's voices took a tenth of a second at every launch on the Mac; a
    /// session lists them only once something needs them.
    func testTheVoicesAreListedOnlyOnceSomethingNeedsThem() throws {
        let speech = TestReadAloudSpeech()
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ReadAloudTests-\(UUID().uuidString)"))
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        XCTAssertEqual(speech.voiceListings, 0)
        XCTAssertEqual(session.voices.map(\.id), ["test-voice"])
        XCTAssertEqual(session.voices.map(\.id), ["test-voice"])
        XCTAssertEqual(speech.voiceListings, 1, "Listed once, then kept until asked to list again")
        session.refreshVoices()
        XCTAssertEqual(speech.voiceListings, 2)
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

    /// By default Graphite speaks like the system's Read & Speak: its voice for the language,
    /// even one Graphite does not list, with the system's settings preferred; a voice
    /// chosen in Graphite overrides both. Without a system voice the best installed one is used.
    func testFollowsTheSystemVoiceAndSettingsUntilAVoiceIsChosenForGraphite() throws {
        let speech = TestReadAloudSpeech()
        speech.voices = [ReadAloudVoice(id: "ava", name: "Ava", language: "en-US", quality: 3)]
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ReadAloudTests-\(UUID().uuidString)"))
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.load(try ReadAloudDocument.plainText("Static gates draw almost no current while they rest, which keeps the power low."))
        XCTAssertEqual(session.selectedVoiceIdentifier, "ava", "No system voice: the best installed voice.")
        speech.systemVoicesByLanguage[session.readingLanguage] = ReadAloudVoice(id: "aaron", name: "Aaron", language: "en-US", quality: 2)
        XCTAssertTrue(session.followsSystemVoice)
        XCTAssertEqual(session.selectedVoice?.name, "Aaron", "The system's voice is followed even when Graphite does not list it.")
        session.play()
        XCTAssertEqual(speech.spokenVoices.last, "aaron")
        XCTAssertEqual(speech.usedSystemSettings.last, true)
        XCTAssertFalse(session.speedFollowsSystem)
        speech.assistiveSpeechSettingsMayApply = true
        XCTAssertTrue(session.speedFollowsSystem, "With Speak Selection on, the system's rate applies and Graphite's speed is hidden.")
        session.chooseVoice("ava")
        XCTAssertFalse(session.speedFollowsSystem)
        session.play()
        XCTAssertEqual(speech.spokenVoices.last, "ava")
        XCTAssertEqual(speech.usedSystemSettings.last, false)
    }

    /// Earlier builds saved their automatic pick as if the person had chosen it; the owner's iPad
    /// kept reading with Eloquence "Eddy". Those keys are dropped, and only a choice recorded with
    /// how it was made is read back.
    func testOldStoredAutomaticPicksAreDroppedAndOnlyRecordedChoicesCount() throws {
        let speech = TestReadAloudSpeech()
        speech.voices = [ReadAloudVoice(id: "com.apple.eloquence.en-US.Eddy", name: "Eddy", language: "en-US", quality: 1),
                         ReadAloudVoice(id: "aaron", name: "Aaron", language: "en-US", quality: 2)]
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ReadAloudTests-\(UUID().uuidString)"))
        preferences.set("com.apple.eloquence.en-US.Eddy", forKey: "GraphiteReadAloudVoice")
        preferences.set("com.apple.eloquence.en-US.Eddy", forKey: "GraphiteReadAloudChosenVoice")
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        XCTAssertNil(session.chosenVoiceIdentifier)
        XCTAssertNil(preferences.object(forKey: "GraphiteReadAloudVoice"))
        XCTAssertNil(preferences.object(forKey: "GraphiteReadAloudChosenVoice"))
        XCTAssertTrue(session.followsSystemVoice)
        XCTAssertEqual(session.selectedVoiceIdentifier, "aaron", "The robotic voice is never the automatic fallback.")
        // A robotic system voice is not used as the utterance voice either.
        speech.systemVoicesByLanguage[session.readingLanguage] = speech.voices[0]
        XCTAssertEqual(session.selectedVoiceIdentifier, "aaron")
        // Picked by hand, it is used and remembered.
        session.chooseVoice("com.apple.eloquence.en-US.Eddy")
        XCTAssertEqual(ReadAloudSession(speech: speech, preferences: preferences).chosenVoiceIdentifier, "com.apple.eloquence.en-US.Eddy")
        XCTAssertEqual(session.selectedVoice?.qualityDescription, "Classic")
    }

    /// Words by default, the sentence in Sentences mode, nothing when Off; when the voice gives
    /// no word positions shortly after it starts, the whole passage instead of nothing.
    func testHighlightModesAndPassageFallbackWithoutWordTiming() async throws {
        let (session, speech) = try makeSession()
        session.load(try ReadAloudDocument.plainText("First sentence here. Second one follows."))
        session.play()
        let identifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.started(identifier))
        speech.eventHandler?(.spoken(identifier, NSRange(location: 21, length: 6)))
        XCTAssertEqual(session.highlightRange, NSRange(location: 21, length: 6))
        session.setHighlightMode(.sentences)
        XCTAssertEqual(session.highlightRange, NSRange(location: 21, length: 19))
        session.setHighlightMode(.off)
        XCTAssertNil(session.highlightRange)
        XCTAssertNil(session.sourceRange)
        session.setHighlightMode(.words)
        // A voice without word positions.
        session.load(try ReadAloudDocument.plainText("Spoken without word positions."))
        session.play()
        speech.eventHandler?(.started(try XCTUnwrap(speech.requests.last?.identifier)))
        XCTAssertNil(session.highlightRange, "No flash of the whole passage before the first word is due.")
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertTrue(session.lacksWordTiming)
        XCTAssertEqual(session.highlightRange, NSRange(location: 0, length: 30))
        XCTAssertEqual(session.sourceRange, NSRange(location: 0, length: 30))
    }

    func testIPAPronunciationsReachTheSpeechEngineRelativeToTheUtterance() throws {
        let (session, speech) = try makeSession()
        // IPA is opt-in (plain respelling is the default for every voice).
        var pronunciations = ReadAloudPronunciations(terms: ["SIMD": .init(say: "sim dee", ipa: "ˈsɪmdiː")])
        pronunciations.usesPhoneticNotation = true
        session.load(try ReadAloudDocument.markdown("The SIMD unit.", pronunciations: pronunciations))
        session.play()
        XCTAssertEqual(speech.phoneticRequests.last, [ReadAloudPhoneticRange(range: NSRange(location: 4, length: 7), notation: "ˈsɪmdiː")])
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
        XCTAssertEqual(compactUS.qualityDescription, "Default")
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

    /// The robotic MacinTalk and Eloquence voices (Fred used to win ties by identifier) are
    /// listed for picking by hand but flagged, and never chosen automatically. Uses this Mac's voices.
    func testRoboticSystemVoicesAreNeverPickedAutomatically() throws {
        let offered = AppleReadAloudSpeech().voices
        let robotic = offered.filter { voice in voice.id.contains(".eloquence.") || voice.id.contains(".speech.synthesis.voice.") }
        guard !robotic.isEmpty else { throw XCTSkip("This system lists no MacinTalk or Eloquence voices.") }
        XCTAssertTrue(robotic.allSatisfy(\.isRobotic))
        XCTAssertFalse(ReadAloudVoice.preferred(in: offered, language: "en-US")?.isRobotic ?? false)
        XCTAssertNil(ReadAloudVoice.preferred(in: robotic, language: "en-US"), "Not even as the last resort.")
        // The system's own voice for a language is reported whatever its family.
        let systemVoice = try XCTUnwrap(AppleReadAloudSpeech().systemVoice(language: "en-US"))
        XCTAssertEqual(systemVoice.id, AVSpeechSynthesisVoice(language: "en-US")?.identifier)
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
