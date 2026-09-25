import XCTest
import GRDB
import GraphiteCore
@testable import GraphiteIndex

/// Link resolution and backlinks: partial paths, aliases and case differences in any script.
final class IndexVaultIndexLinkTests: XCTestCase {
    private var directory: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func note(_ path: String, _ markdown: String?) throws -> IndexedFile {
        IndexedFile(path: try VaultPath(path), size: 10, modified: .now, markdown: markdown)
    }

    /// Regression: backlinks read only links written as the full path, name or stem, so
    /// partial paths and aliases were missing although they resolve to the note.
    func testBacklinksIncludePartialPathsRootedPathsAndAliases() async throws {
        let target = try VaultPath("Folder/Sub/Target.md")
        try await index.update([
            try note(target.rawValue, "---\naliases: [My Alias]\n---\n# Target"),
            try note("Linkers/plain.md", "[[Target]]"),
            try note("Linkers/partial.md", "[[Sub/Target]]"),
            try note("Linkers/alias.md", "[[My Alias]]"),
            try note("Linkers/rooted.md", "[[/Folder/Sub/Target]]"),
            try note("Linkers/lowercase.md", "[[folder/sub/target]]"),
            try note("Linkers/property.md", "---\nrelated: \"[[Sub/Target]]\"\n---\nBody"),
            try note("Linkers/unrelated.md", "[[Sub/Other]] [[Target elsewhere]]"),
        ], generation: "test")
        let expectedLinkers = ["Linkers/alias.md", "Linkers/lowercase.md", "Linkers/partial.md", "Linkers/plain.md", "Linkers/rooted.md"]
        let backlinks = try await index.backlinks(to: target)
        XCTAssertEqual(backlinks.map(\.rawValue), expectedLinkers)
        XCTAssertEqual(index.baseRecordProvider.backlinks(to: target).map(\.rawValue), (expectedLinkers + ["Linkers/property.md"]).sorted(),
                       "`file.backlinks` also counts frontmatter links.")
        let rootedResolution = try await index.resolve("/Folder/Sub/Target", from: VaultPath("Linkers/rooted.md"))
        XCTAssertEqual(rootedResolution, [target])
    }

    /// Regression: a partial path resolved to another note with the same name is not a backlink.
    func testAmbiguousOrOtherPartialPathsAreNotBacklinks() async throws {
        let target = try VaultPath("Library/covers/Book.md")
        try await index.update([
            try note(target.rawValue, "# Book"),
            try note("Other/Book.md", "# Other book"),
            try note("Only.md", "[[covers/Book]]"),
            try note("Bare.md", "[[Book]]"),
            try note("OtherLinker.md", "[[Other/Book]]"),
        ], generation: "test")
        let backlinks = try await index.backlinks(to: target)
        XCTAssertEqual(backlinks.map(\.rawValue), ["Only.md"], "The bare name is ambiguous, and Other/Book names the other note.")
    }

    /// Regression: SQLite's NOCASE folds ASCII letters only, so `[[éclair]]` did not find `Éclair.md`.
    func testNonASCIILettersMatchWhateverTheirCase() async throws {
        let eclair = try VaultPath("Pâtisserie/Éclair.md")
        // "Übung" with the accent stored as a combining character, as macOS often writes names.
        let exercise = try VaultPath("U\u{308}bung.md")
        try await index.update([
            try note(eclair.rawValue, "---\naliases: [Ölkuchen]\n---\n# Éclair"),
            try note(exercise.rawValue, "# Übung"),
            try note("Source.md", "[[éclair]] [[übung]]"),
            try note("AliasSource.md", "[[ölkuchen]]"),
        ], generation: "test")
        let lowercaseResolution = try await index.resolve("éclair", from: VaultPath("Source.md"))
        XCTAssertEqual(lowercaseResolution, [eclair])
        let uppercaseResolution = try await index.resolve("ÉCLAIR", from: VaultPath("Source.md"))
        XCTAssertEqual(uppercaseResolution, [eclair])
        let partialResolution = try await index.resolve("pâtisserie/éclair", from: VaultPath("Source.md"))
        XCTAssertEqual(partialResolution, [eclair])
        let decomposedResolution = try await index.resolve("übung", from: VaultPath("Source.md"))
        XCTAssertEqual(decomposedResolution, [exercise])
        let aliasResolution = try await index.resolve("ÖLKUCHEN", from: VaultPath("Source.md"))
        XCTAssertEqual(aliasResolution, [eclair])
        let eclairBacklinks = try await index.backlinks(to: eclair)
        XCTAssertEqual(eclairBacklinks.map(\.rawValue), ["AliasSource.md", "Source.md"])
        let exerciseBacklinks = try await index.backlinks(to: exercise)
        XCTAssertEqual(exerciseBacklinks.map(\.rawValue), ["Source.md"])
        let eclairCount = try await index.fileCount(named: "éclair.md")
        XCTAssertEqual(eclairCount, 1)
        let exerciseCount = try await index.fileCount(named: "ÜBUNG.md")
        XCTAssertEqual(exerciseCount, 1)
    }

