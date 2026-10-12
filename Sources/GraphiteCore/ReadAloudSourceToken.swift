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
            for span in passage.spans where !span.isEquation {
                guard let writtenText = span.writtenText else { continue }
                // Said differently from how it is written: the rendered note shows the
                // written words, so those are the tokens, at their place in the source.
                prose.replaceCharacters(in: span.speechRange, with: String(repeating: " ", count: span.speechRange.length))
                guard span.sourceRange.length == writtenText.utf16.count else { continue }
                writtenText.enumerateSubstrings(in: writtenText.startIndex..<writtenText.endIndex,
                                                options: [.byWords, .substringNotRequired]) { _, range, _, _ in
                    let wordRange = NSRange(range, in: writtenText)
                    tokens.append(Self(text: (writtenText as NSString).substring(with: wordRange),
                                       sourceRange: NSRange(location: span.sourceRange.location + wordRange.location, length: wordRange.length)))
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
