import Foundation

/// Checks a passage a downloaded voice rendered before anyone hears it. Autoregressive speech
/// models sometimes babble: they loop on a syllable, invent words, run on long after the text
/// ended, or fall silent for seconds. The on-device recognition already run for the word
/// highlight tells whether the words that were asked for were said; the audio itself tells how
/// long it ran and how long it was silent.
public enum ReadAloudRenderCheck {
    public enum Problem: Equatable, Sendable, CustomStringConvertible {
        /// Too little of the passage was recognized: the share of its letters that was.
        case lowCoverage(Double)
        /// The audio is this many times longer than the text should take.
        case tooLong(Double)
        /// A word or short phrase repeats over and over where the text does not.
        case repeatedLoop(String)
        /// Silence of this many seconds inside the audio.
        case longSilence(Double)

        public var description: String {
            switch self {
            case .lowCoverage(let share): "only \(Int((share * 100).rounded())) % of the text was heard"
            case .tooLong(let ratio): String(format: "%.1f times longer than expected", ratio)
            case .repeatedLoop(let phrase): "a loop repeating “\(phrase)”"
            case .longSilence(let seconds): String(format: "%.1f s of silence", seconds)
            }
        }
    }

    /// The share of the text's letters that must be heard, in order. Recognition writes
    /// acronyms and splits names its own way ("C Moss" for CMOS), so the comparison is letter
    /// by letter; clean renderings of the owner's term list scored above 0.9, babbling below 0.6.
    public static let minimumCoverage = 0.8
    /// How much longer than expected audio may run before it counts as running on.
    public static let maximumDurationRatio = 1.8
    /// Silence longer than this inside a passage is not a pause any voice makes on purpose.
    public static let maximumSilenceSeconds = 2.5
    /// Speech of a calm narrator, in characters of text per second: Pocket TTS and Qwen3-TTS
    /// read the audition passages at 13 to 15.
    public static let charactersPerSecond = 14.0

    /// How long the text should take to say: its characters at a calm pace, plus the pauses
    /// voices make at commas and at the ends of sentences, which dominate in lists of terms.
    public static func expectedDurationSeconds(for text: String) -> Double {
        let commas = text.filter { character in character == "," || character == ";" || character == ":" }.count
        let sentenceEnds = text.filter { character in character == "." || character == "?" || character == "!" }.count
        return max(1, Double(text.count) / charactersPerSecond + 0.25 * Double(commas) + 0.4 * Double(sentenceEnds))
    }

    /// Every problem found. `recognized` is nil when recognition was not available; the checks
    /// that need it are then skipped rather than failed.
    public static func problems(text: String, recognized: [ReadAloudRecognizedWord]?, durationSeconds: Double,
                                longestSilenceSeconds: Double) -> [Problem] {
        var found: [Problem] = []
        let expected = expectedDurationSeconds(for: text)
        // Short passages vary a lot in relative terms, so a few seconds of slack are allowed too.
        if durationSeconds > expected * maximumDurationRatio, durationSeconds > expected + 4 {
            found.append(.tooLong(durationSeconds / expected))
        }
        if longestSilenceSeconds > maximumSilenceSeconds {
            found.append(.longSilence(longestSilenceSeconds))
        }
        if let recognized {
            let coverage = self.coverage(text: text, recognized: recognized)
            if coverage < minimumCoverage { found.append(.lowCoverage(coverage)) }
            if let loop = repeatedLoop(in: recognized.map(\.text), comparedWith: text) { found.append(.repeatedLoop(loop)) }
        }
        return found
    }

    /// The share of the text's letters and digits found, in order, in what was heard: the
    /// longest common subsequence of the two letter streams, divided by the text's length.
    public static func coverage(text: String, recognized: [ReadAloudRecognizedWord]) -> Double {
        let written = Array(ReadAloudWordAlignment.normalize(text))
        guard !written.isEmpty else { return 1 }
        let heard = Array(recognized.map { word in ReadAloudWordAlignment.normalize(word.text) }.joined())
        guard !heard.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: heard.count + 1)
        var current = previous
        for writtenCharacter in written {
            for (index, heardCharacter) in heard.enumerated() {
                current[index + 1] = writtenCharacter == heardCharacter ? previous[index] + 1 : max(previous[index + 1], current[index])
            }
            swap(&previous, &current)
        }
        return Double(previous[heard.count]) / Double(written.count)
    }

    /// The most repeated phrase of one to four words when it repeats at least four times in a
    /// row and the text itself never repeats it twice in a row; also a single recognized token
    /// that is one short syllable over and over ("rdfrdfrdfrdf").
    public static func repeatedLoop(in recognizedWords: [String], comparedWith text: String) -> String? {
        let heard = recognizedWords.map(ReadAloudWordAlignment.normalize).filter { word in !word.isEmpty }
        let written = ReadAloudWordAlignment.words(in: text).map(\.normalized)
        for token in heard where token.count >= 9 {
            for unitLength in 1...4 where token.count % unitLength == 0 && token.count / unitLength >= 4 {
                let unit = String(token.prefix(unitLength))
                if String(repeating: unit, count: token.count / unitLength) == token { return unit }
            }
        }
        for phraseLength in 1...4 where heard.count >= phraseLength * 4 {
            var index = 0
            while index + phraseLength <= heard.count {
                let phrase = Array(heard[index..<index + phraseLength])
                var repeats = 1
                var next = index + phraseLength
                while next + phraseLength <= heard.count, Array(heard[next..<next + phraseLength]) == phrase {
                    repeats += 1
                    next += phraseLength
                }
                if repeats >= 4, maximumConsecutiveRepeats(of: phrase, in: written) < 2 {
                    return phrase.joined(separator: " ")
                }
                index += 1
            }
        }
        return nil
    }

    static func maximumConsecutiveRepeats(of phrase: [String], in words: [String]) -> Int {
        guard !phrase.isEmpty, words.count >= phrase.count else { return 0 }
        var best = 0
        var index = 0
        while index + phrase.count <= words.count {
            var repeats = 0
            var next = index
            while next + phrase.count <= words.count, Array(words[next..<next + phrase.count]) == phrase {
                repeats += 1
                next += phrase.count
            }
            best = max(best, repeats)
            index += max(1, repeats * phrase.count)
        }
        return best
    }

    /// The longest stretch of near silence, in seconds, measured in 50 ms windows; silence
    /// at the very start and end is trimmed first, since every voice pads a little there.
    public static func longestSilenceSeconds(samples: [Float], sampleRate: Int) -> Double {
        guard sampleRate > 0, !samples.isEmpty else { return 0 }
        let windowLength = max(1, sampleRate / 20)
        // About -46 dBFS: well below speech, above the faint noise floor of codec output.
        let threshold: Float = 0.005
        var levels: [Float] = []
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + windowLength)
            var sum: Float = 0
            for index in start..<end { sum += samples[index] * samples[index] }
            levels.append((sum / Float(end - start)).squareRoot())
            start = end
        }
        guard let first = levels.firstIndex(where: { level in level >= threshold }),
              let last = levels.lastIndex(where: { level in level >= threshold }) else { return 0 }
        var longest = 0, current = 0
        for level in levels[first...last] {
            if level < threshold { current += 1; longest = max(longest, current) } else { current = 0 }
        }
        return Double(longest * windowLength) / Double(sampleRate)
    }
}
