import XCTest
import CryptoKit
import GraphiteCore
@testable import GraphiteIndex

final class IndexTests: XCTestCase {
    func testLinksResolveDottedNamesUnicodeFormsAndPartialPaths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let source = try VaultPath("Notes/Source.md")
        let dotted = try VaultPath("Courses/CS-250 Homework 2.1.md")
        // "Café" with the accent stored as a separate combining character, as macOS often writes names.
        let decomposed = try VaultPath("Places/Cafe\u{301} de Chavannes.md")
        let cover = try VaultPath("Library/covers/Book cover 6.png")
        try await index.update([
            IndexedFile(path: source, size: 10, modified: .now, markdown: "[[CS-250 Homework 2.1]] [[Café de Chavannes]] ![[covers/Book cover 6.png]]"),
            IndexedFile(path: dotted, size: 10, modified: .now, markdown: "Homework"),
            IndexedFile(path: decomposed, size: 10, modified: .now, markdown: "Café"),
            IndexedFile(path: cover, size: 10, modified: .now, markdown: nil),
        ], generation: "test")
        let dottedResolution = try await index.resolve("CS-250 Homework 2.1", from: source)
        XCTAssertEqual(dottedResolution, [dotted])
        let composedResolution = try await index.resolve("Café de Chavannes", from: source)
        XCTAssertEqual(composedResolution, [decomposed])
        let partialResolution = try await index.resolve("covers/Book cover 6.png", from: source)
        XCTAssertEqual(partialResolution, [cover])
        let backlinks = try await index.backlinks(to: decomposed)
        XCTAssertEqual(backlinks, [source])
        let dottedBacklinks = try await index.backlinks(to: dotted)
        XCTAssertEqual(dottedBacklinks, [source])
    }

    func testSearchPutsFileNameMatchesFirstWithoutDuplicates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.update([
            IndexedFile(path: try VaultPath("Lectures/Signals.md"), size: 40, modified: .now, markdown: "Math appears in the body of this lecture."),
            IndexedFile(path: try VaultPath("Lectures/More math practice.md"), size: 40, modified: .now, markdown: "Exercises."),
            IndexedFile(path: try VaultPath("Edge cases/06 Math.md"), size: 40, modified: .now, markdown: "Display math tests."),
            IndexedFile(path: try VaultPath("Notes/100%_done.md"), size: 40, modified: .now, markdown: "Nothing else."),
        ], generation: "test")
        let results = try await index.search("math").results
        XCTAssertEqual(results.map(\.path.rawValue), ["Edge cases/06 Math.md", "Lectures/More math practice.md", "Lectures/Signals.md"])
        let twoWords = try await index.search("06 math").results
        XCTAssertEqual(twoWords.first?.path.rawValue, "Edge cases/06 Math.md")
        let likeCharacters = try await index.search("100%_").results
        XCTAssertEqual(likeCharacters.map(\.path.rawValue), ["Notes/100%_done.md"], "% and _ are matched literally in names.")
    }

    func testSearchAliasesAmbiguityAndBacklinks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let source = try VaultPath("Course/Lecture.md")
        let target = try VaultPath("Course/Quantization.md")
        try await index.update([
            IndexedFile(path: source, size: 80, modified: .now, markdown: "# Lecture\n\n[[Quantization]] #signals"),
            IndexedFile(path: target, size: 80, modified: .now, markdown: "---\naliases: [ADC]\n---\n# Quantization\n\nSampling noise theory."),
            IndexedFile(path: try VaultPath("Other/Quantization.md"), size: 20, modified: .now, markdown: "# Other")
        ], generation: "test")
        let search = try await index.search("sampling").results
        XCTAssertEqual(search.map(\.path), [target])
        let tag = try await index.search("#signals").results
        XCTAssertEqual(tag.map(\.path), [source])
        let localResolution = try await index.resolve("Quantization", from: source)
        XCTAssertEqual(localResolution, [target])
        let ambiguousResolution = try await index.resolve("Quantization", from: VaultPath("Elsewhere/Note.md"))
        XCTAssertEqual(ambiguousResolution.count, 2)
        let aliasResolution = try await index.resolve("ADC", from: source)
        XCTAssertEqual(aliasResolution, [target])
        let backlinks = try await index.backlinks(to: target)
        XCTAssertEqual(backlinks, [source])
    }

    func testEverySearchSortOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        // Folders sort the other way from the names, and names differ in case, so path
        // order and case-sensitive order both disagree with the expected name order.
        try await index.update([
            IndexedFile(path: try VaultPath("Z/Alpha.md"), size: 1, modified: Date(timeIntervalSince1970: 3_000), created: Date(timeIntervalSince1970: 1_000), markdown: "common"),
            IndexedFile(path: try VaultPath("A/beta.md"), size: 1, modified: Date(timeIntervalSince1970: 1_000), created: Date(timeIntervalSince1970: 3_000), markdown: "common"),
            IndexedFile(path: try VaultPath("M/Gamma.md"), size: 1, modified: Date(timeIntervalSince1970: 2_000), created: nil, markdown: "common"),
        ], generation: "test")
        let expectedNames: [SearchSortOrder: [String]] = [
            .fileNameAscending: ["Alpha.md", "beta.md", "Gamma.md"],
            .fileNameDescending: ["Gamma.md", "beta.md", "Alpha.md"],
            .modifiedNewestFirst: ["Alpha.md", "Gamma.md", "beta.md"],
            .modifiedOldestFirst: ["beta.md", "Gamma.md", "Alpha.md"],
            // A file without a creation time sorts by its modification time.
            .createdNewestFirst: ["beta.md", "Gamma.md", "Alpha.md"],
            .createdOldestFirst: ["Alpha.md", "Gamma.md", "beta.md"],
        ]
        for sortOrder in SearchSortOrder.allCases {
            let results = try await index.search("common", sortOrder: sortOrder).results
            XCTAssertEqual(results.map(\.path.name), expectedNames[sortOrder], "\(sortOrder.rawValue)")
        }
    }
}

