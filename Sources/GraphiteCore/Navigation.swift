import Foundation

/// Fuzzy matching as in Obsidian's quick switcher and command palette: the query's
/// characters appear in order, and matches at the start of words, in a row, and near
/// the start of a short name score higher.
public enum FuzzyMatcher {
    public struct Match: Equatable, Sendable {
        /// Higher is better.
        public let score: Double
        /// The matched characters' positions in the candidate, as UTF-16 offsets.
        public let matchedRanges: [Range<Int>]
    }

    /// The match of `query` in `candidate`, ignoring case and accents, or nil.
    ///
    /// Both are compared as folded characters, each candidate character giving all of its
    /// folded characters (`ß` gives `ss`, `ﬁ` gives `fi`), so a name matches itself.
    public static func match(_ query: String, in candidate: String) -> Match? {
        let queryCharacters = foldedQueryCharacters(query)
        guard !queryCharacters.isEmpty else { return Match(score: 0, matchedRanges: []) }
        // Most names are ASCII. Their bytes fold and classify without Foundation or Unicode
        // property lookups, which dominate the cost of scoring thousands of names per
        // keystroke; results are the same as the general path's. `\r` is excluded because
        // `\r\n` is one Character, and the general path counts it once.
        if let queryBytes = asciiBytes(of: queryCharacters), candidate.utf8.allSatisfy({ byte in byte < 0x80 && byte != 0x0D }) {
            return asciiMatch(queryBytes, in: Array(candidate.utf8))
        }
        return unicodeMatch(queryCharacters, in: candidate)
    }

    private static func asciiBytes(of characters: [Character]) -> [UInt8]? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(characters.count)
        for character in characters {
            guard let byte = singleASCIIByte(of: character) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }

    /// The match through the general path only, which the ASCII path must agree with.
    static func matchWithoutASCIIPath(_ query: String, in candidate: String) -> Match? {
        let queryCharacters = foldedQueryCharacters(query)
        guard !queryCharacters.isEmpty else { return Match(score: 0, matchedRanges: []) }
        return unicodeMatch(queryCharacters, in: candidate)
    }

    /// The query folded like candidates, without its spaces.
    private static func foldedQueryCharacters(_ query: String) -> [Character] {
        var queryCharacters: [Character] = []
        for character in query { appendFoldedCharacters(of: character, to: &queryCharacters) }
        return queryCharacters.filter { character in !character.isWhitespace }
    }

    private static func asciiMatch(_ query: [UInt8], in candidate: [UInt8]) -> Match? {
        func isLowercase(_ byte: UInt8) -> Bool { (0x61...0x7A).contains(byte) }
        func isUppercase(_ byte: UInt8) -> Bool { (0x41...0x5A).contains(byte) }
        func isLetterOrNumber(_ byte: UInt8) -> Bool { isLowercase(byte) || isUppercase(byte) || (0x30...0x39).contains(byte) }
        let folded = candidate.map { byte in isUppercase(byte) ? byte + 0x20 : byte }
        guard let latestPositions = latestPositions(of: query, in: folded) else { return nil }
        var wordStarts = [Bool](repeating: true, count: candidate.count)
        for index in candidate.indices.dropFirst() {
            let previous = candidate[index - 1]
            wordStarts[index] = !isLetterOrNumber(previous) || (isLowercase(previous) && isUppercase(candidate[index]))
        }
        guard let best = bestPositions(of: query, in: folded, latestPositions: latestPositions, wordStarts: wordStarts, characterCount: candidate.count) else { return nil }
        // One byte is one UTF-16 unit.
        return Match(score: best.score, matchedRanges: mergedRanges(best.positions.map { position in position..<(position + 1) }))
    }

