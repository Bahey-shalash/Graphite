import XCTest
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

/// The base pre-filter never leaves out a record the evaluator would keep: over small
/// generated vaults and link filters, the rows found through the pre-filter are the rows
/// found by evaluating every record.
final class BaseRecordPrefilterSupersetTests: XCTestCase {
    private var temporaryFolders: [URL] = []

    override func tearDown() async throws {
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) } // Best-effort removal of temporary folders.
        temporaryFolders = []
    }

    /// A small deterministic generator, so a failure names the same vault on every run.
    private struct SeededChoices {
        var state: UInt64
        mutating func next(below count: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(count))
        }
    }

    private static let noteLocations = ["Note.md", "A/Note.md", "B/Note.md"]
    private static let linkingNoteLocations = ["X.md", "A/X.md", "B/X.md", "C/X.md"]
    private static let linkTexts = ["[[Note]]", "[[A/Note]]", "[[/Note]]", "[[B/Note]]", "[[Note.md]]", "plain text without a link"]
    private static let filters = [
        "'file.hasLink(file(\"Note\"))'",
        "'file.hasLink(file(\"A/Note.md\"))'",
        "'file.hasLink(file(\"B/Note\"))'",
        "'file.hasLink(file(\"Note.md\"))'",
        "'file.hasLink(\"Note\")'",
        "'file.hasLink(link(\"Note\"))'",
    ]

    private func makeVault(_ files: [String: String]) throws -> (vault: URL, index: VaultIndex) {
        let vault = try TemporaryVault.make(prefix: "PrefilterSupersetVault", for: self).root
        temporaryFolders += [vault, vault.appendingPathExtension("cache")]
        for (relativePath, text) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: location)
        }
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        return (vault, index)
    }

    private func filteredPaths(_ filter: String, in index: VaultIndex) async throws -> (prefiltered: Set<String>, all: Set<String>) {
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
        return (Set(prefilteredRows.map(\.path.rawValue)), Set(allRows.map(\.path.rawValue)))
    }

    func testThePrefilterKeepsEveryRowTheEvaluatorKeepsOverGeneratedVaultsAndLinkFilters() async throws {
        var choices = SeededChoices(state: 20_261_019)
        var vaultsWithKeptRows = 0
        for vaultNumber in 0..<24 {
            var files: [String: String] = [:]
            for location in Self.noteLocations where choices.next(below: 2) == 0 { files[location] = "the note at \(location)" }
            files["Other.md"] = "an unrelated note"
            for location in Self.linkingNoteLocations { files[location] = Self.linkTexts[choices.next(below: Self.linkTexts.count)] }
            let (vault, index) = try makeVault(files)
            _ = try await index.reconcile(root: vault)

            for filter in Self.filters {
                let outcome = try await filteredPaths(filter, in: index)
                XCTAssertEqual(outcome.prefiltered, outcome.all, "vault \(vaultNumber) \(filter) \(files.sorted { $0.key < $1.key })")
                if !outcome.all.isEmpty { vaultsWithKeptRows += 1 }
            }
        }
        XCTAssertGreaterThan(vaultsWithKeptRows, 0, "The generated vaults include filters that keep rows, so the comparison is not empty.")
    }

    func testARootNoteBesideTheFilterNameDoesNotHideALinkToTheNoteBesideTheLinkingNote() async throws {
        let (vault, index) = try makeVault([
            "Note.md": "the note at the vault root",
            "A/Note.md": "the note beside the linking note",
            "A/X.md": "[[A/Note]]",
        ])
        _ = try await index.reconcile(root: vault)

        let outcome = try await filteredPaths("'file.hasLink(file(\"Note\"))'", in: index)

        XCTAssertEqual(outcome.all, ["A/X.md"])
        XCTAssertEqual(outcome.prefiltered, outcome.all)
    }
}
