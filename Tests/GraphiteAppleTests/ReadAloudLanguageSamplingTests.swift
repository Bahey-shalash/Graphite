import XCTest
import GraphiteCore
@testable import GraphiteApple

@MainActor
private final class SilentSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "test-voice", name: "Study", language: "en-US", quality: 3)]
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {}
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
}

/// The language a passage is read in comes from its own words: the document's leading passages
/// (at least 4,000 UTF-16 units) are sampled, a guess needs a confidence of at least 0.6, and a
/// weaker guess leaves the device language in use. The recognizer itself weighs the start of
/// the sample, so the 4,000-unit cutoff cannot be told apart from it by a test.
final class ReadAloudLanguageSamplingTests: XCTestCase {
    private let englishSentence = "The transistor switches when the gate voltage exceeds the threshold voltage of the device."
    private let frenchSentence = "Le transistor commute lorsque la tension de grille dépasse la tension de seuil du dispositif."

    /// Paragraphs of the sentence, separated by blank lines, until the text holds at least `units` UTF-16 units.
    private func paragraphs(of sentence: String, atLeast units: Int) -> String {
        var text = ""
        while text.utf16.count < units { text += (sentence + " " + sentence + "\n\n") }
        return text
    }

    func testEnglishTextIsEnglishWhateverTheDeviceLanguageIs() throws {
        let language = try XCTUnwrap(ReadAloudLanguage.language(ofText: englishSentence))

        XCTAssertTrue(language == "en" || language.hasPrefix("en-"), language)
    }

    func testFrenchTextIsFrench() throws {
        let language = try XCTUnwrap(ReadAloudLanguage.language(ofText: frenchSentence))

        XCTAssertTrue(language == "fr" || language.hasPrefix("fr-"), language)
    }

    func testTextThatNoLanguageClaimsWithEnoughConfidenceGivesNoLanguage() {
        XCTAssertNil(ReadAloudLanguage.language(ofText: "12345 6789 ???"))
        XCTAssertNil(ReadAloudLanguage.language(ofText: ""))
        XCTAssertNil(ReadAloudLanguage.language(ofText: "ok"), "Best guess 29 %.")
        XCTAssertNil(ReadAloudLanguage.language(ofText: "la casa the house"), "Best guess 26 %.")
    }

    func testTheLeadingPassagesDecideTheLanguageOfALongDocument() throws {
        let frenchFirst = try ReadAloudDocument.markdown(paragraphs(of: frenchSentence, atLeast: 4_100) + paragraphs(of: englishSentence, atLeast: 20_000))
        let englishFirst = try ReadAloudDocument.markdown(paragraphs(of: englishSentence, atLeast: 4_100) + paragraphs(of: frenchSentence, atLeast: 20_000))

        let frenchLanguage = try XCTUnwrap(ReadAloudLanguage.language(of: frenchFirst))
        let englishLanguage = try XCTUnwrap(ReadAloudLanguage.language(of: englishFirst))

        XCTAssertTrue(frenchLanguage == "fr" || frenchLanguage.hasPrefix("fr-"), frenchLanguage)
        XCTAssertTrue(englishLanguage == "en" || englishLanguage.hasPrefix("en-"), englishLanguage)
    }

    func testADocumentWhoseLanguageIsNotRecognizedGivesNoLanguage() throws {
        let document = try ReadAloudDocument.markdown("12345 6789 ???")

        XCTAssertNil(ReadAloudLanguage.language(of: document))
    }

    @MainActor
    func testASessionReadsInTheDocumentsLanguageOrElseTheDeviceLanguage() throws {
        let suiteName = "ReadAloudLanguageSamplingTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { preferences.removePersistentDomain(forName: suiteName) }
        let session = ReadAloudSession(speech: SilentSpeech(), preferences: preferences)

        session.load(try ReadAloudDocument.markdown(frenchSentence))
        XCTAssertTrue(session.readingLanguage == "fr" || session.readingLanguage.hasPrefix("fr-"), session.readingLanguage)

        session.load(try ReadAloudDocument.markdown("12345 6789 ???"))
        XCTAssertEqual(session.readingLanguage, ReadAloudLanguage.deviceLanguage)
    }
}
