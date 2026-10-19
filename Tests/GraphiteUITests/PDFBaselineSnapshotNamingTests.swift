import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Copies of an open PDF are named `Graphite-OpenPDF-<process>-<UUID>.pdf` in the temporary
/// folder, so a copy left by an ended process (iOS suspends apps without running their
/// deinitializers) is told from one in use and removed. History page copies over 1 MiB are
/// named the same way.
final class PDFBaselineSnapshotNamingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFBaselineSnapshotNaming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func assertNamedLikeABaselineCopy(_ location: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(location.deletingLastPathComponent().standardizedFileURL.path, FileManager.default.temporaryDirectory.standardizedFileURL.path,
                       "In the temporary folder.", file: file, line: line)
        let filename = location.lastPathComponent
        XCTAssertEqual(PDFBaselineSnapshot.filenamePrefix, "Graphite-OpenPDF-", file: file, line: line)
        XCTAssertTrue(filename.hasSuffix(".pdf"), file: file, line: line)
        let processAndUUID = filename.dropFirst("Graphite-OpenPDF-".count).dropLast(".pdf".count)
        let processText = processAndUUID.prefix { $0 != "-" }
        XCTAssertEqual(pid_t(processText), ProcessInfo.processInfo.processIdentifier, "Names the process that made it.", file: file, line: line)
        let uuidText = processAndUUID.dropFirst(processText.count + 1)
        XCTAssertNotNil(UUID(uuidString: String(uuidText)), "Then a UUID: \(filename)", file: file, line: line)
    }

    func testANewBaselineCopyIsNamedWithTheProcessAndAUniqueIdentifier() {
        let first = PDFBaselineSnapshot.makeLocation(), second = PDFBaselineSnapshot.makeLocation()
        assertNamedLikeABaselineCopy(first)
        assertNamedLikeABaselineCopy(second)
        XCTAssertNotEqual(first, second)
    }

    func testOnlyPDFCopiesOfEndedProcessesAreRemoved() throws {
        let prefix = PDFBaselineSnapshot.filenamePrefix
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let launchdProcess = 1  // Runs as another user: signalling it is not permitted, which still shows that it runs.
        let kept = [
            "\(prefix)\(ownProcess)-\(UUID().uuidString).pdf",
            "\(prefix)\(launchdProcess)-\(UUID().uuidString).pdf",
            "Graphite-OpenPDF-\(ownProcess)-\(UUID().uuidString).pdf.part",
            "Lecture.pdf",
            "Other-OpenPDF-99999999-\(UUID().uuidString).pdf",
        ]
        let removed = [
            "\(prefix)99999999-\(UUID().uuidString).pdf",
            "\(prefix)0-\(UUID().uuidString).pdf",
            "\(prefix)\(UUID().uuidString).pdf",
            "\(prefix).pdf",
            "\(prefix)notaprocess-\(UUID().uuidString).pdf",
        ]
        for filename in kept + removed { try Data("%PDF".utf8).write(to: directory.appendingPathComponent(filename)) }

        PDFBaselineSnapshot.removeStaleBaselines(in: directory)

        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), Set(kept))
    }

    func testRemovingStaleCopiesOfAMissingFolderDoesNothing() {
        PDFBaselineSnapshot.removeStaleBaselines(in: directory.appendingPathComponent("Missing"))
    }

    func testAnUnreferencedBaselineCopyIsDeletedWithItsLastOwner() throws {
        let location = PDFBaselineSnapshot.makeLocation()
        try Data("%PDF".utf8).write(to: location)
        var snapshot: PDFBaselineSnapshot? = PDFBaselineSnapshot(location: location)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path))
        snapshot = nil
        XCTAssertNil(snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
    }

    // MARK: History page copies

    func testHistoryPageCopiesOfUpToOneMebibyteStayInMemoryAndLargerOnesUseTheSameNaming() throws {
        let limit = 1_048_576
        XCTAssertNil(try PDFHistoryPageContent(data: Data(repeating: 1, count: limit)).temporaryFileLocation, "Exactly 1 MiB stays in memory.")
        let largerContent = try PDFHistoryPageContent(data: Data(repeating: 2, count: limit + 1))
        let location = try XCTUnwrap(largerContent.temporaryFileLocation)
        assertNamedLikeABaselineCopy(location)
        XCTAssertEqual(try largerContent.read().count, limit + 1)
    }
}
