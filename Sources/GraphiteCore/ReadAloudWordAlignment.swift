import Foundation

/// A word speech recognition heard in rendered audio, with when it was heard.
public struct ReadAloudRecognizedWord: Equatable, Sendable {
    public let text: String
    public let startSeconds: Double
    public let endSeconds: Double

    public init(text: String, startSeconds: Double, endSeconds: Double) {
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

/// A word of a passage's text and when the rendered audio says it. Ranges are UTF-16 offsets
/// into the passage's speech text, the same units the highlight already uses.
public struct ReadAloudTimedWord: Equatable, Sendable, Codable {
    public let location: Int
    public let length: Int
    public let startSeconds: Double
    public let endSeconds: Double

    public init(location: Int, length: Int, startSeconds: Double, endSeconds: Double) {
        self.location = location
        self.length = length
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public var range: NSRange { NSRange(location: location, length: length) }
}

/// Neural voices report no word timings, so after a passage is rendered its audio is run
/// through on-device speech recognition and the recognized words are matched back to the
/// passage's own words. Words the recognizer missed or misheard take their time from their
/// matched neighbors, shared by length. When too few words match, the alignment is refused
/// and the caller highlights the whole passage instead of guessing.
public enum ReadAloudWordAlignment {
    /// The share of the passage's words that must be matched for the timings to be trusted.
    public static let minimumMatchedShare = 0.5

    /// The passage's words with their UTF-16 ranges, as the highlight counts them.
    public static func words(in text: String) -> [(range: NSRange, normalized: String)] {
        var words: [(range: NSRange, normalized: String)] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { substring, range, _, _ in
            guard let substring else { return }
            let normalized = normalize(substring)
            guard !normalized.isEmpty else { return }
            words.append((NSRange(range, in: text), normalized))
        }
        return words
    }

    /// Lowercase letters and digits only, accents removed: "Résumé," and "resume" compare equal.
    public static func normalize(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }

    /// Timings for every word of the passage, in order, or nil when the recognized words do not
    /// match the passage well enough.
    public static func align(passage: String, recognized: [ReadAloudRecognizedWord], audioDurationSeconds: Double) -> [ReadAloudTimedWord]? {
        let passageWords = words(in: passage)
        let heardWords = recognized.compactMap { word -> (normalized: String, word: ReadAloudRecognizedWord)? in
            let normalized = normalize(word.text)
            return normalized.isEmpty ? nil : (normalized, word)
        }
        guard !passageWords.isEmpty, !heardWords.isEmpty, audioDurationSeconds > 0 else { return nil }
        let matches = matchedPairs(passageWords.map(\.normalized), heardWords.map(\.normalized))
        guard Double(matches.count) / Double(passageWords.count) >= minimumMatchedShare else { return nil }

        var starts = [Double?](repeating: nil, count: passageWords.count)
        var ends = [Double?](repeating: nil, count: passageWords.count)
        for (passageIndex, heardIndex) in matches {
            starts[passageIndex] = max(0, min(audioDurationSeconds, heardWords[heardIndex].word.startSeconds))
            ends[passageIndex] = max(0, min(audioDurationSeconds, heardWords[heardIndex].word.endSeconds))
        }
        fillUnmatchedWords(passageWords.map(\.range.length), starts: &starts, ends: &ends, audioDurationSeconds: audioDurationSeconds)
        return passageWords.indices.map { index in
            let start = starts[index] ?? 0
            return ReadAloudTimedWord(location: passageWords[index].range.location, length: passageWords[index].range.length,
                                      startSeconds: start, endSeconds: max(start, ends[index] ?? start))
        }
    }

    /// Spreads each run of unmatched words over the gap between its matched neighbors, longer
    /// words taking more time, and keeps every start at or after the previous one.
    static func fillUnmatchedWords(_ lengths: [Int], starts: inout [Double?], ends: inout [Double?], audioDurationSeconds: Double) {
        var index = 0
        while index < lengths.count {
            guard starts[index] == nil else { index += 1; continue }
            let runStart = index
            while index < lengths.count, starts[index] == nil { index += 1 }
            let runEnd = index
            let gapStart = runStart > 0 ? (ends[runStart - 1] ?? 0) : 0
            let gapEnd = runEnd < lengths.count ? (starts[runEnd] ?? audioDurationSeconds) : audioDurationSeconds
            let span = max(0, gapEnd - gapStart)
            let totalLength = Double(lengths[runStart..<runEnd].reduce(0) { total, length in total + max(1, length) })
            var cursor = gapStart
            for wordIndex in runStart..<runEnd {
                let share = span * Double(max(1, lengths[wordIndex])) / totalLength
                starts[wordIndex] = cursor
                ends[wordIndex] = cursor + share
                cursor += share
            }
        }
        // Recognition can report overlapping times for adjacent words; the highlight only
        // moves forward.
        var latestStart = 0.0
        for index in starts.indices {
            let start = max(latestStart, starts[index] ?? latestStart)
            starts[index] = start
            latestStart = start
        }
    }

    /// The best monotonic pairing of passage words with heard words, scored so exact matches
    /// win over near ones and skipped words cost a little: a global sequence alignment.
    static func matchedPairs(_ passage: [String], _ heard: [String]) -> [(passageIndex: Int, heardIndex: Int)] {
        let rowCount = passage.count + 1, columnCount = heard.count + 1
        let gapScore = -1, mismatchScore = -2
        var scores = [Int](repeating: 0, count: rowCount * columnCount)
        for row in 1..<rowCount { scores[row * columnCount] = row * gapScore }
        for column in 1..<columnCount { scores[column] = column * gapScore }
        for row in 1..<rowCount {
            for column in 1..<columnCount {
                let similarity = similarityScore(passage[row - 1], heard[column - 1])
                let diagonal = scores[(row - 1) * columnCount + column - 1] + (similarity > 0 ? similarity : mismatchScore)
                let skipPassageWord = scores[(row - 1) * columnCount + column] + gapScore
                let skipHeardWord = scores[row * columnCount + column - 1] + gapScore
                scores[row * columnCount + column] = max(diagonal, skipPassageWord, skipHeardWord)
            }
        }
        var pairs: [(passageIndex: Int, heardIndex: Int)] = []
        var row = passage.count, column = heard.count
        while row > 0, column > 0 {
            let similarity = similarityScore(passage[row - 1], heard[column - 1])
            let current = scores[row * columnCount + column]
            if similarity > 0, current == scores[(row - 1) * columnCount + column - 1] + similarity {
                pairs.append((row - 1, column - 1))
                row -= 1; column -= 1
            } else if current == scores[(row - 1) * columnCount + column] + gapScore {
                row -= 1
            } else if current == scores[row * columnCount + column - 1] + gapScore {
                column -= 1
            } else {
                row -= 1; column -= 1
            }
        }
        return pairs.reversed()
    }

    /// 3 for the same word, 1 for a near one (a plural, a dropped letter, a shared stem of at
    /// least four letters), 0 otherwise.
    static func similarityScore(_ first: String, _ second: String) -> Int {
        if first == second { return 3 }
        let shorter = first.count <= second.count ? first : second
        let longer = first.count <= second.count ? second : first
        if shorter.count >= 4, longer.hasPrefix(shorter) { return 1 }
        if shorter.count >= 4, longer.count - shorter.count <= 1, editDistance(first, second) <= 1 { return 1 }
        return 0
    }

    static func editDistance(_ first: String, _ second: String) -> Int {
        let firstCharacters = Array(first), secondCharacters = Array(second)
        var previous = Array(0...secondCharacters.count)
        for (firstIndex, firstCharacter) in firstCharacters.enumerated() {
            var current = [firstIndex + 1] + [Int](repeating: 0, count: secondCharacters.count)
            for (secondIndex, secondCharacter) in secondCharacters.enumerated() {
                current[secondIndex + 1] = min(previous[secondIndex + 1] + 1, current[secondIndex] + 1,
                                               previous[secondIndex] + (firstCharacter == secondCharacter ? 0 : 1))
            }
            previous = current
        }
        return previous[secondCharacters.count]
    }

    /// The word being said at a playback time: the last word that has started.
    public static func word(at seconds: Double, in timings: [ReadAloudTimedWord]) -> ReadAloudTimedWord? {
        var low = 0, high = timings.count
        while low < high {
            let middle = (low + high) / 2
            if timings[middle].startSeconds <= seconds { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? timings[low - 1] : nil
    }

    /// Where playback starts to read from a character offset: the start of the first word at
    /// or after it, so resuming mid-passage begins on a word boundary.
    public static func startSeconds(forOffset offset: Int, in timings: [ReadAloudTimedWord]) -> Double {
        timings.first { word in word.location + word.length > offset }?.startSeconds ?? 0
    }
}