    /// Regression: a partial path starting at a top-level folder matched only with the exact case.
    func testRootLevelPartialPathsIgnoreCase() async throws {
        let note = try VaultPath("Folder/Note.md")
        try await index.update([
            try self.note(note.rawValue, "# Note"),
            try self.note("Deep/Topic/Page.md", "# Page"),
            try self.note("Other/Source.md", "[[folder/note]] [[topic/page]]"),
        ], generation: "test")
        let rootResolution = try await index.resolve("folder/note", from: VaultPath("Other/Source.md"))
        XCTAssertEqual(rootResolution, [note])
        let deepResolution = try await index.resolve("topic/page", from: VaultPath("Other/Source.md"))
        XCTAssertEqual(deepResolution.map(\.rawValue), ["Deep/Topic/Page.md"])
        let backlinks = try await index.backlinks(to: note)
        XCTAssertEqual(backlinks.map(\.rawValue), ["Other/Source.md"])
    }

    /// Names that differ only by case (possible on case-sensitive volumes): the exact
    /// spelling wins, and otherwise both are returned as ambiguous rather than one chosen.
    func testNamesDifferingOnlyByCasePreferTheExactSpelling() async throws {
        try await index.update([
            try note("Case/Note.md", "upper"),
            try note("Case/note.md", "lower"),
        ], generation: "test")
        let exactResolution = try await index.resolve("Case/note", from: VaultPath("Source.md"))
        XCTAssertEqual(exactResolution.map(\.rawValue), ["Case/note.md"])
        let ambiguousResolution = try await index.resolve("CASE/NOTE", from: VaultPath("Source.md"))
        XCTAssertEqual(ambiguousResolution.map(\.rawValue), ["Case/Note.md", "Case/note.md"])
    }

    /// Regression: `path = ? OR path_key = ?` scanned the whole files table for every
    /// direct link candidate, and the prune read every row of the search table.
    func testLookupsUseIndexesRatherThanTableScans() async throws {
        func queryPlan(_ sql: String) async throws -> String {
            try await index.databaseQueue.read { database in
                try Row.fetchAll(database, sql: "EXPLAIN QUERY PLAN " + sql, arguments: ["a"]).map { row in row["detail"] as String }.joined(separator: "\n")
            }
        }
        let directLookupPlan = try await queryPlan("SELECT path FROM files WHERE folded_path = ? ORDER BY path LIMIT 50")
        XCTAssertTrue(directLookupPlan.contains("files_folded_path"), directLookupPlan)
        let nameLookupPlan = try await queryPlan("SELECT path FROM files WHERE folded_name = ?")
        XCTAssertTrue(nameLookupPlan.contains("files_folded_name"), nameLookupPlan)
        let backlinkPlan = try await queryPlan("SELECT DISTINCT source, target, isWiki FROM links WHERE folded_target IN (?)")
        XCTAssertTrue(backlinkPlan.contains("links_folded_target"), backlinkPlan)
        let prunePlan = try await queryPlan(VaultIndex.staleSearchRowDeletion)
        // FTS5 reports a rowid lookup as an index constraint ("INDEX 0:=") and a full scan as "INDEX 0:".
        XCTAssertFalse(prunePlan.split(separator: "\n").contains { line in line.hasSuffix("VIRTUAL TABLE INDEX 0:") }, prunePlan)
    }

