import Foundation

/// When each event of a spoken passage happens if nothing is heard: the pace of a voice worked
/// out from the text and the speed, so a silent reading takes about as long as a spoken one and
/// the screens that follow it (highlight, page turns, Now Playing) see the same sequence of events.
/// The numbers are an even voice's: about 170 words a minute at speed 1, with a short breath at
/// each comma and a longer one at each sentence end.
struct SilentSpeechPacing {
    enum Event: Equatable {
        case started
        case word(NSRange)
        case finished
    }

    /// An event and how long after the one before it (or, for the first, after the reading was
    /// asked for) it happens, in seconds.
    struct Step: Equatable {
        let delaySeconds: Double
        let event: Event
    }

    /// Seconds a word takes at speed 1, before its punctuation: a short fixed part and a part per letter.
    static let secondsPerWordAtNormalSpeed = 0.12
    static let secondsPerCharacterAtNormalSpeed = 0.045
    static let secondsAfterComma = 0.1
    static let secondsAfterSentence = 0.25

    static func schedule(for text: String, speed: Double, leadingPauseSeconds: Double) -> [Step] {
        let safeSpeed = max(speed, 0.1)
        let source = text as NSString
        let words = wordRanges(in: source)
        var steps = [Step(delaySeconds: max(0, leadingPauseSeconds), event: .started)]
        var secondsOfPreviousWord = 0.0
        for range in words {
            steps.append(Step(delaySeconds: secondsOfPreviousWord, event: .word(range)))
            secondsOfPreviousWord = seconds(ofWord: source.substring(with: range), speed: safeSpeed)
        }
        steps.append(Step(delaySeconds: secondsOfPreviousWord, event: .finished))
        return steps
    }

    /// The runs of characters between white space, as the synthesizer reports a word.
    private static func wordRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var wordStart: Int?
        for index in 0..<source.length {
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(source.character(at: index)) ?? "a")
            if isSpace, let start = wordStart {
                ranges.append(NSRange(location: start, length: index - start))
                wordStart = nil
            } else if !isSpace, wordStart == nil {
                wordStart = index
            }
        }
        if let start = wordStart { ranges.append(NSRange(location: start, length: source.length - start)) }
        return ranges
    }

    /// How long the passage takes from its start to its end, without the leading pause.
    static func durationSeconds(of text: String, speed: Double) -> Double {
        schedule(for: text, speed: speed, leadingPauseSeconds: 0).dropFirst().reduce(0) { total, step in total + step.delaySeconds }
    }

    private static func seconds(ofWord word: String, speed: Double) -> Double {
        var seconds = secondsPerWordAtNormalSpeed + secondsPerCharacterAtNormalSpeed * Double(word.count)
        if let last = word.last {
            if ".!?".contains(last) { seconds += secondsAfterSentence } else if ",;:".contains(last) { seconds += secondsAfterComma }
        }
        return seconds / speed
    }
}
