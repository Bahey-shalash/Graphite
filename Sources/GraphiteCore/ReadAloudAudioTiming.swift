import Foundation

/// Validated timing for an already prepared passage. Provider character entries
/// may contain several Unicode scalars; they are never treated as UTF-16 indexes.
/// Exact source agreement is required before audio can drive source highlights.
public struct ReadAloudAudioTiming: Equatable, Sendable {
    public struct Word: Equatable, Sendable {
        public let range: NSRange
        public let startSeconds: Double
        public let endSeconds: Double
    }

    public enum ValidationError: Error, Equatable {
        case invalidSize
        case mismatchedText
        case invalidTime
    }

    public let words: [Word]
    public let durationSeconds: Double

    public init(sourceText: String, characters: [String], startTimesSeconds: [Double],
                endTimesSeconds: [Double], durationSeconds: Double) throws {
        guard !sourceText.isEmpty, sourceText.utf16.count <= ReadAloudDocument.maximumPassageUTF16Count,
              !characters.isEmpty, characters.count <= sourceText.utf16.count,
              characters.count == startTimesSeconds.count, characters.count == endTimesSeconds.count,
              characters.allSatisfy({ character in character.count == 1 }) else {
            throw ValidationError.invalidSize
        }
        // Swift String equality allows canonically equivalent spellings. Source
        // coordinates require identical UTF-16 units, including combining marks.
        guard characters.reduce(0, { count, character in count + character.utf16.count }) == sourceText.utf16.count,
              Array(characters.joined().utf16) == Array(sourceText.utf16) else {
            throw ValidationError.mismatchedText
        }
        guard durationSeconds.isFinite, durationSeconds > 0, durationSeconds <= 600 else {
            throw ValidationError.invalidTime
        }
        var characterRanges: [NSRange] = []
        var sourceOffset = 0
        var previousStartSeconds = 0.0
        var previousEndSeconds = 0.0
        for index in characters.indices {
            let startSeconds = startTimesSeconds[index]
            let endSeconds = endTimesSeconds[index]
            guard startSeconds.isFinite, endSeconds.isFinite,
                  startSeconds >= previousStartSeconds, endSeconds >= previousEndSeconds,
                  endSeconds >= startSeconds, endSeconds <= durationSeconds else {
                throw ValidationError.invalidTime
            }
            characterRanges.append(NSRange(location: sourceOffset, length: characters[index].utf16.count))
            sourceOffset += characters[index].utf16.count
            previousStartSeconds = startSeconds
            previousEndSeconds = endSeconds
        }

        var timedWords: [Word] = []
        var characterIndex = 0
        sourceText.enumerateSubstrings(in: sourceText.startIndex..<sourceText.endIndex,
                                       options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            let wordRange = NSRange(range, in: sourceText)
            while characterIndex < characterRanges.count,
                  NSMaxRange(characterRanges[characterIndex]) <= wordRange.location { characterIndex += 1 }
            let firstCharacterIndex = characterIndex
            while characterIndex < characterRanges.count,
                  characterRanges[characterIndex].location < NSMaxRange(wordRange) { characterIndex += 1 }
            guard characterIndex > firstCharacterIndex else { return }
            timedWords.append(Word(range: wordRange, startSeconds: startTimesSeconds[firstCharacterIndex],
                                   endSeconds: endTimesSeconds[characterIndex - 1]))
            // A grapheme may consist of multiple provider scalar entries.
            characterIndex = max(firstCharacterIndex, characterIndex - 1)
        }
        self.words = timedWords
        self.durationSeconds = durationSeconds
    }

    /// Query using the player's actual media clock, including its rate changes.
    /// Silence and punctuation gaps intentionally have no active word.
    public func wordRange(atPlaybackSeconds playbackSeconds: Double) -> NSRange? {
        guard playbackSeconds.isFinite, playbackSeconds >= 0, playbackSeconds < durationSeconds else { return nil }
        var lowerBound = 0
        var upperBound = words.count
        while lowerBound < upperBound {
            let middleIndex = lowerBound + (upperBound - lowerBound) / 2
            if words[middleIndex].startSeconds <= playbackSeconds { lowerBound = middleIndex + 1 }
            else { upperBound = middleIndex }
        }
        guard lowerBound > 0, playbackSeconds < words[lowerBound - 1].endSeconds else { return nil }
        return words[lowerBound - 1].range
    }
}