    /// The folded keys are added to an index written by an earlier version without a rescan.
    func testMigrationFoldsKeysOfExistingRows() async throws {
        try await index.update([
            try note("Pâtisserie/Éclair.md", "---\naliases: [Ölkuchen]\nrelated: \"[[Sub/Éclair]]\"\n---\n[[Übung]]"),
        ], generation: "test")
        let databaseURL = directory.appendingPathComponent("index.sqlite")
        index = nil
        // Returns the database to the schema before the migration, keeping its rows.
        let databaseQueue = try DatabaseQueue(path: databaseURL.path)
        try await databaseQueue.write { database in
            try database.execute(sql: """
                DROP INDEX files_folded_path; DROP INDEX files_folded_name; DROP INDEX aliases_folded_alias;
                DROP INDEX links_folded_target; DROP INDEX property_links_folded_target;
                ALTER TABLE files DROP COLUMN folded_path; ALTER TABLE files DROP COLUMN folded_name;
                ALTER TABLE aliases DROP COLUMN folded_alias; ALTER TABLE links DROP COLUMN folded_target;
                ALTER TABLE property_links DROP COLUMN folded_target;
                CREATE INDEX files_path_key ON files(path_key COLLATE NOCASE);
                CREATE INDEX files_name_key ON files(name_key COLLATE NOCASE);
                DELETE FROM grdb_migrations WHERE identifier = 'case-folded-link-keys-8';
                """)
        }
        try databaseQueue.close()
        let migratedIndex = try VaultIndex(databaseURL: databaseURL)
        let folded = try await migratedIndex.databaseQueue.read { database in
            [try String.fetchOne(database, sql: "SELECT folded_path FROM files"), try String.fetchOne(database, sql: "SELECT folded_name FROM files"),
             try String.fetchOne(database, sql: "SELECT folded_alias FROM aliases"), try String.fetchOne(database, sql: "SELECT folded_target FROM links"),
             try String.fetchOne(database, sql: "SELECT folded_target FROM property_links")]
        }
        XCTAssertEqual(folded, ["pâtisserie/éclair.md", "éclair.md", "ölkuchen", "übung", "sub/éclair"])
        let resolution = try await migratedIndex.resolve("ÉCLAIR", from: VaultPath("Source.md"))
        XCTAssertEqual(resolution.map(\.rawValue), ["Pâtisserie/Éclair.md"])
    }
}

/// Renames keep links that name the file by a partial path.
final class IndexVaultIndexRenameTests: XCTestCase {
    private var vault: URL!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Library/covers"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Other"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    /// Regression: a note linking only by `[[covers/Book]]` was left out of the rename plan,
    /// so its link broke.
    func testRenamingRewritesPartialPathLinks() async throws {
        try Data("# Book".utf8).write(to: vault.appendingPathComponent("Library/covers/Book.md"))
        try Data("# Other".utf8).write(to: vault.appendingPathComponent("Other/Book.md"))
        try Data("see [[covers/Book]]".utf8).write(to: vault.appendingPathComponent("Only.md"))
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let operations = VaultFileOperations(store: VaultStore(root: vault), index: index)
        let source = try VaultPath("Library/covers/Book.md"), destination = try VaultPath("Library/covers/Novel.md")
        let plan = try await operations.linkUpdates(forMoving: source, to: destination)
        XCTAssertEqual(plan.updates.map(\.path.rawValue), ["Only.md"])
        _ = try await operations.move(source, to: destination, applying: plan)
        let rewritten = try String(contentsOf: vault.appendingPathComponent("Only.md"), encoding: .utf8)
        XCTAssertNotEqual(rewritten, "see [[covers/Book]]")
        _ = try await index.reconcile(root: vault)
        let links = try MarkdownSemantics.parse(rewritten).links
        XCTAssertEqual(links.count, 1)
        let resolution = try await index.resolve(try XCTUnwrap(links.first).target, from: VaultPath("Only.md"))
        XCTAssertEqual(resolution, [destination], "The rewritten link still names the renamed note.")
    }
}

