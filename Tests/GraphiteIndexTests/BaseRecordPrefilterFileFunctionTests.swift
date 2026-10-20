import XCTest
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

/// The base pre-filter keeps every row the evaluator keeps when a filter names a file with
/// `file("Name")`, which the evaluator resolves from each row's own folder.
final class BaseRecordPrefilterFileFunctionTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "PrefilterVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
    }

    private func write(_ relativePath: String, _ text: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    /// The paths a base's filter keeps, once over the pre-filtered records and once over every record.
    private func filteredPaths(_ filter: String) async throws -> (prefiltered: [String], all: [String]) {
        let definition = try BaseDefinition.parse("filters:\n  and:\n    - \(filter)\nviews:\n  - type: table\n    name: Table\n")
        let environment = BaseEvaluationEnvironment()
        let provider = index.baseRecordProvider
        let filters = [definition.filters].compactMap { filter in filter }
        let prefilter = BaseRecordPrefilter.extract(from: filters, definition: definition, environment: environment, thisRecord: nil, provider: provider)
        let prefilteredBatch = try await index.baseRecords(matching: prefilter)
        let allBatch = try await index.baseRecords(matching: BaseRecordPrefilter(), limit: VaultIndex.maximumBaseRecordLimit)
        XCTAssertFalse(allBatch.isTruncated)
        let (prefilteredRows, allRows) = await Task.detached {
            let engine = BaseQueryEngine(definition: definition, environment: environment, thisRecord: nil, provider: provider)
            return (engine.run(viewIndex: 0, records: prefilteredBatch.records).rows, engine.run(viewIndex: 0, records: allBatch.records).rows)
        }.value
        return (prefilteredRows.map(\.path.rawValue).sorted(), allRows.map(\.path.rawValue).sorted())
    }

    /// BUG-BASES-02: a Markdown body link matched another note's alias in `file.hasLink`.
    func testAMarkdownLinkDoesNotNameANoteByItsAliasAsInBacklinks() async throws {
        try write("People/Robert.md", "---\naliases: [Bob]\n---\nRobert\n")
        try write("Notes/A.md", "[see](Bob)")
        try write("Notes/B.md", "[[Bob]]")
        _ = try await index.reconcile(root: vault)
        let backlinkPaths = try await index.backlinks(to: try VaultPath("People/Robert.md")).map(\.rawValue)
        XCTAssertEqual(backlinkPaths, ["Notes/B.md"], "Aliases are Wikilink names; a Markdown link names files only.")
        let outcome = try await filteredPaths("'file.hasLink(file(\"People/Robert.md\"))'")
        XCTAssertEqual(outcome.all, backlinkPaths, "A base resolves a link as backlinks do.")
        XCTAssertEqual(outcome.prefiltered, outcome.all)
    }

    func testFileFunctionWithABareNameKeepsRowsThatLinkToTheNoteBesideThem() async throws {
        try write("Note.md", "the note at the vault root")
        try write("A/Note.md", "the note beside the linking note")
        try write("A/X.md", "[[A/Note]]")
        try write("Unrelated.md", "[[Elsewhere]]")
        _ = try await index.reconcile(root: vault)
        let outcome = try await filteredPaths("'file.hasLink(file(\"Note\"))'")
        XCTAssertEqual(outcome.all, ["A/X.md"], "The evaluator resolves file(\"Note\") from the row's folder.")
        XCTAssertEqual(outcome.prefiltered, outcome.all)
    }

    func testFileFunctionWithAFullPathKeepsTheRowsThatLinkToThatFile() async throws {
        try write("Note.md", "the note at the vault root")
        try write("A/Note.md", "the note beside the linking note")
        try write("A/X.md", "[[A/Note]]")
        try write("B/Y.md", "[[Note]]")
        _ = try await index.reconcile(root: vault)
        let outcome = try await filteredPaths("'file.hasLink(file(\"A/Note.md\"))'")
        XCTAssertEqual(outcome.prefiltered, outcome.all)
        XCTAssertTrue(outcome.all.contains("A/X.md"))
    }
}
