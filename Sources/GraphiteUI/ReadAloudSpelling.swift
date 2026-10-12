import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The system's spelling dictionary, used to tell a word broken by hyphenation ("tran-sistor")
/// from a compound ("low-power") when a PDF line ends with a hyphen. Main actor: both
/// checkers belong to the interface thread.
@MainActor
enum ReadAloudSpelling {
    /// At most this many candidates are checked per page; a page has a few dozen at most.
    private static let maximumCandidates = 400

    static func dictionaryWords(among candidates: Set<String>, language: String = "en") -> Set<String> {
        var words = Set<String>()
        #if canImport(UIKit)
        let checker = UITextChecker()
        let checkerLanguage = UITextChecker.availableLanguages.first { available in available.hasPrefix(language) } ?? "en_US"
        for candidate in candidates.prefix(maximumCandidates) {
            let range = NSRange(location: 0, length: (candidate as NSString).length)
            if checker.rangeOfMisspelledWord(in: candidate, range: range, startingAt: 0, wrap: false, language: checkerLanguage).location == NSNotFound {
                words.insert(candidate)
            }
        }
        #else
        let checker = NSSpellChecker.shared
        for candidate in candidates.prefix(maximumCandidates) {
            if checker.checkSpelling(of: candidate, startingAt: 0, language: language, wrap: false,
                                     inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound {
                words.insert(candidate)
            }
        }
        #endif
        return words
    }
}