/// Scans and refreshes: what is pruned, what is re-read, and what one failure costs.
final class IndexVaultIndexScanTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: vault.appendingPathComponent("B.md").path)
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func searchPaths(_ text: String) async throws -> [String] {
        try await index.search(text).results.map(\.path.rawValue)
    }

    /// Regression: a refresh during a scan gave the row a new generation, and the scan's
    /// prune then deleted the note although it still existed.
    func testNotesSavedDuringAScanAreNotPruned() async throws {
        let noteCount = 600
        for noteNumber in 0..<noteCount { try write("# Note \(noteNumber)\n\n[[n0000]]", to: String(format: "n%04d.md", noteNumber)) }
        _ = try await index.reconcile(root: vault)
        let savedPaths = try stride(from: 0, to: noteCount, by: 50).map { noteNumber in try VaultPath(String(format: "n%04d.md", noteNumber)) }
        let scanCompletion = ScanCompletion()
        let index = try XCTUnwrap(index), vault = try XCTUnwrap(vault)
        let scan = Task {
            let report = try await index.reconcile(root: vault)
            await scanCompletion.markFinished()
            return report
        }
        var saveCount = 0
        // Saves keep landing while the scan runs, as autosave does while a large vault is indexed.
        while saveCount < 2_000 {
            let savedPath = savedPaths[saveCount % savedPaths.count]
            try write("# Saved\n\nsavedword\(saveCount)", to: savedPath.rawValue)
            try await index.refresh(paths: [savedPath], root: vault)
            saveCount += 1
            if saveCount >= savedPaths.count, await scanCompletion.isFinished { break }
        }
        _ = try await scan.value
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, noteCount)
        for savedPath in savedPaths {
            let resolution = try await index.resolve(savedPath.stem, from: .root)
            XCTAssertEqual(resolution, [savedPath])
        }
        let lastSaved = savedPaths[(saveCount - 1) % savedPaths.count]
        let lastSearch = try await searchPaths("savedword\(saveCount - 1)")
        XCTAssertEqual(lastSearch, [lastSaved.rawValue], "The scan did not replace the saved text with an older reading.")
    }

    /// A scan that read a note before it was saved must not write that older reading over
    /// the saved text. Every note changes on disk, so the scan reads each one into a batch,
    /// while saves walk the vault in the same order as the scan.
    func testScanDoesNotOverwriteNotesSavedAfterItReadThem() async throws {
        let noteCount = 400, savedCount = 200
        for noteNumber in 0..<noteCount { try write("# Note \(noteNumber)", to: String(format: "n%04d.md", noteNumber)) }
        _ = try await index.reconcile(root: vault)
        for noteNumber in 0..<noteCount { try write("# Note \(noteNumber)\n\nchanged", to: String(format: "n%04d.md", noteNumber)) }
        let index = try XCTUnwrap(index), vault = try XCTUnwrap(vault)
        let scan = Task { try await index.reconcile(root: vault) }
        for noteNumber in 0..<savedCount {
            let savedPath = try VaultPath(String(format: "n%04d.md", noteNumber))
            try write("# Saved\n\nsavedword\(noteNumber)", to: savedPath.rawValue)
            try await index.refresh(paths: [savedPath], root: vault)
        }
        _ = try await scan.value
        var notesWithOlderText: [Int] = []
        for noteNumber in 0..<savedCount where try await searchPaths("savedword\(noteNumber)").isEmpty { notesWithOlderText.append(noteNumber) }
        XCTAssertEqual(notesWithOlderText, [])
    }

    /// Regression: a file whose name VaultPath refused (a backslash, legal on APFS) marked
    /// every scan incomplete, so deleted notes were never pruned. VaultPath now accepts a
    /// backslash, so such a file is indexed like any other.
    func testBackslashInANameDoesNotBlockPruning() async throws {
        try write("# Deleted later\n\nzebraword", to: "Deleted.md")
        try write("attachment", to: "report\\final.png")
        let firstReport = try await index.reconcile(root: vault)
        XCTAssertEqual(firstReport.failedPaths, [])
        let backslashNameCount = try await index.fileCount(named: "report\\final.png")
        XCTAssertEqual(backslashNameCount, 1)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Deleted.md"))
        _ = try await index.reconcile(root: vault)
        let staleSearch = try await searchPaths("zebraword")
        XCTAssertEqual(staleSearch, [])
        let staleResolution = try await index.resolve("Deleted", from: .root)
        XCTAssertEqual(staleResolution, [])
    }

    /// Regression: notes that cannot be indexed (too large, not UTF-8) were written again on every scan.
    func testUnindexableNotesAreNotRewrittenOnEveryScan() async throws {
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try Data(count: VaultIndex.maximumIndexedNoteBytes + 1).write(to: vault.appendingPathComponent("Large.md"))
        try Data([0x23, 0x20, 0xE9, 0x74, 0xE9]).write(to: vault.appendingPathComponent("Latin1.md"))
        try write("# Plain", to: "Plain.md")
        let firstReport = try await index.reconcile(root: vault)
        XCTAssertEqual(firstReport.updatedFiles, 3)
        XCTAssertEqual(firstReport.pendingContentFiles, 2)
        let secondReport = try await index.reconcile(root: vault)
        XCTAssertEqual(secondReport.updatedFiles, 0)
        XCTAssertEqual(secondReport.pendingContentFiles, 2, "They are still not searchable.")
        XCTAssertEqual(secondReport.failedPaths, [])
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 3)
        // Once the large note fits, the next scan reads it.
        try write("# Large\n\nshrunkenword", to: "Large.md")
        let thirdReport = try await index.reconcile(root: vault)
        XCTAssertEqual(thirdReport.updatedFiles, 1)
        let search = try await searchPaths("shrunkenword")
        XCTAssertEqual(search, ["Large.md"])
    }

    /// Batches are also limited by the bytes of note text they hold; notes past that
    /// limit are still all indexed.
    func testLargeNotesAreAllIndexedAcrossByteLimitedBatches() async throws {
        // Each 6 MiB note exceeds the 4 MiB batch limit, so every note is written in its own batch.
        let filler = String(repeating: "filler text ", count: 6 * 1_048_576 / 12)
        for noteNumber in 0..<3 { try write("# Large \(noteNumber)\n\nlargeword\(noteNumber)\n\n" + filler, to: "Large \(noteNumber).md") }
        let report = try await index.reconcile(root: vault)
        XCTAssertEqual(report.updatedFiles, 3)
        XCTAssertEqual(report.failedPaths, [])
        for noteNumber in 0..<3 {
            let search = try await searchPaths("largeword\(noteNumber)")
            XCTAssertEqual(search, ["Large \(noteNumber).md"])
        }
    }

    /// Regression: a failed batch write was never cleared, so every later file re-parsed a
    /// growing batch and the scan threw, leaving the rest of the vault unindexed.
    func testFailedWriteCostsOnlyTheFailingFile() async throws {
        for noteNumber in 0..<200 { try write("# Note \(noteNumber)", to: String(format: "n%04d.md", noteNumber)) }
        try await index.databaseQueue.write { database in
            try database.execute(sql: """
                CREATE TRIGGER simulated_write_failure BEFORE INSERT ON files WHEN NEW.path = 'n0003.md'
                BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END
                """)
        }
        let report = try await index.reconcile(root: vault)
        XCTAssertEqual(report.failedPaths.count, 1)
        XCTAssertTrue(report.failedPaths.first?.hasPrefix("n0003.md: ") == true, "\(report.failedPaths)")
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 199)
        try await index.databaseQueue.write { database in try database.execute(sql: "DROP TRIGGER simulated_write_failure") }
        try FileManager.default.removeItem(at: vault.appendingPathComponent("n0100.md"))
        _ = try await index.reconcile(root: vault)
        let resolution = try await index.resolve("n0003", from: .root)
        XCTAssertEqual(resolution.map(\.rawValue), ["n0003.md"])
        let prunedResolution = try await index.resolve("n0100", from: .root)
        XCTAssertEqual(prunedResolution, [])
    }

    /// Regression: refresh indexed hidden paths, which a scan skips, so a trashed note
    /// answered links and searches.
    func testRefreshSkipsHiddenPathsAndSymbolicLinks() async throws {
        try write("# Old\n\ntrashedword", to: ".trash/Old Note.md")
        try write("{\"theme\": \"dark\"}", to: ".obsidian/workspace.json")
        try write("# Real\n\nlinkedword", to: "Real.md")
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("Alias.md"), withDestinationURL: vault.appendingPathComponent("Real.md"))
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("Linked folder"), withDestinationURL: vault.appendingPathComponent("Folder"))
        try write("# Inside", to: "Folder/Inside.md")
        let paths = try [".trash/Old Note.md", ".obsidian/workspace.json", "Alias.md", "Linked folder/Inside.md"].map(VaultPath.init)
        try await index.refresh(paths: paths, root: vault)
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 0)
        let trashedResolution = try await index.resolve("Old Note", from: .root)
        XCTAssertEqual(trashedResolution, [])
        let trashedSearch = try await searchPaths("trashedword")
        XCTAssertEqual(trashedSearch, [])
    }

    /// Regression: refreshing a folder deleted outside Graphite removed only the folder's
    /// own (absent) row; every file inside stayed searchable.
    func testRefreshingADeletedFolderRemovesItsFiles() async throws {
        try write("# Lecture\n\nlectureword", to: "Week 1/Lecture.md")
        try write("# Deep\n\ndeepword", to: "Week 1/Sub/Deep.md")
        try write("# Neighbour\n\nneighbourword", to: "Week 10/Neighbour.md")
        try write("# Kept\n\nkeptword", to: "Week 2/Kept.md")
        _ = try await index.reconcile(root: vault)
        // An existing folder reported as changed keeps its files.
        try await index.refresh(paths: [VaultPath("Week 2")], root: vault)
        let keptSearch = try await searchPaths("keptword")
        XCTAssertEqual(keptSearch, ["Week 2/Kept.md"])
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Week 1"))
        try await index.refresh(paths: [VaultPath("Week 1")], root: vault)
        let lectureSearch = try await searchPaths("lectureword")
        let deepSearch = try await searchPaths("deepword")
        XCTAssertEqual(lectureSearch, [])
        XCTAssertEqual(deepSearch, [])
        let neighbourSearch = try await searchPaths("neighbourword")
        XCTAssertEqual(neighbourSearch, ["Week 10/Neighbour.md"], "A folder whose name starts the same way is not inside it.")
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 2)
    }

    /// Regression: one unreadable file made refresh throw before any path was updated.
    func testUnreadableFileDoesNotStopTheRestOfARefresh() async throws {
        try write("# A\n\nalphaold", to: "A.md")
        try write("# B\n\nbetaold", to: "B.md")
        _ = try await index.reconcile(root: vault)
        try write("# A\n\nalphanew", to: "A.md")
        try write("# B\n\nbetanew", to: "B.md")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: vault.appendingPathComponent("B.md").path)
        try await index.refresh(paths: [VaultPath("A.md"), VaultPath("B.md")], root: vault)
        let alphaSearch = try await searchPaths("alphanew")
        XCTAssertEqual(alphaSearch, ["A.md"])
        let betaCount = try await index.fileCount(named: "B.md")
        XCTAssertEqual(betaCount, 1, "The unreadable note stays in the inventory.")
        let staleBetaSearch = try await searchPaths("betaold")
        XCTAssertEqual(staleBetaSearch, [], "Its old text is not kept as if it were current.")
    }
}

private actor ScanCompletion {
    private(set) var isFinished = false
    func markFinished() { isFinished = true }
}