    private static func unicodeMatch(_ query: [Character], in candidate: String) -> Match? {
        let characters = Array(candidate)
        var units: [Character] = []
        var unitCharacterIndices: [Int] = []
        units.reserveCapacity(characters.count)
        unitCharacterIndices.reserveCapacity(characters.count)
        for (characterIndex, character) in characters.enumerated() {
            let foldedCount = appendFoldedCharacters(of: character, to: &units)
            for _ in 0..<foldedCount { unitCharacterIndices.append(characterIndex) }
        }
        guard let latestPositions = latestPositions(of: query, in: units) else { return nil }
        // Only the first of a character's folded characters can start a word.
        let wordStarts = units.indices.map { unitIndex in
            let characterIndex = unitCharacterIndices[unitIndex]
            return (unitIndex == 0 || unitCharacterIndices[unitIndex - 1] != characterIndex) && isWordStart(characterIndex, in: characters)
        }
        guard let best = bestPositions(of: query, in: units, latestPositions: latestPositions, wordStarts: wordStarts, characterCount: characters.count) else { return nil }
        var utf16Offsets: [Int] = []
        utf16Offsets.reserveCapacity(characters.count)
        var offset = 0
        for character in characters {
            utf16Offsets.append(offset)
            offset += character.utf16.count
        }
        let ranges = best.positions.map { position in
            let characterIndex = unitCharacterIndices[position]
            return utf16Offsets[characterIndex]..<(utf16Offsets[characterIndex] + characters[characterIndex].utf16.count)
        }
        return Match(score: best.score, matchedRanges: mergedRanges(ranges))
    }

    /// The latest position each query character can take with the rest of the query still
    /// matching after it (the query matched backwards from the end), or nil when the query
    /// does not appear in order at all.
    private static func latestPositions<Unit: Equatable>(of query: [Unit], in units: [Unit]) -> [Int]? {
        var latestPositions = [Int](repeating: 0, count: query.count)
        var position = units.count - 1
        for queryIndex in query.indices.reversed() {
            while position >= 0 && units[position] != query[queryIndex] { position -= 1 }
            guard position >= 0 else { return nil }
            latestPositions[queryIndex] = position
            position -= 1
        }
        return latestPositions
    }

    /// The best-scoring match positions among greedy matches from each possible start, or nil.
    ///
    /// Each query character goes to its next occurrence, or to a word start further on. A
    /// word start is taken only up to the character's latest position, where the rest of the
    /// query still fits, so skipping ahead never loses a match that exists (`dan` in "Drank a lot").
    private static func bestPositions<Unit: Equatable>(of query: [Unit], in units: [Unit], latestPositions: [Int], wordStarts: [Bool],
                                                       characterCount: Int) -> (score: Double, positions: [Int])? {
        var bestMatch: (score: Double, positions: [Int])?
        var positions: [Int] = []
        positions.reserveCapacity(query.count)
        for start in 0...latestPositions[0] where units[start] == query[0] {
            positions.removeAll(keepingCapacity: true)
            positions.append(start)
            var candidateIndex = start + 1
            for queryIndex in query.indices.dropFirst() {
                // Prefer a word start ahead; otherwise the next occurrence.
                var nextIndex: Int?
                var searchIndex = candidateIndex
                while searchIndex <= latestPositions[queryIndex] {
                    if units[searchIndex] == query[queryIndex] {
                        if nextIndex == nil { nextIndex = searchIndex }
                        if searchIndex == candidateIndex || wordStarts[searchIndex] { nextIndex = searchIndex; break }
                    }
                    searchIndex += 1
                }
                guard let foundIndex = nextIndex else { break }
                positions.append(foundIndex)
                candidateIndex = foundIndex + 1
            }
            guard positions.count == query.count else { continue }
            let score = self.score(positions, wordStarts: wordStarts, characterCount: characterCount)
            if let currentBest = bestMatch, currentBest.score >= score { continue }
            bestMatch = (score, positions)
        }
        return bestMatch
    }

    /// Appends a character's folded form, without case and accents, which may be several
    /// characters; returns how many were appended.
    @discardableResult
    private static func appendFoldedCharacters(of character: Character, to folded: inout [Character]) -> Int {
        // ASCII folds by lowercasing; `\r\n` is one Character of two bytes and is kept whole.
        if let byte = singleASCIIByte(of: character) {
            folded.append((0x41...0x5A).contains(byte) ? Character(Unicode.Scalar(byte + 0x20)) : character)
            return 1
        }
        let foldedText = String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        guard !foldedText.isEmpty else { folded.append(character); return 1 }
        let countBefore = folded.count
        folded.append(contentsOf: foldedText)
        return folded.count - countBefore
    }

    private static func singleASCIIByte(of character: Character) -> UInt8? {
        guard character.utf8.count == 1, let byte = character.utf8.first, byte < 0x80 else { return nil }
        return byte
    }

