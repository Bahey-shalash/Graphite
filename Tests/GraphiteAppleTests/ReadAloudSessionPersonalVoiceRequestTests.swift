import XCTest
import GraphiteCore
@testable import GraphiteApple

@MainActor
private final class PersonalVoiceCountingSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    var voices = [ReadAloudVoice(id: "test-voice", name: "Study", language: "en-US", quality: 3)]
    var personalVoiceStatus = ReadAloudPersonalVoiceStatus.notDetermined
    /// How many times the system's Personal Voice permission prompt was asked for.
    private(set) var accessRequestCount = 0
    private(set) var requestIdentifiers: [UUID] = []

    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws { requestIdentifiers.append(requestIdentifier) }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}

    func requestPersonalVoiceAccess() async -> ReadAloudPersonalVoiceStatus {
        accessRequestCount += 1
        personalVoiceStatus = .authorized
        voices.append(ReadAloudVoice(id: "personal", name: "My Voice", language: "en-US", quality: 3, isPersonalVoice: true))
        return .authorized
    }
}

/// Graphite shows the system's Personal Voice permission prompt only when the person taps the
/// button for it, never while listing voices or reading.
@MainActor
final class ReadAloudSessionPersonalVoiceRequestTests: XCTestCase {
    private func makeSession() throws -> (ReadAloudSession, PersonalVoiceCountingSpeech) {
        let speech = PersonalVoiceCountingSpeech()
        let suiteName = "ReadAloudSessionPersonalVoiceRequestTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { preferences.removePersistentDomain(forName: suiteName) }
        return (ReadAloudSession(speech: speech, preferences: preferences), speech)
    }

    func testNothingButTheButtonAsksForPersonalVoiceAccessWhileListingChoosingAndReading() throws {
        let (session, speech) = try makeSession()

        session.refreshVoices()
        session.chooseVoice("test-voice")
        session.setSpeed(1.5)
        session.load(try ReadAloudDocument.markdown("First sentence. Second sentence. Third sentence.\n\n# Heading\n\nAnother paragraph."))
        session.play()
        session.moveToNextSentence()
        session.moveToPreviousSentence()
        session.move(to: 1)
        session.repeatPassage()
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requestIdentifiers.last)))
        session.stop()
        session.clear()

        XCTAssertEqual(speech.accessRequestCount, 0)
        XCTAssertEqual(session.personalVoiceStatus, .notDetermined, "The status is read without asking.")
    }

    func testTheButtonAsksOnceAndReadsWithThePersonalVoiceWhenAllowed() async throws {
        let (session, speech) = try makeSession()
        session.refreshVoices()

        await session.requestPersonalVoice()

        XCTAssertEqual(speech.accessRequestCount, 1)
        XCTAssertEqual(session.personalVoiceStatus, .authorized)
        XCTAssertEqual(session.chosenVoiceIdentifier, "personal")
    }
}
