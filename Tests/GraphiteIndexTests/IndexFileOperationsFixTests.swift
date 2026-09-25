import XCTest
import GRDB
import GraphiteCore
@testable import GraphiteIndex

/// Regression tests for moves and renames that must not corrupt, skip or misreport
/// linking notes, and for the base pre-filter's superset guarantee.
final class IndexFileOperationsFixTests: XCTestCase {
    private var vault: URL!
    private var store: VaultStore!
    private var index: VaultIndex!
    private var operations: VaultFileOperations!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("FixVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        store = VaultStore(root: vault)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        operations = VaultFileOperations(store: store, index: index)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ relativePath: String, _ text: String) throws {
        try write(relativePath, Data(text.utf8))
    }

    private func write(_ relativePath: String, _ bytes: Data) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: location)
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func move(_ source: String, _ destination: String) async throws -> MoveReport {
        let plan = try await operations.linkUpdates(forMoving: VaultPath(source), to: VaultPath(destination))
        return try await operations.move(VaultPath(source), to: VaultPath(destination), applying: plan)
    }

    // MARK: Moves and renames

    func testWindowsLineEndingsAreRewrittenCorrectlyOrReportedButNeverCorrupted() async throws {
        let original = "x [[Old name|a]]\r\n> [x](Notes/Old%20name.md)\r\n"
        try write("Notes/Old name.md", "old")
        try write("Linker.md", original)
        _ = try await index.reconcile(root: vault)
        let report = try await move("Notes/Old name.md", "Notes/New name.md")
        let result = try read("Linker.md")
        if report.updatedNotes.map(\.rawValue).contains("Linker.md") {
            XCTAssertEqual(result, "x [[New name|a]]\r\n> [x](Notes/New%20name.md)\r\n", "Both links are rewritten and the line endings kept.")
        } else {
            XCTAssertEqual(result, original, "A note whose links cannot be located is left exactly as it was.")
            XCTAssertEqual(report.failures[try VaultPath("Linker.md")], .linksNotLocated)
        }
    }

    func testUnreadableLinkingNotesAreReportedWithTheirReason() async throws {
        try write("Notes/Old name.md", "old")
        try write("Other/Latin.md", "[[Old name]]")
        try write("Other/Large.md", "[[Old name]]")
        try write("Other/Small.md", "[[Old name]]")
        _ = try await index.reconcile(root: vault)
        // Changed after indexing: a Latin-1 byte, and a size over the rewrite limit.
        try write("Other/Latin.md", Data("[[Old name]] caf".utf8) + Data([0xE9]))
        try write("Other/Large.md", Data("[[Old name]]\n".utf8) + Data(repeating: UInt8(ascii: "a"), count: VaultFileOperations.maximumRewrittenNoteBytes))
        let report = try await move("Notes/Old name.md", "Notes/New name.md")
        XCTAssertEqual(report.updatedNotes.map(\.rawValue), ["Other/Small.md"])
        XCTAssertEqual(report.failures[try VaultPath("Other/Latin.md")], .notText)
        XCTAssertEqual(report.failures[try VaultPath("Other/Large.md")], .tooLarge)
        XCTAssertEqual(report.notesNotUpdated.map(\.rawValue), ["Other/Large.md", "Other/Latin.md"])
    }

    func testNotesGoneSinceIndexingAreNotReported() async throws {
        try write("Notes/Old name.md", "old")
        try write("Notes/Deleted.md", "[[Old name]]")
        try write("Linker.md", "[[Old name]]")
        _ = try await index.reconcile(root: vault)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Notes/Deleted.md"))
        let report = try await move("Notes", "Lectures")
        XCTAssertTrue(report.failures.isEmpty, "A note that no longer exists has nothing to update: \(report.failures)")
        XCTAssertEqual(try read("Linker.md"), "[[Old name]]")
    }

    func testEscapedDestinationsElsewhereInANoteDoNotBlockItsUpdate() async throws {
        try write("Notes/Old name.md", "old")
        try write("Linker.md", "[a](Some\\_file.md) and [b](Fish&amp;Chips.md) and [[Notes/Old name]]")
        _ = try await index.reconcile(root: vault)
        let report = try await move("Notes/Old name.md", "Notes/New name.md")
        XCTAssertEqual(report.updatedNotes.map(\.rawValue), ["Linker.md"])
        XCTAssertEqual(try read("Linker.md"), "[a](Some\\_file.md) and [b](Fish&amp;Chips.md) and [[Notes/New name]]")
    }

    func testEmptyDestinationsElsewhereInANoteDoNotBlockItsUpdate() async throws {
        try write("Notes/Old name.md", "old")
        try write("Linker.md", "---\nsee: \"[draft](<>)\"\n---\n[draft](<>) and [[Old name]]")
        _ = try await index.reconcile(root: vault)
        let report = try await move("Notes/Old name.md", "Notes/New name.md")
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures)")
        XCTAssertEqual(try read("Linker.md"), "---\nsee: \"[draft](<>)\"\n---\n[draft](<>) and [[New name]]")
    }

    func testByteOrderMarkIsKept() async throws {
        try write("Notes/Old name.md", "old")
        try write("Bom.md", Data([0xEF, 0xBB, 0xBF]) + Data("# Title\n[[Old name]]\n".utf8))
        _ = try await index.reconcile(root: vault)
        _ = try await move("Notes/Old name.md", "Notes/New name.md")
        let bytes = try Data(contentsOf: vault.appendingPathComponent("Bom.md"))
        XCTAssertEqual(bytes, Data([0xEF, 0xBB, 0xBF]) + Data("# Title\n[[New name]]\n".utf8))
    }

    func testLinksSpelledWithOtherCapitalsAreRewrittenOnCaseInsensitiveVolumes() async throws {
        try write("Notes/Old name.md", "old")
        guard FileManager.default.fileExists(atPath: vault.appendingPathComponent("notes/old name.md").path) else {
            throw XCTSkip("The temporary folder is on a case-sensitive volume.")
        }
        try write("Linker.md", "[[old name]] and [x](notes/old%20name.md) and [[notes/old name]]")
        _ = try await index.reconcile(root: vault)
        let report = try await move("Notes/Old name.md", "Notes/New name.md")
        XCTAssertEqual(report.updatedNotes.map(\.rawValue), ["Linker.md"])
        XCTAssertEqual(try read("Linker.md"), "[[New name]] and [x](Notes/New%20name.md) and [[Notes/New name]]")
    }

    func testCaseOnlyRenameOfANonASCIINameKeepsABareLinkBare() async throws {
        try write("A/Über.md", "note")
        try write("B/Link.md", "[[Über]]")
        _ = try await index.reconcile(root: vault)
        _ = try await move("A/Über.md", "A/über.md")
        XCTAssertEqual(try read("B/Link.md"), "[[über]]")
    }

    func testFolderRenamePlanningKeepsBareNamesAndScalesWithTheFolder() async throws {
        let noteCount = 400
        for number in 0..<noteCount { try write("Notes/Note \(number).md", "[[Note \((number + 1) % noteCount)]] [[Other]]") }
        try write("Other.md", "[[Note 0]]")
        _ = try await index.reconcile(root: vault)
        let start = Date()
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Notes"), to: VaultPath("Lectures"))
        let planningSeconds = Date().timeIntervalSince(start)
        XCTAssertEqual(plan.moves.count, noteCount)
        XCTAssertEqual(plan.changedLinkCount, 0, "Bare names that stay unique are not rewritten when their folder moves.")
        XCTAssertLessThan(planningSeconds, 30, "Planning must not grow with the square of the folder's size.")
    }

    func testFolderPlanListsFilesTheIndexHasNotSeen() async throws {
        try write("Notes/One.md", "one")
        try write("Notes/Two.md", "two")
        try write("Notes/Sub/Three.md", "three")
        try write("Notes/.hidden.md", "hidden")
        // No scan yet: the index is empty, as when a vault was just opened.
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Notes"), to: VaultPath("Lectures"))
        XCTAssertEqual(Set(plan.moves.map { previousPath, newPath in previousPath.rawValue + "->" + newPath.rawValue }),
                       ["Notes/One.md->Lectures/One.md", "Notes/Two.md->Lectures/Two.md", "Notes/Sub/Three.md->Lectures/Sub/Three.md"])
    }

    func testFolderMoveWithoutLinkUpdatesReportsEveryMovedFile() async throws {
        try write("Notes/One.md", "one")
        try write("Notes/Two.md", "two")
        try write("Linker.md", "[[Notes/One]]")
        _ = try await index.reconcile(root: vault)
        let report = try await operations.move(VaultPath("Notes"), to: VaultPath("Lectures"), applying: nil)
        XCTAssertEqual(report.moves, [try VaultPath("Notes/One.md"): try VaultPath("Lectures/One.md"), try VaultPath("Notes/Two.md"): try VaultPath("Lectures/Two.md")])
        XCTAssertEqual(try read("Linker.md"), "[[Notes/One]]", "Links are left alone when the person chose not to update them.")
        try await index.refresh(paths: Array(report.moves.keys) + Array(report.moves.values), root: vault)
        let oldFolder = try await index.paths(inside: VaultPath("Notes"))
        let newFolder = try await index.paths(inside: VaultPath("Lectures"))
        XCTAssertTrue(oldFolder.isEmpty)
        XCTAssertEqual(Set(newFolder.map(\.rawValue)), ["Lectures/One.md", "Lectures/Two.md"])
    }

    func testFailedWritesAreNotReportedAsExternalChanges() async throws {
        try write("Notes/Old name.md", "old")
        try write("Locked/Linker.md", "[[Old name]]")
        try write("Changed.md", "[[Old name]]")
        _ = try await index.reconcile(root: vault)
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Notes/Old name.md"), to: VaultPath("Notes/New name.md"))
        try write("Changed.md", "edited elsewhere [[Old name]]")
        let lockedFolder = vault.appendingPathComponent("Locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedFolder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedFolder.path) }
        let report = try await operations.move(VaultPath("Notes/Old name.md"), to: VaultPath("Notes/New name.md"), applying: plan)
        XCTAssertEqual(report.failures[try VaultPath("Changed.md")], .changedSincePlanning)
        guard case .saveFailed = report.failures[try VaultPath("Locked/Linker.md")] else {
            return XCTFail("A note in a read-only folder must be reported as a failed save, not as changed elsewhere: \(String(describing: report.failures))")
        }
        XCTAssertEqual(try read("Locked/Linker.md"), "[[Old name]]")
    }

    // MARK: Base pre-filter

    private func prefilteredPaths(_ requirement: BasePrefilterRequirement) async throws -> Set<String> {
        let batch = try await index.baseRecords(matching: BaseRecordPrefilter(requirements: [requirement]))
        return Set(batch.records.map(\.path.rawValue))
    }

    func testLinkPrefilterKeepsRelativePartialRootedAndAliasLinks() async throws {
        try write("Notes/B/Target.md", "---\naliases: [Goal]\n---\ntarget")
        try write("Other/Relative.md", "[[../Notes/B/Target]]")
        try write("Other/DotRelative.md", "[[./../Notes/B/Target|x]]")
        try write("Partial.md", "[[B/Target]]")
        try write("Rooted.md", "[[/Notes/B/Target]]")
        try write("Alias.md", "[[Goal]]")
        try write("Plain.md", "[[Target]]")
        try write("Markdown.md", "[t](Notes/B/Target.md)")
        try write("Unrelated.md", "[[Elsewhere]]")
        _ = try await index.reconcile(root: vault)
        let expected: Set<String> = ["Other/Relative.md", "Other/DotRelative.md", "Partial.md", "Rooted.md", "Alias.md", "Plain.md", "Markdown.md"]
        let byPath = try await prefilteredPaths(.linksTo(.path(try VaultPath("Notes/B/Target.md"))))
        XCTAssertTrue(expected.isSubset(of: byPath), "Missing: \(expected.subtracting(byPath).sorted())")
        XCTAssertFalse(byPath.contains("Unrelated.md"), "The requirement still narrows the query.")
        let byTarget = try await prefilteredPaths(.linksTo(.target("Target")))
        XCTAssertTrue(expected.isSubset(of: byTarget), "Missing: \(expected.subtracting(byTarget).sorted())")
    }

    func testLinkPrefilterResolvesAWrittenTargetFromEveryFolder() async throws {
        try write("Note.md", "root note")
        try write("A/Note.md", "folder note")
        try write("A/Row.md", "[n](Note.md)")
        try write("Unrelated.md", "[[Elsewhere]]")
        _ = try await index.reconcile(root: vault)
        let paths = try await prefilteredPaths(.linksTo(.target("Note")))
        XCTAssertTrue(paths.contains("A/Row.md"), "From A/Row.md, `Note` is A/Note.md, which it links to.")
        XCTAssertFalse(paths.contains("Unrelated.md"))
    }

    func testEmptyExtensionRequirementKeepsFilesWithoutExtension() async throws {
        try write("Makefile", "all:")
        try write("Note.md", "note")
        _ = try await index.reconcile(root: vault)
        let paths = try await prefilteredPaths(.hasAnyExtension([""]))
        XCTAssertTrue(paths.contains("Makefile"))
    }

    func testProviderReportsDatabaseErrorsInsteadOfEmptyAnswers() async throws {
        try write("Note.md", "note")
        _ = try await index.reconcile(root: vault)
        let provider = index.baseRecordProvider
        XCTAssertNotNil(provider.record(at: try VaultPath("Note.md")))
        XCTAssertNoThrow(try provider.throwIfLookupFailed())
        try await index.databaseQueue.write { database in try database.execute(sql: "DROP TABLE aliases") }
        XCTAssertNil(provider.resolveLinkTarget("Missing", from: try VaultPath("Note.md")))
        XCTAssertThrowsError(try provider.throwIfLookupFailed(), "A failed lookup is reported after the run.")
    }

    // MARK: Record decoding

    func testScalarFastPathDecodesExactlyAsJSONDecoder() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let texts = ["", "EE330", "https://example.com/a/b", "Notes/Old name.md", "quote \" inside", "back\\slash", "tab\tand\nnewline",
                     "café", "e\u{301}", "emoji 🧪", "[[Link|alias]]", "\\/", "/", "\u{7F}"]
        for text in texts {
            for isPlain in [true, false] {
                let node = BaseFrontmatterNode.scalar(text: text, isPlain: isPlain)
                let encodedNode = String(decoding: try encoder.encode(node), as: UTF8.self)
                let decodedByJSONDecoder = try decoder.decode(BaseFrontmatterNode.self, from: Data(encodedNode.utf8))
                if let fastNode = VaultIndex.decodedScalarNode(encodedNode) { XCTAssertEqual(fastNode, decodedByJSONDecoder, encodedNode) }
                XCTAssertEqual(decodedByJSONDecoder, node)
            }
        }
        let encodedPathNode = String(decoding: try encoder.encode(BaseFrontmatterNode.scalar(text: "Notes/Old name.md", isPlain: true)), as: UTF8.self)
        XCTAssertEqual(VaultIndex.decodedScalarNode(encodedPathNode), .scalar(text: "Notes/Old name.md", isPlain: true), "The index's own encoding takes the fast path.")
        XCTAssertEqual(VaultIndex.decodedScalarNode(#"{"scalar":{"isPlain":false,"text":"a\/b"}}"#), .scalar(text: "a/b", isPlain: false))
        XCTAssertEqual(VaultIndex.decodedScalarNode(#"{"scalar":{"text":"plain","isPlain":true}}"#), .scalar(text: "plain", isPlain: true))
        XCTAssertNil(VaultIndex.decodedScalarNode(#"{"scalar":{"text":"a\nb","isPlain":true}}"#), "Other escapes fall back to JSONDecoder.")
        XCTAssertNil(VaultIndex.decodedScalarNode(#"{"sequence":{"_0":[]}}"#))
        XCTAssertNil(VaultIndex.decodedScalarNode(#"{"scalar":{"text":"a","isPlain":true}} "#))
        XCTAssertNil(VaultIndex.decodedScalarNode(#"{"scalar":{"text":"a"}}"#))
    }
}