final class IncrementalIndexTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Course"), withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        try Data(text.utf8).write(to: vault.appendingPathComponent(relativePath))
    }

    func testOneFileIsOneRowWhateverFormItsNameArrivesIn() async throws {
        try write("---\nfinished: true\n---\nCamus", to: "L'\u{C9}tranger.md")
        try await index.refresh(paths: [try VaultPath("L'\u{C9}tranger.md")], root: vault)
        // File URLs spell the same name decomposed.
        try await index.refresh(paths: [try VaultPath("L'E\u{301}tranger.md")], root: vault)
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 1)
        let finishedPaths = try await index.paths(withPropertyKey: "finished")
        XCTAssertEqual(finishedPaths.count, 1)
    }

    func testRefreshLeavesHiddenFilesOut() async throws {
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try write(#"{"items": []}"#, to: ".obsidian/bookmarks.json")
        try await index.refresh(paths: [try VaultPath(".obsidian/bookmarks.json")], root: vault)
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 0, "Obsidian's settings are not notes, even when a change to one is reported.")
    }

    func testIndexesAreNamedAfterTheVaultAndOldOnesMove() async throws {
        let caches = vault.appendingPathExtension("caches")
        defer { try? FileManager.default.removeItem(at: caches) }
        let directory = caches.appendingPathComponent("Graphite/Indexes")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyRoot = vault.appendingPathComponent("Old place")
        let legacyName = SHA256Hex.of(legacyRoot.standardizedFileURL.path) + ".sqlite"
        try Data("database".utf8).write(to: directory.appendingPathComponent(legacyName))
        try Data("journal".utf8).write(to: directory.appendingPathComponent(legacyName + "-wal"))
        // Another vault's index, unused for 40 days, and one used yesterday.
        let abandoned = directory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let recent = directory.appendingPathComponent(UUID().uuidString + ".sqlite")
        try Data().write(to: abandoned)
        try Data().write(to: recent)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-40 * 86_400)], ofItemAtPath: abandoned.path)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-86_400)], ofItemAtPath: recent.path)

        let vaultIdentifier = UUID()
        let location = try VaultIndex.cacheURL(forVault: vaultIdentifier, legacyRoot: legacyRoot, in: caches)
        XCTAssertEqual(location.lastPathComponent, vaultIdentifier.uuidString + ".sqlite")
        XCTAssertEqual(try String(contentsOf: location, encoding: .utf8), "database", "The old index moved, so nothing is read again.")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: location.path + "-wal"), encoding: .utf8), "journal")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(legacyName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))

        VaultIndex.removeIndex(forVault: vaultIdentifier, in: caches)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path + "-wal"))
    }

    func testRefreshAddsUpdatesAndRemovesSingleFiles() async throws {
        try write("# Sampling\n\nzebraword", to: "Course/Note.md")
        let path = try VaultPath("Course/Note.md")
        try await index.refresh(paths: [path], root: vault)
        let firstSearch = try await index.search("zebraword").results
        XCTAssertEqual(firstSearch.map(\.path), [path])
        try write("# Sampling\n\nquokka", to: "Course/Note.md")
        try await index.refresh(paths: [path], root: vault)
        let staleSearch = try await index.search("zebraword").results
        let freshSearch = try await index.search("quokka").results
        XCTAssertTrue(staleSearch.isEmpty)
        XCTAssertEqual(freshSearch.map(\.path), [path])
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Course/Note.md"))
        try await index.refresh(paths: [path], root: vault)
        let removedSearch = try await index.search("quokka").results
        let removedCount = try await index.fileCount(named: "Note.md")
        XCTAssertTrue(removedSearch.isEmpty)
        XCTAssertEqual(removedCount, 0)
    }

    /// Regression: one note that is not UTF-8 used to stop deleted files from being pruned.
    func testUnreadableNoteDoesNotBlockPruning() async throws {
        try write("# Deleted later\n\nzebraword", to: "Deleted.md")
        try Data([0x23, 0x20, 0xE9, 0x74, 0xE9]).write(to: vault.appendingPathComponent("Latin1.md"))
        let firstReport = try await index.reconcile(root: vault)
        XCTAssertEqual(firstReport.failedPaths.count, 1)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Deleted.md"))
        _ = try await index.reconcile(root: vault)
        let staleResults = try await index.search("zebraword").results
        XCTAssertTrue(staleResults.isEmpty)
        let latinCount = try await index.fileCount(named: "Latin1.md")
        XCTAssertEqual(latinCount, 1, "The unreadable note stays in the inventory.")
    }

    /// A canceled scan has not seen every file, so it must not prune what it did not reach.
    func testCanceledScanKeepsEveryRecord() async throws {
        try write("# Deleted later\n\nzebraword", to: "Course/Deleted.md")
        _ = try await index.reconcile(root: vault)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Course/Deleted.md"))
        let scanningIndex = try XCTUnwrap(index), vaultFolder = try XCTUnwrap(vault)
        let scan = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await scanningIndex.reconcile(root: vaultFolder)
        }
        scan.cancel()
        do {
            _ = try await scan.value
            XCTFail("A canceled scan must not finish.")
        } catch is CancellationError {}
        let keptResults = try await index.search("zebraword").results
        XCTAssertEqual(keptResults.map(\.path.rawValue), ["Course/Deleted.md"])
        _ = try await index.reconcile(root: vault)
        let prunedResults = try await index.search("zebraword").results
        XCTAssertTrue(prunedResults.isEmpty, "The next complete scan prunes the deleted note.")
    }

    /// A folder the scan cannot list, as on a file provider that is offline, must keep the
    /// records of its notes, and the incomplete scan must not prune anything else either.
    func testScanThatCannotListAFolderKeepsRecords() async throws {
        let lockedFolder = vault.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: lockedFolder, withIntermediateDirectories: true)
        try write("# Inside\n\nquokka", to: "Locked/Inside.md")
        try write("# Deleted later\n\nzebraword", to: "Course/Deleted.md")
        _ = try await index.reconcile(root: vault)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Course/Deleted.md"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: lockedFolder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedFolder.path) }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: lockedFolder.path), "This user can read folders without permission.")
        _ = try await index.reconcile(root: vault)
        let insideResults = try await index.search("quokka").results
        XCTAssertEqual(insideResults.map(\.path.rawValue), ["Locked/Inside.md"])
        let deletedResults = try await index.search("zebraword").results
        XCTAssertEqual(deletedResults.map(\.path.rawValue), ["Course/Deleted.md"], "Only a complete scan may prune.")
    }

    /// Regression: relative Markdown links and differently capitalized Wikilinks count as backlinks.
    func testBacklinksIncludeMarkdownLinksAndCaseDifferences() async throws {
        let target = try VaultPath("Course/Quantization Notes.md")
        try await index.update([
            IndexedFile(path: target, size: 10, modified: .now, markdown: "# Quantization"),
            IndexedFile(path: try VaultPath("Course/Relative.md"), size: 10, modified: .now, markdown: "[q](Quantization%20Notes.md)"),
            IndexedFile(path: try VaultPath("Other/Parent.md"), size: 10, modified: .now, markdown: "[q](../Course/Quantization%20Notes.md)"),
            IndexedFile(path: try VaultPath("Course/WikiCase.md"), size: 10, modified: .now, markdown: "[[quantization notes]]"),
            IndexedFile(path: try VaultPath("Course/Wiki.md"), size: 10, modified: .now, markdown: "[[Quantization Notes]]"),
            IndexedFile(path: try VaultPath("Course/Unrelated.md"), size: 10, modified: .now, markdown: "[x](Other.md)"),
        ], generation: "test")
        let backlinks = try await index.backlinks(to: target)
        XCTAssertEqual(backlinks.map(\.rawValue), ["Course/Relative.md", "Course/Wiki.md", "Course/WikiCase.md", "Other/Parent.md"])
    }
}

private enum SHA256Hex {
    static func of(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { byte in String(format: "%02x", byte) }.joined() }
}
