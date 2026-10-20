import XCTest
@testable import GraphiteCore

/// Settings may rewrite the vault's pronunciation file only when it knows the whole file: a file
/// that is missing (nothing to lose) or that was read completely. Every other outcome says why.
final class ReadAloudPronunciationVaultFileReadingTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PronunciationVaultFile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func write(_ data: Data) throws -> URL {
        let location = folder.appendingPathComponent("pronunciations.json")
        try data.write(to: location)
        return location
    }

    private func termsObject(count: Int) throws -> Data {
        let object = Dictionary(uniqueKeysWithValues: (0..<count).map { index in ("TERM\(index)", "term \(index)") })
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testAMissingFileIsReportedAsNoFileAndMayBeCreated() {
        let reading = ReadAloudPronunciations.readVaultFile(at: folder.appendingPathComponent("absent.json"))
        XCTAssertEqual(reading, .noFile)
        XCTAssertTrue(reading.allowsRewriting)
    }

    func testAFileThatCannotBeReadIsReportedAsReadFailedAndIsNeverRewritten() throws {
        let directoryInPlaceOfFile = folder.appendingPathComponent("pronunciations.json", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryInPlaceOfFile, withIntermediateDirectories: false)
        let reading = ReadAloudPronunciations.readVaultFile(at: directoryInPlaceOfFile)
        guard case .readFailed = reading else { return XCTFail("Expected a read failure, got \(reading)") }
        XCTAssertFalse(reading.allowsRewriting)
    }

    func testBytesThatAreNotJSONAreReportedAsInvalidAndAreNeverRewritten() throws {
        let reading = ReadAloudPronunciations.readVaultFile(at: try write(Data([0xFF, 0xFE, 0x00, 0x7B])))
        XCTAssertEqual(reading, .invalid(.notJSON))
        XCTAssertFalse(reading.allowsRewriting)
    }

    func testJSONCutOffBeforeItsClosingBraceIsReportedAsInvalidAndIsNeverRewritten() throws {
        let reading = ReadAloudPronunciations.readVaultFile(at: try write(Data(#"{"LUT": "L U T", "SIMDRAM": "sim dee"#.utf8)))
        XCTAssertEqual(reading, .invalid(.notJSON))
        XCTAssertFalse(reading.allowsRewriting)
    }

    func testJSONThatIsNotAnObjectOfTermsIsReportedAsInvalidAndIsNeverRewritten() throws {
        let reading = ReadAloudPronunciations.readVaultFile(at: try write(Data(#"["LUT", "L U T"]"#.utf8)))
        XCTAssertEqual(reading, .invalid(.notAnObjectOfTerms))
        XCTAssertFalse(reading.allowsRewriting)
    }

    func testAFileOverTheSizeLimitIsReportedAsInvalidAndIsNeverRewritten() throws {
        let oversized = Data(repeating: UInt8(ascii: " "), count: ReadAloudPronunciations.maximumFileBytes + 1)
        let reading = ReadAloudPronunciations.readVaultFile(at: try write(oversized))
        XCTAssertEqual(reading, .invalid(.overSizeLimit(byteCount: ReadAloudPronunciations.maximumFileBytes + 1)))
        XCTAssertFalse(reading.allowsRewriting)
    }

    func testMoreTermsThanTheListHoldsAreReportedAsPartialAndAreNeverRewritten() throws {
        let termCount = ReadAloudPronunciations.maximumVaultTerms + 500
        let reading = ReadAloudPronunciations.readVaultFile(at: try write(termsObject(count: termCount)))
        guard case .loaded(let entries, let termsInFile) = reading else { return XCTFail("Expected a partial load, got \(reading)") }
        XCTAssertEqual(entries.count, ReadAloudPronunciations.maximumVaultTerms)
        XCTAssertEqual(termsInFile, termCount)
        XCTAssertFalse(reading.allowsRewriting, "Writing the 2,000 loaded terms back would delete the other 500.")
    }

    func testAnEntryThePronunciationListSkipsMakesTheLoadPartialAndNeverRewritten() throws {
        let tooLongTerm = String(repeating: "A", count: 65)
        let reading = ReadAloudPronunciations.readVaultFile(at: try write(Data(#"{"LUT": "L U T", "\#(tooLongTerm)": "x"}"#.utf8)))
        guard case .loaded(let entries, let termsInFile) = reading else { return XCTFail("Expected a partial load, got \(reading)") }
        XCTAssertEqual(entries.map(\.term), ["LUT"])
        XCTAssertEqual(termsInFile, 2)
        XCTAssertFalse(reading.allowsRewriting)
    }

    func testAValidFileIsLoadedWholeSortedByTermAndMayBeRewritten() throws {
        let reading = ReadAloudPronunciations.readVaultFile(
            at: try write(Data(#"{"SIMDRAM": "sim dee ram", "LUT": {"say": "L U T", "ipa": "ɛl juː tiː"}}"#.utf8)))
        XCTAssertEqual(reading, .loaded(
            entries: [
                ReadAloudPronunciations.VaultEntry(term: "LUT", pronunciation: .init(say: "L U T", ipa: "ɛl juː tiː")),
                ReadAloudPronunciations.VaultEntry(term: "SIMDRAM", pronunciation: .init(say: "sim dee ram"))
            ],
            termsInFile: 2))
        XCTAssertTrue(reading.allowsRewriting)
    }

    func testSpeechLookupStillUsesAtMostTheTermLimit() throws {
        let merged = ReadAloudPronunciations(terms: [:]).merging(vaultFile: try termsObject(count: ReadAloudPronunciations.maximumVaultTerms + 500))
        XCTAssertEqual(merged.terms.count, ReadAloudPronunciations.maximumVaultTerms)
    }
}