    private static func isWordStart(_ index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1], current = characters[index]
        // ASCII letters and digits are classified by their bytes, the same answers as the
        // Character properties below without their lookups.
        if let previousByte = singleASCIIByte(of: previous), let currentByte = singleASCIIByte(of: current) {
            let previousIsLowercase = (0x61...0x7A).contains(previousByte)
            let previousIsLetterOrNumber = previousIsLowercase || (0x41...0x5A).contains(previousByte) || (0x30...0x39).contains(previousByte)
            return !previousIsLetterOrNumber || (previousIsLowercase && (0x41...0x5A).contains(currentByte))
        }
        if !previous.isLetter && !previous.isNumber { return true }
        return previous.isLowercase && current.isUppercase
    }

    private static func score(_ positions: [Int], wordStarts: [Bool], characterCount: Int) -> Double {
        var score = 0.0
        for (offset, position) in positions.enumerated() {
            score += 1
            if wordStarts[position] { score += 2 }
            if offset > 0 && positions[offset - 1] == position - 1 { score += 3 }
        }
        if positions.first == 0 { score += 4 }
        // Shorter names and earlier matches rank first.
        score -= Double(positions.first ?? 0) * 0.05
        score -= Double(characterCount) * 0.02
        return score
    }

    /// Ranges in order, with touching ones joined; a character matched through two of its
    /// folded characters (`ß` for `ss`) is one range.
    private static func mergedRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var merged: [Range<Int>] = []
        for range in ranges {
            if let last = merged.last, last.upperBound >= range.lowerBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

/// Back and forward through the documents opened, like a browser's history.
public struct NavigationHistory: Equatable, Sendable {
    public private(set) var entries: [VaultPath] = []
    /// The index of the document on screen, or -1 before the first.
    public private(set) var currentIndex = -1
    /// Older entries are dropped beyond this.
    public static let maximumEntryCount = 100

    public init() {}

    public var current: VaultPath? { entries.indices.contains(currentIndex) ? entries[currentIndex] : nil }
    public var canGoBack: Bool { currentIndex > 0 }
    public var canGoForward: Bool { currentIndex >= 0 && currentIndex < entries.count - 1 }

    /// Records that `path` was opened by following a link, the sidebar, or search. Anything
    /// ahead of the current document is dropped, as in a browser.
    public mutating func visit(_ path: VaultPath) {
        guard path != current else { return }
        if currentIndex < entries.count - 1 { entries.removeSubrange((currentIndex + 1)...) }
        entries.append(path)
        if entries.count > Self.maximumEntryCount { entries.removeFirst(entries.count - Self.maximumEntryCount) }
        currentIndex = entries.count - 1
    }

    public mutating func goBack() -> VaultPath? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return entries[currentIndex]
    }

    public mutating func goForward() -> VaultPath? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return entries[currentIndex]
    }

    /// Follows a rename or move of a file or folder.
    public mutating func replacePrefix(_ oldPath: VaultPath, with newPath: VaultPath) {
        entries = entries.map { entry in (try? entry.replacingPrefix(oldPath, with: newPath)) ?? entry }
    }

    /// Forgets a deleted file or folder. When the current document goes, the one before
    /// it becomes current.
    public mutating func remove(inside removedPath: VaultPath) {
        var keptEntries: [VaultPath] = []
        var newIndex = -1
        for (index, entry) in entries.enumerated() where !entry.isInside(removedPath) {
            // Entries left side by side by the removal would be the same step twice.
            if keptEntries.last != entry { keptEntries.append(entry) }
            if index <= currentIndex { newIndex = keptEntries.count - 1 }
        }
        entries = keptEntries
        currentIndex = entries.isEmpty ? -1 : max(newIndex, 0)
    }
}

/// Recently opened files, newest first, as the quick switcher lists them when empty.
public struct RecentFiles: Equatable, Sendable {
    public private(set) var paths: [VaultPath]
    public static let maximumCount = 30

    public init(paths: [VaultPath] = []) {
        self.paths = Array(paths.prefix(Self.maximumCount))
    }

    public mutating func record(_ path: VaultPath) {
        paths.removeAll { recentPath in recentPath == path }
        paths.insert(path, at: 0)
        if paths.count > Self.maximumCount { paths.removeLast(paths.count - Self.maximumCount) }
    }

    public mutating func replacePrefix(_ oldPath: VaultPath, with newPath: VaultPath) {
        var seen = Set<VaultPath>()
        paths = paths.map { path in (try? path.replacingPrefix(oldPath, with: newPath)) ?? path }.filter { path in seen.insert(path).inserted }
    }

    public mutating func remove(inside removedPath: VaultPath) {
        paths.removeAll { path in path.isInside(removedPath) }
    }
}
