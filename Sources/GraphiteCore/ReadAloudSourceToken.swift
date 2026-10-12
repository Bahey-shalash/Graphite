import Foundation

/// One word, or one entire equation, in the semantic reading order. These tokens
/// allow a renderer to validate the complete sequence before assigning locations;
/// repeated words are never relocated by searching for their spelling.
public struct ReadAloudSourceToken: Hashable, Sendable {
    public let text: String
    public let sourceRange: NSRange
    public let isEquation: Bool

    public init(text: String, sourceRange: NSRange, isEquation: Bool = false) {
        self.text = text
        self.sourceRange = sourceRange
        self.isEquation = isEquation
    }

    public static func tokens(in document: ReadAloudDocument) -> [Self] {
        var tokens: [Self] = []
        var previousEquationRange: NSRange?
        for passage in document.passages {
            let speech = passage.text as NSString
            let prose = NSMutableString(string: passage.text)
            for span in passage.spans where span.isEquation {
                // Keep UTF-16 coordinates while excluding mathematical speech from
                // prose tokenization. The rendered equation is a single attachment.
                prose.replaceCharacters(in: span.speechRange, with: String(repeating: " ", count: span.speechRange.length))
                if span.sourceRange != previousEquationRange {
                    tokens.append(Self(text: "\u{FFFC}", sourceRange: span.sourceRange, isEquation: true))
                    previousEquationRange = span.sourceRange
                }
            }
            let proseText = prose as String
            proseText.enumerateSubstrings(in: proseText.startIndex..<proseText.endIndex,
                                         options: [.byWords, .substringNotRequired]) { _, range, _, _ in
                let speechRange = NSRange(range, in: proseText)
                guard let sourceRange = passage.sourceRange(for: speechRange) else { return }
                tokens.append(Self(text: speech.substring(with: speechRange), sourceRange: sourceRange))
            }
        }
        return tokens.sorted { first, second in first.sourceRange.location < second.sourceRange.location }
    }
}
