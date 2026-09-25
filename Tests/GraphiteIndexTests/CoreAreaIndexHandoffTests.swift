import XCTest
import GraphiteCore
@testable import GraphiteIndex

/// Regressions for changes other groups handed to the index files: the base pre-filter
/// stays a superset of the evaluator's result, Markdown links resolve in every format
/// Obsidian writes, and a link a move cannot rewrite is reported.
final class CoreAreaIndexHandoffTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("HandoffVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ relativePath: String, _ text: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The paths a base's filters keep, once over the pre-filtered records and once over
    /// every record, and whether the pre-filtered batch was truncated.
    private func filteredPaths(_ baseSource: String, this thisPath: String? = nil) async throws -> (prefiltered: [String], all: [String], isTruncated: Bool) {
        let definition = try BaseDefinition.parse(baseSource)
        let environment = BaseEvaluationEnvironment()
        var thisRecord: BaseFileRecord?
        if let thisPath { thisRecord = try await index.baseRecord(at: VaultPath(thisPath)) }
        let provider = index.baseRecordProvider
        let filters = [definition.filters].compactMap { filter in filter }
        let prefilter = BaseRecordPrefilter.extract(from: filters, definition: definition, environment: environment, thisRecord: thisRecord, provider: provider)
        let prefilteredBatch = try await index.baseRecords(matching: prefilter)
        let allBatch = try await index.baseRecords(matching: BaseRecordPrefilter(), limit: VaultIndex.maximumBaseRecordLimit)
        XCTAssertFalse(allBatch.isTruncated)
        let evaluatedThisRecord = thisRecord
        let (prefilteredRows, allRows) = await Task.detached {
            let engine = BaseQueryEngine(definition: definition, environment: environment, thisRecord: evaluatedThisRecord, provider: provider)
            return (engine.run(viewIndex: 0, records: prefilteredBatch.records).rows, engine.run(viewIndex: 0, records: allBatch.records).rows)
        }.value
        return (prefilteredRows.map(\.path.rawValue).sorted(), allRows.map(\.path.rawValue).sorted(), prefilteredBatch.isTruncated)
    }

    // MARK: Base pre-filter (F19, F408, P66)

    func testHasLinkPrefilterKeepsEveryLinkTheEvaluatorResolves() async throws {
        try write("Folder/Sub/Target.md", "---\naliases: [My Alias]\n---\ntarget")
        try write("This.md", "the base's own note")
        try write("A/Name.md", "[[Target]]")
        try write("A/Partial.md", "[[Sub/Target]]")
        try write("A/Labelled.md", "[[Sub/Target|x]]")
        try write("A/Alias.md", "[[My Alias]]")
        try write("A/Padded.md", "[[Target ]]")
        try write("Other/Relative.md", "[r](../Folder/Sub/Target.md)")
        try write("Other/Shortest.md", "[s](Target.md)")
        try write("Other/Absolute.md", "[a](Folder/Sub/Target.md)")
        try write("Unrelated.md", "[[Elsewhere]]")
        _ = try await index.reconcile(root: vault)
        let base = "filters:\n  and:\n    - file.hasLink(link(\"Folder/Sub/Target.md\"))\nviews:\n  - type: table\n    name: Table\n"
        let outcome = try await filteredPaths(base)
        XCTAssertEqual(outcome.prefiltered, outcome.all)
        XCTAssertTrue(Set(["A/Name.md", "A/Partial.md", "A/Labelled.md", "A/Alias.md", "Other/Relative.md", "Other/Shortest.md", "Other/Absolute.md"])
            .isSubset(of: Set(outcome.all)), "\(outcome.all)")
        XCTAssertFalse(outcome.all.contains("Unrelated.md"))
    }

    func testTagPropertyAndFolderPrefiltersKeepStoredTextFoundationFoldsIntoASCII() async throws {
        try write("German.md", "---\ntags: [straße]\n---\n")
        try write("Kelvin.md", "---\ntags: [\u{212A}ids]\n\u{212A}ey: value\n---\n")
        try write("Plain.md", "---\ntags: [other]\nother: value\n---\n")
        _ = try await index.reconcile(root: vault)
        let expectedPaths = ["file.hasTag(\"strasse\")": ["German.md"], "file.hasTag(\"kids\")": ["Kelvin.md"], "file.hasProperty(\"key\")": ["Kelvin.md"]]
        for (filter, expected) in expectedPaths {
            let outcome = try await filteredPaths("filters:\n  and:\n    - '\(filter)'\nviews:\n  - type: table\n    name: Table\n")
            XCTAssertEqual(outcome.all, expected, "The evaluator folds these names: \(filter)")
            XCTAssertEqual(outcome.prefiltered, outcome.all, filter)
        }
    }

    func testPropertyEqualityNarrowsTheQueryWithoutLosingMatches() async throws {
        var files: [IndexedFile] = []
        for noteIndex in 0..<6_000 {
            let status = noteIndex.isMultiple(of: 2) ? "reading" : "done"
            files.append(IndexedFile(path: try VaultPath(String(format: "Notes/Note %05d.md", noteIndex)), size: 1, modified: .now, markdown: "---\nstatus: \(status)\n---\n"))
        }
        files.append(IndexedFile(path: try VaultPath("Encoded.md"), size: 1, modified: .now, markdown: "---\nstatus: \"[x](read%69ng)\"\n---\n"))
        files.append(IndexedFile(path: try VaultPath("Linked.md"), size: 1, modified: .now, markdown: "---\nstatus: \"[[Reading]]\"\n---\n"))
        files.append(IndexedFile(path: try VaultPath("Reading.md"), size: 1, modified: .now, markdown: "reading"))
        try await index.update(files, generation: "test")
        let outcome = try await filteredPaths("filters:\n  and:\n    - status == \"reading\"\nviews:\n  - type: table\n    name: Table\n")
        XCTAssertFalse(outcome.isTruncated, "Only notes whose status can equal the text are loaded.")
        XCTAssertEqual(outcome.prefiltered, outcome.all)
        XCTAssertGreaterThanOrEqual(outcome.all.count, 3_000)
    }

    // MARK: Markdown link formats (F7)

    func testMarkdownLinksResolveInEveryFormatObsidianWrites() async throws {
        try write("Folder/Sub/Target.md", "---\naliases: [My Alias]\n---\ntarget")
        try write("Other/Shortest.md", "[s](Target.md)")
        try write("Other/Absolute.md", "[a](Folder/Sub/Target.md)")
        try write("Other/Encoded.md", "[e](Folder%2FSub%2FTarget.md) and [p](Sub/Target.md)")
        try write("Folder/Sub/Beside.md", "[b](./Target.md)")
        try write("Other/Relative.md", "[r](../Folder/Sub/Target.md)")
        try write("Other/ByAlias.md", "[x](My%20Alias)")
        try write("Other/RelativeWiki.md", "[[../Folder/Sub/Target]]")
        _ = try await index.reconcile(root: vault)
        let target = try VaultPath("Folder/Sub/Target.md")
        let expectedSources = ["Folder/Sub/Beside.md", "Other/Absolute.md", "Other/Encoded.md", "Other/Relative.md", "Other/RelativeWiki.md", "Other/Shortest.md"]

        let backlinks = try await index.backlinks(to: target).map(\.rawValue)
        XCTAssertEqual(backlinks, expectedSources, "An alias is a Wikilink name; a Markdown link names a file.")
        let linkingNotes = try await index.linkingNotes(to: target).map(\.rawValue)
        XCTAssertEqual(linkingNotes, expectedSources)

        let graph = try await index.linkGraph()
        let graphSources = graph.edges.filter { edge in edge.target == target.rawValue }.map(\.source).sorted()
        XCTAssertEqual(graphSources, expectedSources)

        let resolver = try await index.graphLinkResolver()
        let source = try VaultPath("Other/Note.md")
        for writtenTarget in ["Target.md", "Target", "Folder/Sub/Target.md", "Sub/Target.md", "Folder%2FSub%2FTarget.md", "My%20Alias", "My Alias",
                              "./Target.md", "../Folder/Sub/Target.md", "../Folder/Sub/Target", "Missing.md", "/Folder/Sub/Target.md"] {
            for isWiki in [true, false] {
                let expected = try await index.resolve(writtenTarget, from: source, isWiki: isWiki).map(\.rawValue)
                XCTAssertEqual(resolver.resolve(writtenTarget, from: source, isWiki: isWiki), expected, "\(writtenTarget), isWiki \(isWiki)")
            }
        }
        let shortestResolution = try await index.resolve("Target.md", from: source, isWiki: false)
        XCTAssertEqual(shortestResolution, [target])
    }

    func testRenamingATargetRewritesShortestAndAbsoluteMarkdownLinks() async throws {
        try write("Folder/Sub/Target.md", "target")
        try write("Other/Shortest.md", "[s](Target.md)")
        try write("Other/Absolute.md", "[a](Folder/Sub/Target.md)")
        try write("Other/Reference.md", "[t][ref]\n\n[ref]: Folder/Sub/Target.md\n")
        _ = try await index.reconcile(root: vault)
        let operations = VaultFileOperations(store: VaultStore(root: vault), index: index)
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Folder/Sub/Target.md"), to: VaultPath("Folder/Sub/Renamed.md"))
        let report = try await operations.move(VaultPath("Folder/Sub/Target.md"), to: VaultPath("Folder/Sub/Renamed.md"), applying: plan)
        XCTAssertEqual(report.notesNotUpdated, [], "A reference link's definition is rewritten, so its note is not reported.")
        XCTAssertEqual(try read("Other/Shortest.md"), "[s](Renamed.md)")
        XCTAssertEqual(try read("Other/Absolute.md"), "[a](Folder/Sub/Renamed.md)")
        XCTAssertEqual(try read("Other/Reference.md"), "[t][ref]\n\n[ref]: Folder/Sub/Renamed.md\n")
    }

    func testIndexedMarkdownTargetsAreStoredForEveryFormat() throws {
        let source = try VaultPath("Other/Note.md")
        XCTAssertEqual(VaultIndex.storedLinkTarget("Target.md", isWiki: false, source: source), "Target.md")
        XCTAssertEqual(VaultIndex.storedLinkTarget("Folder/Sub/Target%20Two.md#Part", isWiki: false, source: source), "Folder/Sub/Target Two.md")
        XCTAssertEqual(VaultIndex.storedLinkTarget("../Folder/Target.md", isWiki: false, source: source), "Folder/Target.md")
        XCTAssertEqual(VaultIndex.storedLinkTarget("./Target.md", isWiki: false, source: source), "Other/Target.md")
        XCTAssertEqual(VaultIndex.storedLinkTarget("#Heading", isWiki: false, source: source), "Other/Note.md")
        XCTAssertEqual(VaultIndex.storedLinkTarget("https://example.com/a%20b", isWiki: false, source: source), "https://example.com/a%20b")
    }

    // MARK: Link prefilter by folded names (F20)

    func testHasLinkPrefilterKeepsLinksWrittenInAnotherCase() async throws {
        try write("People/Émile.md", "person")
        try write("Kelvin.md", "unit")
        try write("Upper.md", "[[ÉMILE]]")
        try write("Lower.md", "[[émile]]")
        try write("Sign.md", "[[\u{212A}elvin]]")
        try write("Unrelated.md", "[[Elsewhere]]")
        _ = try await index.reconcile(root: vault)
        let emile = try await filteredPaths("filters:\n  and:\n    - file.hasLink(link(\"People/Émile.md\"))\nviews:\n  - type: table\n    name: Table\n")
        XCTAssertEqual(emile.all, ["Lower.md", "Upper.md"])
        XCTAssertEqual(emile.prefiltered, emile.all)
        let kelvin = try await filteredPaths("filters:\n  and:\n    - file.hasLink(link(\"Kelvin.md\"))\nviews:\n  - type: table\n    name: Table\n")
        XCTAssertEqual(kelvin.all, ["Sign.md"])
        XCTAssertEqual(kelvin.prefiltered, kelvin.all)
        let destination = try VaultPath("People/Émile.md")
        let condition = try await index.databaseQueue.read { database in try VaultIndex.linkCondition(for: .path(destination), in: database) }
        XCTAssertNotNil(condition, "A name outside ASCII still narrows the query.")
    }

    // MARK: Backlinks by relative and partial paths (F26)

    func testRenamingRewritesRelativeAndPartialWikilinks() async throws {
        try write("A/B/Note.md", "note")
        try write("Other/Linker.md", "[[B/Note]] and [[../A/B/Note]]")
        _ = try await index.reconcile(root: vault)
        let noteBacklinks = index.baseRecordProvider.backlinks(to: try VaultPath("A/B/Note.md")).map(\.rawValue)
        XCTAssertEqual(noteBacklinks, ["Other/Linker.md"], "file.backlinks finds both links.")
        let operations = VaultFileOperations(store: VaultStore(root: vault), index: index)
        let plan = try await operations.linkUpdates(forMoving: VaultPath("A/B/Note.md"), to: VaultPath("A/B/Renamed.md"))
        let report = try await operations.move(VaultPath("A/B/Note.md"), to: VaultPath("A/B/Renamed.md"), applying: plan)
        XCTAssertEqual(report.notesNotUpdated, [])
        let rewritten = try read("Other/Linker.md")
        XCTAssertFalse(rewritten.contains("Note]]"), rewritten)
        _ = try await index.reconcile(root: vault)
        let renamedBacklinks = try await index.backlinks(to: VaultPath("A/B/Renamed.md")).map(\.rawValue)
        XCTAssertEqual(renamedBacklinks, ["Other/Linker.md"], rewritten)
    }

    // MARK: Links a move cannot locate (F51)

    func testMovingKeepsANoteWhoseLinkCannotBeLocatedUnchanged() async throws {
        let original = "[r]: r.md\ntext [x](Old.md) end\n"
        try write("Old.md", "old")
        try write("Linker.md", original)
        _ = try await index.reconcile(root: vault)
        let operations = VaultFileOperations(store: VaultStore(root: vault), index: index)
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Old.md"), to: VaultPath("New.md"))
        let report = try await operations.move(VaultPath("Old.md"), to: VaultPath("New.md"), applying: plan)
        if report.updatedNotes.map(\.rawValue).contains("Linker.md") {
            XCTAssertEqual(try read("Linker.md"), "[r]: r.md\ntext [x](New.md) end\n", "A located link is rewritten in place.")
        } else {
            XCTAssertEqual(try read("Linker.md"), original, "A link without its exact place is never written blindly.")
            XCTAssertEqual(report.failures[try VaultPath("Linker.md")], .linksNotLocated)
        }
    }

    // MARK: Search text the word index cannot find (F100, F375, F376, F132)

    private func searchedPaths(_ query: String) async throws -> [String] {
        try await index.search(query).results.map(\.path.rawValue).sorted()
    }

    func testSearchFindsWordsInsideUnspacedTextAndSymbols() async throws {
        try write("Notes/Beijing.md", "我今天去北京玩")
        try write("Notes/Heart.md", "I ❤ tea")
        try write("Notes/Alpha.md", "first note")
        _ = try await index.reconcile(root: vault)
        let beijing = try await searchedPaths("北京")
        XCTAssertEqual(beijing, ["Notes/Beijing.md"])
        let beijingByLine = try await searchedPaths("line:北京")
        XCTAssertEqual(beijingByLine, ["Notes/Beijing.md"])
        let heart = try await searchedPaths("❤️")
        XCTAssertEqual(heart, ["Notes/Heart.md"])
        let withoutHeart = try await searchedPaths("-❤️")
        XCTAssertEqual(withoutHeart, ["Notes/Alpha.md", "Notes/Beijing.md"])
        let beijingMatches = try await index.search("北京").results.first?.matches ?? []
        XCTAssertFalse(beijingMatches.isEmpty, "The excerpt shows where the word is.")
    }

    func testNoteExtensionIsNotSearchedAsText() async throws {
        try write("Alpha.md", "first")
        try write("Beta.md", "second")
        _ = try await index.reconcile(root: vault)
        let extensionOnly = try await searchedPaths("md")
        XCTAssertEqual(extensionOnly, [])
        let withoutExtension = try await searchedPaths("-md")
        XCTAssertEqual(withoutExtension, ["Alpha.md", "Beta.md"])
    }

    func testLineScopeFindsUnspacedWordsAndSymbolsOnOneLine() async throws {
        try write("Notes/Tokyo.md", "一行目\n私は東京都に行く")
        try write("Notes/Together.md", "🙂 apple pie\nbanana")
        try write("Notes/Apart.md", "🙂 here\napple there")
        _ = try await index.reconcile(root: vault)
        let tokyo = try await searchedPaths("line:東京")
        XCTAssertEqual(tokyo, ["Notes/Tokyo.md"])
        let together = try await searchedPaths("line:(🙂 apple)")
        XCTAssertEqual(together, ["Notes/Together.md"])
    }

    // MARK: Slow patterns checked note by note (F134)

    func testRunawayPatternInALineSearchStopsWithAnError() async throws {
        try write("Runaway.md", String(repeating: "a", count: 32) + "!")
        _ = try await index.reconcile(root: vault)
        let clock = ContinuousClock()
        let startTime = clock.now
        do {
            _ = try await index.search("line:/(a+)+$/")
            XCTFail("A pattern that backtracks without end must stop.")
        } catch let error as SearchError {
            XCTAssertEqual(error, .regularExpressionTooSlow)
        }
        XCTAssertLessThan(clock.now - startTime, .seconds(10))
    }

    // MARK: File names in another case (F242)

    func testFileAndPathSearchIgnoreCaseOutsideASCII() async throws {
        try write("People/Émile.md", "person")
        try write("People/Other.md", "person")
        _ = try await index.reconcile(root: vault)
        let byName = try await searchedPaths("file:émile")
        XCTAssertEqual(byName, ["People/Émile.md"])
        let byPath = try await searchedPaths("path:PEOPLE/ÉMILE")
        XCTAssertEqual(byPath, ["People/Émile.md"])
    }
}
