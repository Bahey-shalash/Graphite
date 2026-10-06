import Foundation

/// A version of a file that iCloud or another file provider kept beside the current one,
/// because the file was changed in two places and the provider could not tell which
/// change should win.
public struct FileConflictVersion: Identifiable, Equatable, Sendable {
    /// Names the version among those of its file, for as long as the provider keeps it.
    public let id: String
    /// The device the version was saved on, when the provider recorded it.
    public let deviceName: String?
    /// The person who saved the version, for a file shared with others.
    public let savedBy: String?
    public let modified: Date?
    public let byteCount: Int?
    /// False when the provider has the version but has not downloaded its contents.
    public let hasLocalContents: Bool

    public init(id: String, deviceName: String?, savedBy: String? = nil, modified: Date?, byteCount: Int?, hasLocalContents: Bool = true) {
        self.id = id; self.deviceName = deviceName; self.savedBy = savedBy
        self.modified = modified; self.byteCount = byteCount; self.hasLocalContents = hasLocalContents
    }
}

/// A file's size and modification time: enough to notice that it changed since it was
/// looked at, without reading it.
public struct FileChangeStamp: Equatable, Sendable {
    public let modified: Date?
    public let byteCount: Int?

    public init(modified: Date?, byteCount: Int?) {
        self.modified = modified; self.byteCount = byteCount
    }

    public static func of(_ location: URL) -> FileChangeStamp {
        // A URL keeps the values it read before; a change since then must be seen.
        var freshLocation = location
        freshLocation.removeAllCachedResourceValues()
        let values = try? freshLocation.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return FileChangeStamp(modified: values?.contentModificationDate, byteCount: values?.fileSize)
    }
}

/// The name a conflict version gets when it is kept as a file of its own, in the form
/// Obsidian Sync gives its conflict files: "Lecture (Conflicted copy MacBook 202609301215).md".
public enum ConflictCopyName {
    /// The longest device name kept in a file name.
    static let maximumDeviceNameLength = 40

    /// The stem of the separate file for a version of the file whose stem is `originalStem`.
    /// - Parameters:
    ///   - deviceName: The device the version was saved on; left out when unknown.
    ///   - date: When the version was saved; left out when unknown.
    ///   - isNote: A note's name must not contain the characters that break links to it.
    public static func stem(forVersionOf originalStem: String, deviceName: String?, date: Date?, isNote: Bool,
                            timeZone: TimeZone = .current) -> String {
        var details = ["Conflicted copy"]
        if let deviceName = deviceName.map({ deviceName in sanitized(deviceName, isNote: isNote) }), !deviceName.isEmpty { details.append(deviceName) }
        if let date { details.append(timestamp(date, timeZone: timeZone)) }
        let suffix = " (" + details.joined(separator: " ") + ")"
        // Room is left for the extension and a number that tells two copies apart.
        let maximumStemBytes = FileNameRules.maximumFileNameBytes - FileNameRules.reservedSuffixBytes - suffix.utf8.count
        var shortenedStem = originalStem
        while shortenedStem.utf8.count > max(maximumStemBytes, 1), !shortenedStem.isEmpty { shortenedStem.removeLast() }
        return shortenedStem + suffix
    }

    /// A device name with the characters no file name, or no note's name, may contain
    /// taken out. People name devices freely ("Anna's iPad #2").
    static func sanitized(_ deviceName: String, isNote: Bool) -> String {
        var forbidden = FileNameRules.forbiddenCharacters.union(FileNameRules.controlCharacters).union(CharacterSet(charactersIn: "()"))
        if isNote { forbidden.formUnion(FileNameRules.linkBreakingCharacters) }
        let allowedText = String(String.UnicodeScalarView(deviceName.unicodeScalars.filter { scalar in !forbidden.contains(scalar) }))
        let words = allowedText.split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(maximumDeviceNameLength)).trimmingCharacters(in: .whitespaces)
    }

    /// "202609301215": a fixed form without separators, so no region adds characters a
    /// file name cannot hold.
    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04ld%02ld%02ld%02ld%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0, components.hour ?? 0, components.minute ?? 0)
    }
}

/// Two versions of a note, compared line by line.
public struct TextVersionComparison: Equatable, Sendable {
    public enum Line: Equatable, Sendable {
        case unchanged(String)
        case onlyInCurrent(String)
        case onlyInOtherVersion(String)
    }

    /// Every line of both versions, in reading order.
    public let lines: [Line]

    /// Beyond this many lines that differ between the versions' common beginning and end,
    /// comparing takes too long to wait for; the versions are then shown without it.
    public static let maximumComparedLines = 4_000

    public var linesOnlyInCurrent: Int { lines.count { line in if case .onlyInCurrent = line { true } else { false } } }
    public var linesOnlyInOtherVersion: Int { lines.count { line in if case .onlyInOtherVersion = line { true } else { false } } }
    public var isIdentical: Bool { linesOnlyInCurrent == 0 && linesOnlyInOtherVersion == 0 }

    /// Compares `current` with `otherVersion`; nil when they differ over too many lines.
    /// Lines that differ only in their line ending (`\r\n` against `\n`) count as the same.
    public static func compare(current: String, otherVersion: String) -> TextVersionComparison? {
        let currentLines = textLines(of: current), otherLines = textLines(of: otherVersion)
        var commonPrefixCount = 0
        while commonPrefixCount < min(currentLines.count, otherLines.count), currentLines[commonPrefixCount] == otherLines[commonPrefixCount] { commonPrefixCount += 1 }
        var commonSuffixCount = 0
        while commonSuffixCount < min(currentLines.count, otherLines.count) - commonPrefixCount,
              currentLines[currentLines.count - 1 - commonSuffixCount] == otherLines[otherLines.count - 1 - commonSuffixCount] { commonSuffixCount += 1 }
        let differingCurrentLines = Array(currentLines[commonPrefixCount..<(currentLines.count - commonSuffixCount)])
        let differingOtherLines = Array(otherLines[commonPrefixCount..<(otherLines.count - commonSuffixCount)])
        guard differingCurrentLines.count <= maximumComparedLines, differingOtherLines.count <= maximumComparedLines else { return nil }

        let difference = differingOtherLines.difference(from: differingCurrentLines)
        var removedOffsets = Set<Int>(), insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removedOffsets.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }
        var lines = currentLines[..<commonPrefixCount].map(Line.unchanged)
        var currentIndex = 0, otherIndex = 0
        while currentIndex < differingCurrentLines.count || otherIndex < differingOtherLines.count {
            if currentIndex < differingCurrentLines.count, removedOffsets.contains(currentIndex) {
                lines.append(.onlyInCurrent(differingCurrentLines[currentIndex])); currentIndex += 1
            } else if otherIndex < differingOtherLines.count, insertedOffsets.contains(otherIndex) {
                lines.append(.onlyInOtherVersion(differingOtherLines[otherIndex])); otherIndex += 1
            } else if currentIndex < differingCurrentLines.count {
                lines.append(.unchanged(differingCurrentLines[currentIndex])); currentIndex += 1; otherIndex += 1
            } else {
                // Every line left of the other version is an insertion; nothing else is possible.
                break
            }
        }
        lines += currentLines[(currentLines.count - commonSuffixCount)...].map(Line.unchanged)
        return TextVersionComparison(lines: lines)
    }

    /// The text's lines without their line endings. A final line ending adds no empty line.
    static func textLines(of text: String) -> [String] {
        // Split by code unit: to Swift a "\r\n" is one character, which holds no "\n".
        var lines = text.components(separatedBy: "\n").map { line in line.hasSuffix("\r") ? String(line.dropLast()) : line }
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}
