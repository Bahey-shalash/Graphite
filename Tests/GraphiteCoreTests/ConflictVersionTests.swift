import XCTest
@testable import GraphiteCore

final class ConflictVersionTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC") ?? .gmt
    /// 30 September 2026, 12:15:40 UTC.
    private let savedDate = Date(timeIntervalSince1970: 1_790_770_540)

    // MARK: Names of separate copies

    func testASeparateCopyIsNamedLikeAnObsidianConflictFile() {
        XCTAssertEqual(ConflictCopyName.stem(forVersionOf: "Lecture 4", deviceName: "MacBook Pro", date: savedDate, isNote: true, timeZone: utc),
                       "Lecture 4 (Conflicted copy MacBook Pro 202609301215)")
    }

    func testTheNameUsesTheTimeWhereThePersonIs() throws {
        let zurich = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        XCTAssertEqual(ConflictCopyName.stem(forVersionOf: "Notes", deviceName: nil, date: savedDate, isNote: true, timeZone: zurich),
                       "Notes (Conflicted copy 202609301415)")
    }

    func testUnknownDeviceAndDateAreLeftOut() {
        XCTAssertEqual(ConflictCopyName.stem(forVersionOf: "Slides", deviceName: nil, date: nil, isNote: false), "Slides (Conflicted copy)")
        XCTAssertEqual(ConflictCopyName.stem(forVersionOf: "Slides", deviceName: "   ", date: nil, isNote: false), "Slides (Conflicted copy)")
    }

    func testADeviceNameCannotBreakTheFileNameOrLinksToTheNote() throws {
        let stem = ConflictCopyName.stem(forVersionOf: "Plan", deviceName: "Anna's iPad #2 [work] / \"home\" (old)\n", date: nil, isNote: true)
        XCTAssertEqual(stem, "Plan (Conflicted copy Anna's iPad 2 work home old)")
        XCTAssertNil(FileNameRules.problem(with: stem, isNote: true))
        XCTAssertNoThrow(try VaultPath(stem + ".md"))

        // A file that is not a note keeps the characters only links mind.
        XCTAssertEqual(ConflictCopyName.stem(forVersionOf: "Scan", deviceName: "iPad #2 [work]", date: nil, isNote: false), "Scan (Conflicted copy iPad #2 [work])")
    }

    func testALongDeviceNameIsCutAndALongFileNameStillFits() {
        let longDeviceName = String(repeating: "Überlanger Gerätename ", count: 10)
        let cutName = ConflictCopyName.sanitized(longDeviceName, isNote: true)
        XCTAssertLessThanOrEqual(cutName.count, ConflictCopyName.maximumDeviceNameLength)
        XCTAssertFalse(cutName.hasSuffix(" "))

        let longStem = String(repeating: "é", count: 140)
        let stem = ConflictCopyName.stem(forVersionOf: longStem, deviceName: longDeviceName, date: savedDate, isNote: true, timeZone: utc)
        XCTAssertLessThanOrEqual(stem.utf8.count, FileNameRules.maximumFileNameBytes - FileNameRules.reservedSuffixBytes, "Room is left for the extension and a number.")
        XCTAssertTrue(stem.hasSuffix(" 202609301215)"), "The original name is shortened, not what tells the copy apart.")
        XCTAssertTrue(stem.hasPrefix("ééé"))
        XCTAssertNil(FileNameRules.problem(with: stem, isNote: true))
    }

    // MARK: Comparing notes

    private typealias Line = TextVersionComparison.Line

    func testIdenticalTextsHaveNoDifferences() throws {
        let comparison = try XCTUnwrap(TextVersionComparison.compare(current: "one\ntwo\n", otherVersion: "one\ntwo\n"))
        XCTAssertEqual(comparison.lines, [.unchanged("one"), .unchanged("two")])
        XCTAssertTrue(comparison.isIdentical)
    }

    func testLinesOfEachVersionAreShownInReadingOrder() throws {
        let current = "# Lecture\nfirst\nsecond\nthird\nlast\n"
        let other = "# Lecture\nfirst\nsecond, edited elsewhere\nthird\nadded elsewhere\nlast\n"
        let comparison = try XCTUnwrap(TextVersionComparison.compare(current: current, otherVersion: other))
        XCTAssertEqual(comparison.lines, [
            .unchanged("# Lecture"), .unchanged("first"),
            .onlyInCurrent("second"), .onlyInOtherVersion("second, edited elsewhere"),
            .unchanged("third"),
            .onlyInOtherVersion("added elsewhere"),
            .unchanged("last"),
        ])
        XCTAssertEqual(comparison.linesOnlyInCurrent, 1)
        XCTAssertEqual(comparison.linesOnlyInOtherVersion, 2)
        XCTAssertFalse(comparison.isIdentical)
    }

    func testEveryLineOfBothVersionsIsAccountedFor() throws {
        let current = (0..<200).map { number in number % 7 == 0 ? "current \(number)" : "shared \(number)" }.joined(separator: "\n")
        let other = (0..<230).map { number in number % 5 == 0 ? "other \(number)" : "shared \(number)" }.joined(separator: "\n")
        let comparison = try XCTUnwrap(TextVersionComparison.compare(current: current, otherVersion: other))
        let rebuiltCurrent = comparison.lines.compactMap { line -> String? in
            switch line {
            case .unchanged(let text), .onlyInCurrent(let text): text
            case .onlyInOtherVersion: nil
            }
        }
        let rebuiltOther = comparison.lines.compactMap { line -> String? in
            switch line {
            case .unchanged(let text), .onlyInOtherVersion(let text): text
            case .onlyInCurrent: nil
            }
        }
        XCTAssertEqual(rebuiltCurrent.joined(separator: "\n"), current, "The current note can be read off the comparison.")
        XCTAssertEqual(rebuiltOther.joined(separator: "\n"), other, "So can the other version.")
    }

    func testLineEndingsAloneAreNotADifference() throws {
        let comparison = try XCTUnwrap(TextVersionComparison.compare(current: "one\r\ntwo\r\n", otherVersion: "one\ntwo"))
        XCTAssertTrue(comparison.isIdentical)
        XCTAssertEqual(comparison.lines, [.unchanged("one"), .unchanged("two")])
    }

    func testAnEmptyVersionAndBlankLinesAreCompared() throws {
        let comparison = try XCTUnwrap(TextVersionComparison.compare(current: "", otherVersion: "new\n\ntext\n"))
        XCTAssertEqual(comparison.lines, [.onlyInOtherVersion("new"), .onlyInOtherVersion(""), .onlyInOtherVersion("text")])
        let emptied = try XCTUnwrap(TextVersionComparison.compare(current: "kept\n", otherVersion: ""))
        XCTAssertEqual(emptied.lines, [.onlyInCurrent("kept")])
    }

    func testTextThatCombinesCharactersIsComparedAsWritten() throws {
        let comparison = try XCTUnwrap(TextVersionComparison.compare(current: "café ☕️\n数学\n", otherVersion: "café ☕️\n数学 II\n"))
        XCTAssertEqual(comparison.lines, [.unchanged("café ☕️"), .onlyInCurrent("数学"), .onlyInOtherVersion("数学 II")])
    }

    func testVersionsThatDifferOverTooManyLinesAreNotCompared() {
        let manyLines = (0...TextVersionComparison.maximumComparedLines).map { number in "line \(number)" }.joined(separator: "\n")
        XCTAssertNil(TextVersionComparison.compare(current: "", otherVersion: manyLines))
        XCTAssertNil(TextVersionComparison.compare(current: manyLines, otherVersion: "rewritten"))
    }

    func testALongNoteWithASmallChangeIsComparedWhateverItsLength() throws {
        var lines = (0..<50_000).map { number in "line \(number)" }
        let current = lines.joined(separator: "\n")
        lines[25_000] = "changed elsewhere"
        let comparison = try XCTUnwrap(TextVersionComparison.compare(current: current, otherVersion: lines.joined(separator: "\n")),
                                       "What the versions share at the start and the end does not count against the limit.")
        XCTAssertEqual(comparison.lines.count, 50_001)
        XCTAssertEqual(comparison.linesOnlyInCurrent, 1)
        XCTAssertEqual(comparison.linesOnlyInOtherVersion, 1)
    }

    // MARK: Noticing a changed file

    func testAStampChangesWhenTheFileIsRewritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Stamp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("Note.md")
        try Data("first".utf8).write(to: location)
        let stamp = FileChangeStamp.of(location)
        XCTAssertEqual(stamp.byteCount, 5)
        XCTAssertEqual(FileChangeStamp.of(location), stamp, "A file left alone keeps its stamp.")

        try Data("longer text".utf8).write(to: location)
        XCTAssertNotEqual(FileChangeStamp.of(location), stamp)

        // The same size, written later.
        let sameSizeStamp = FileChangeStamp.of(location)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(5)], ofItemAtPath: location.path)
        XCTAssertNotEqual(FileChangeStamp.of(location), sameSizeStamp)

        try FileManager.default.removeItem(at: location)
        XCTAssertEqual(FileChangeStamp.of(location), FileChangeStamp(modified: nil, byteCount: nil), "A file that is gone has no stamp.")
    }
}
