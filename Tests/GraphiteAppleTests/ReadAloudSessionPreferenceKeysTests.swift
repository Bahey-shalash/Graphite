import XCTest
@testable import GraphiteApple

/// A voice that says nothing, offering two voices, so a session can be given choices.
@MainActor
private final class SilentReadAloudSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "voice-a", name: "A", language: "en-US", quality: 3),
                  ReadAloudVoice(id: "voice-b", name: "B", language: "en-US", quality: 3)]
    var assistiveSpeechSettingsMayApply = false
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {}
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
    func systemVoice(language: String) -> ReadAloudVoice? { nil }
    func releaseAudio() {}
}

/// What `ReadAloudSession` keeps on the device: the voice chosen, how much is highlighted
/// and the speed, under these names.
@MainActor
final class ReadAloudSessionPreferenceKeysTests: XCTestCase {
    private var suiteName = ""
    private var preferences: UserDefaults!

    override func setUp() async throws {
        suiteName = "ReadAloudSessionPreferenceKeysTests-\(UUID().uuidString)"
        preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        preferences.removePersistentDomain(forName: suiteName)
        preferences = nil
    }

    private func makeSession() -> ReadAloudSession {
        ReadAloudSession(speech: SilentReadAloudSpeech(), preferences: preferences)
    }

    func testAnEmptyStoreFollowsTheSystemVoiceHighlightsWordsAndReadsAtNormalSpeed() {
        let session = makeSession()

        XCTAssertNil(session.chosenVoiceIdentifier)
        XCTAssertEqual(session.highlightMode, .words)
        XCTAssertEqual(session.speed, 1.0)
    }

    func testAVoiceChosenInThePickerIsStoredAsJSONWithItsSource() throws {
        makeSession().chooseVoice("voice-a")

        let data = try XCTUnwrap(preferences.data(forKey: "GraphiteReadAloudVoiceChoice"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["identifier": "voice-a", "source": "picker"])
        XCTAssertEqual(makeSession().chosenVoiceIdentifier, "voice-a")
    }

    func testAVoiceChosenWithThePersonalVoiceButtonIsStoredWithThatSource() throws {
        makeSession().chooseVoice("voice-b", madeWith: .personalVoiceButton)

        let data = try XCTUnwrap(preferences.data(forKey: "GraphiteReadAloudVoiceChoice"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["identifier": "voice-b", "source": "personalVoiceButton"])
    }

    func testFollowingTheSystemVoiceAgainRemovesTheStoredChoice() {
        let session = makeSession()
        session.chooseVoice("voice-a")

        session.chooseVoice(nil)

        XCTAssertNil(preferences.object(forKey: "GraphiteReadAloudVoiceChoice"))
        XCTAssertNil(makeSession().chosenVoiceIdentifier)
    }

    func testAChoiceWrittenByHandIsReadBackWhenItIsAtMost4096Bytes() throws {
        let prefix = #"{"identifier":""#
        let suffix = #"","source":"picker"}"#
        let paddingCount = 4_096 - (prefix.utf8.count + suffix.utf8.count)
        let identifier = String(repeating: "a", count: paddingCount)
        let atTheLimit = Data((prefix + identifier + suffix).utf8)
        XCTAssertEqual(atTheLimit.count, 4_096)
        let overTheLimit = Data((prefix + identifier + "a" + suffix).utf8)
        XCTAssertEqual(overTheLimit.count, 4_097)

        preferences.set(atTheLimit, forKey: "GraphiteReadAloudVoiceChoice")
        XCTAssertEqual(makeSession().chosenVoiceIdentifier, identifier)

        preferences.set(overTheLimit, forKey: "GraphiteReadAloudVoiceChoice")
        XCTAssertNil(makeSession().chosenVoiceIdentifier)
    }

    func testAChoiceThatIsNotTheStoredJSONIsNotReadAsAChoice() {
        preferences.set("voice-a", forKey: "GraphiteReadAloudVoiceChoice")
        XCTAssertNil(makeSession().chosenVoiceIdentifier)

        preferences.set(Data(#"{"identifier":"voice-a"}"#.utf8), forKey: "GraphiteReadAloudVoiceChoice")
        XCTAssertNil(makeSession().chosenVoiceIdentifier, "A choice without its source is not one this build made.")
    }

    func testTheStoredVoiceKeysOfEarlierBuildsAreRemovedAndNeverRead() {
        preferences.set("com.apple.voice.compact.en-US.Fred", forKey: "GraphiteReadAloudVoice")
        preferences.set("com.apple.eloquence.en-US.Eddy", forKey: "GraphiteReadAloudChosenVoice")

        let session = makeSession()

        XCTAssertNil(session.chosenVoiceIdentifier)
        XCTAssertNil(preferences.object(forKey: "GraphiteReadAloudVoice"))
        XCTAssertNil(preferences.object(forKey: "GraphiteReadAloudChosenVoice"))
    }

    func testTheHighlightModeIsStoredAsItsRawValueAndReadBack() {
        XCTAssertEqual(ReadAloudHighlightMode.allCases.map(\.rawValue), ["words", "sentences", "off"])
        let session = makeSession()

        session.setHighlightMode(.sentences)

        XCTAssertEqual(preferences.string(forKey: "GraphiteReadAloudHighlightMode"), "sentences")
        XCTAssertEqual(makeSession().highlightMode, .sentences)
        preferences.set("off", forKey: "GraphiteReadAloudHighlightMode")
        XCTAssertEqual(makeSession().highlightMode, .off)
        preferences.set("paragraphs", forKey: "GraphiteReadAloudHighlightMode")
        XCTAssertEqual(makeSession().highlightMode, .words)
    }

    func testTheSpeedIsStoredAsADoubleAndReadBackOnlyWithinHalfToTriple() {
        XCTAssertEqual(ReadAloudSession.speedRange, 0.5...3)
        let session = makeSession()

        session.setSpeed(1.75)

        XCTAssertEqual(preferences.object(forKey: "GraphiteReadAloudSpeed") as? Double, 1.75)
        XCTAssertEqual(makeSession().speed, 1.75)
        for (stored, expected) in [(0.5, 0.5), (3.0, 3.0), (0.49, 1.0), (3.01, 1.0), (0.0, 1.0), (-1.0, 1.0)] {
            preferences.set(stored, forKey: "GraphiteReadAloudSpeed")
            XCTAssertEqual(makeSession().speed, expected, "stored \(stored)")
        }
    }

    func testASpeedOutsideTheRangeIsNotStored() {
        let session = makeSession()

        session.setSpeed(3.5)
        session.setSpeed(0.25)
        session.setSpeed(.nan)

        XCTAssertNil(preferences.object(forKey: "GraphiteReadAloudSpeed"))
        XCTAssertEqual(session.speed, 1.0)
    }
}
