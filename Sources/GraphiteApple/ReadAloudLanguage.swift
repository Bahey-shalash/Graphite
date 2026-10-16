import AVFoundation
import Foundation
import NaturalLanguage
import GraphiteCore

/// Finds the language a passage is written in, so it is read with a voice of that language
/// rather than the device's. Lecture notes are often English on a French or German iPad.
public enum ReadAloudLanguage {
    /// Enough words to recognize a language without scanning a whole textbook chapter.
    private static let maximumSampleUTF16Count = 4_000
    /// Below this confidence a short or mixed passage keeps the device language.
    private static let minimumConfidence = 0.6

    static var deviceLanguage: String { AVSpeechSynthesisVoice.currentLanguageCode() }

    static func language(of document: ReadAloudDocument) -> String? {
        var sample = ""
        for passage in document.passages {
            sample += passage.text + "\n"
            if sample.utf16.count >= maximumSampleUTF16Count { break }
        }
        return language(ofText: sample)
    }

    /// A BCP 47 language with a region: the device's own region when it speaks that language
    /// (en-GB on a British iPad), otherwise the region of the system's voice for the language.
    public static func language(ofText text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minimumConfidence, language != .undetermined else { return nil }
        let code = language.rawValue
        for preferred in Locale.preferredLanguages + [deviceLanguage] {
            let parts = preferred.split(separator: "-")
            if parts.first.map(String.init) == code, parts.count > 1, let region = parts.last, region.count == 2 {
                return "\(code)-\(region)"
            }
        }
        return AVSpeechSynthesisVoice(language: code)?.language ?? code
    }
}
