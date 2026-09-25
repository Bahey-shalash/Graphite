import XCTest
import GRDB
@testable import GraphiteIndex
import GraphiteCore

/// Paging, cancellation, text matching and error reporting of `VaultIndex.search`, the
/// quick switcher, and tag suggestions.
final class IndexSearchFixTests: XCTestCase {
    private var directory: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func note(_ path: String, _ markdown: String?, modified: Double = 100) throws -> IndexedFile {
        IndexedFile(path: try VaultPath(path), size: 1, modified: Date(timeIntervalSince1970: modified), markdown: markdown)
    }

    private func paths(_ query: String) async throws -> [String] {
        try await index.search(query).results.map(\.path.rawValue).sorted()
    }

    /// Every result of a search, following continuations to the end.
    private func allPages(_ query: String, sortOrder: SearchSortOrder = .fileNameAscending, limit: Int = 50) async throws -> [String] {
        var page = try await index.search(query, sortOrder: sortOrder, limit: limit)
        var collected = page.results.map(\.path.rawValue)
        var pageCount = 1
        while let continuation = page.continuation {
            page = try await index.search(query, sortOrder: sortOrder, limit: limit, after: continuation)
            collected += page.results.map(\.path.rawValue)
            pageCount += 1
            XCTAssertLessThan(pageCount, 100, "Pages must advance.")
            if pageCount >= 100 { break }
        }
        return collected
    }

    // MARK: - Cancellation and page bounds

    func testCancelledSearchThrowsCancellationError() async throws {
        let body = String(repeating: "The quick brown fox jumps over the lazy dog again. ", count: 200)
        try await index.update(try (0..<600).map { number in try note("Bulk/Note \(number).md", body) }, generation: "bulk")
        let searchedIndex: VaultIndex = index
        let alreadyCancelled = Task {
            withUnsafeCurrentTask { task in task?.cancel() }
            return try await searchedIndex.search("line:(quick -brown)")
        }
        do {
            _ = try await alreadyCancelled.value
            XCTFail("A cancelled search must not return results.")
        } catch is CancellationError {}

        let clock = ContinuousClock()
        let startTime = clock.now
        // Every note is a candidate and none matches, so the search checks the whole vault
        // unless cancellation stops it.
        let running = Task { try await searchedIndex.search("line:(quick -brown)") }
        try await Task.sleep(for: .milliseconds(100))
        running.cancel()
        do {
            _ = try await running.value
            XCTFail("A search cancelled while it runs must stop.")
        } catch is CancellationError {}
        XCTAssertLessThan(clock.now - startTime, .seconds(2))
        // The index is usable right away.
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 600)
    }

    func testLongSearchWithoutMatchesLeavesTheIndexToOtherLookups() async throws {
        let body = String(repeating: "The quick brown fox jumps over the lazy dog again. ", count: 200)
        try await index.update(try (0..<1_500).map { number in try note("Bulk/Note \(number).md", body) }, generation: "bulk")
        let searchedIndex: VaultIndex = index
        let clock = ContinuousClock()
        let searchStartTime = clock.now
        // Every note is a candidate and none matches, so the search reads the whole vault.
        let running = Task { try await searchedIndex.search("line:(quick -brown)") }
        try await Task.sleep(for: .milliseconds(100))
        let lookupStartTime = clock.now
        let switcherMatches = try await index.quickSwitcherMatches(for: "note 7")
        let lookupDuration = clock.now - lookupStartTime
        let page = try await running.value
        let searchDuration = clock.now - searchStartTime
        XCTAssertFalse(switcherMatches.isEmpty)
        XCTAssertTrue(page.results.isEmpty)
        XCTAssertNil(page.continuation, "An empty page is the last one.")
        XCTAssertLessThan(lookupDuration, .seconds(1))
        XCTAssertLessThan(lookupDuration * 2, searchDuration, "The lookup must not wait for the whole search.")
    }

    func testFirstPageKeepsCheckingPastTheCandidateLimitUntilAMatch() async throws {
        var files = try (0..<(VaultIndex.maximumCheckedCandidatesPerPage + 100)).map { number in
            try note(String(format: "Bulk/Item %05d.md", number), "---\nstatus: todo\n---\nbody")
        }
        files.append(try note("Bulk/Zulu.md", "---\nstatus: done\n---\nbody"))
        for start in stride(from: 0, to: files.count, by: 1_000) {
            try await index.update(Array(files[start..<min(start + 1_000, files.count)]), generation: "bulk")
        }
        let page = try await index.search("[status:done]")
        XCTAssertEqual(page.results.map(\.path.rawValue), ["Bulk/Zulu.md"], "A page with candidates left must not come back empty.")
        XCTAssertNil(page.continuation)
    }

    func testContinuationDoesNotSkipAfterAnEarlierFileIsRemoved() async throws {
        try await index.update(try (1...60).map { number in try note(String(format: "P/Item %02d.md", number), "common text") }, generation: "bulk")
        let firstPage = try await index.search("common")
        XCTAssertEqual(firstPage.results.last?.path.rawValue, "P/Item 50.md")
        // The vault folder has no files, so the refresh removes the note from the index.
        try await index.refresh(paths: [try VaultPath("P/Item 03.md")], root: directory)
        let secondPage = try await index.search("common", after: firstPage.continuation)
        XCTAssertEqual(secondPage.results.map(\.path.rawValue), (51...60).map { number in String(format: "P/Item %02d.md", number) })
        XCTAssertNil(secondPage.continuation)
    }

    func testPagesFollowEverySortOrderWithoutGapsOrRepeats() async throws {
        // Equal names in different folders and equal times exercise the path tie-break.
        let files = try (0..<130).map { number in
            try note(String(format: "Folder %d/Item %03d.md", number % 3, number / 2), "common text", modified: Double(1_000 + number / 4))
        }
        try await index.update(files, generation: "bulk")
        for sortOrder in SearchSortOrder.allCases {
            let exact = try await allPages("common", sortOrder: sortOrder, limit: 7)
            let checked = try await allPages("line:(common text)", sortOrder: sortOrder, limit: 11)
            XCTAssertEqual(Set(exact).count, files.count, "\(sortOrder)")
            XCTAssertEqual(exact.count, files.count, "\(sortOrder)")
            XCTAssertEqual(checked, exact, "\(sortOrder)")
        }
        let newestFirst = try await allPages("common", sortOrder: .modifiedNewestFirst, limit: 9)
        let expectedNewestFirst = files.sorted { leftFile, rightFile in
            leftFile.modified != rightFile.modified ? leftFile.modified > rightFile.modified : leftFile.path.rawValue < rightFile.path.rawValue
        }.map(\.path.rawValue)
        XCTAssertEqual(newestFirst, expectedNewestFirst)
    }

    func testLimitBelowTheNameMatchesStillAdvances() async throws {
        try await index.update(try (1...25).map { number in try note(String(format: "Z/zeta %02d.md", number), "text") }, generation: "bulk")
        let firstPage = try await index.search("zeta", limit: 5)
        XCTAssertEqual(firstPage.results.count, 5)
        XCTAssertNotNil(firstPage.continuation)
        let everything = try await allPages("zeta", limit: 5)
        XCTAssertEqual(everything.count, 25)
        XCTAssertEqual(Set(everything).count, 25)
    }

    // MARK: - Words and text

    func testWordsFoldAsTheFullTextIndexFoldsThem() async throws {
        try await index.update([
            try note("Notes/Stadt.md", "Die Straße ist lang"),
            try note("Notes/Upper.md", "STRASSE upper"),
            try note("Notes/Ligature.md", "the ﬁle is here"),
            try note("Notes/Accents.md", "Crème brûlée"),
        ], generation: "test")
        let sharpS = try await paths("Straße")
        XCTAssertEqual(sharpS, ["Notes/Stadt.md"])
        let doubleS = try await paths("strasse")
        XCTAssertEqual(doubleS, ["Notes/Upper.md"])
        let ligature = try await paths("ﬁle")
        XCTAssertEqual(ligature, ["Notes/Ligature.md"])
        let prefixWithoutAccents = try await paths("CREME brul")
        XCTAssertEqual(prefixWithoutAccents, ["Notes/Accents.md"])
    }

    func testSymbolsAndEmojiAreFoundAsText() async throws {
        try await index.update([
            try note("Notes/A.md", "I am happy 🙂"),
            try note("Notes/B.md", "nothing here, it costs 5 €"),
            try note("Media/photo.jpg", nil),
        ], generation: "test")
        let emoji = try await paths("🙂")
        XCTAssertEqual(emoji, ["Notes/A.md"])
        let currency = try await paths("€")
        XCTAssertEqual(currency, ["Notes/B.md"])
        let withoutEmoji = try await paths("-🙂")
        XCTAssertEqual(withoutEmoji, ["Media/photo.jpg", "Notes/B.md"])
        let contentOnly = try await paths("content:🙂")
        XCTAssertEqual(contentOnly, ["Notes/A.md"])
    }

    func testWordsInsideTextWithoutSpacesAreFound() async throws {
        try await index.update([
            try note("Notes/Tokyo.md", "私は東京都に行く"),
            try note("Notes/Beijing.md", "我们今天去北京吃饭"),
            try note("Notes/Thai.md", "ผมชอบกินข้าวผัด"),
        ], generation: "test")
        let tokyo = try await paths("東京")
        XCTAssertEqual(tokyo, ["Notes/Tokyo.md"])
        let beijing = try await paths("北京")
        XCTAssertEqual(beijing, ["Notes/Beijing.md"])
        let eating = try await paths("吃饭")
        XCTAssertEqual(eating, ["Notes/Beijing.md"])
        let thai = try await paths("ข้าวผัด")
        XCTAssertEqual(thai, ["Notes/Thai.md"])
        let excluded = try await paths("-北京")
        XCTAssertEqual(excluded, ["Notes/Thai.md", "Notes/Tokyo.md"])
    }

    // MARK: - Regular expressions

    func testPatternsMatchingEmptyTextSkipAttachmentsAndUnreadNotes() async throws {
        try await index.update([
            try note("Notes/A.md", "text"),
            try note("Notes/Empty.md", ""),
            try note("Notes/Unread.md", nil),
            try note("Media/photo.jpg", nil),
            try note("Media/doc.pdf", nil),
        ], generation: "test")
        let anywhere = try await paths("/^$/")
        XCTAssertEqual(anywhere, ["Notes/Empty.md"])
        let inContent = try await paths("content:/^$/")
        XCTAssertEqual(inContent, ["Notes/Empty.md"])
        let checkedByLine = try await paths("line:/^$/")
        XCTAssertFalse(checkedByLine.contains("Notes/Unread.md"))
        XCTAssertFalse(checkedByLine.contains("Media/photo.jpg"))
    }

    func testInvalidRegularExpressionIsReported() async throws {
        try await index.update([try note("Notes/A.md", "text")], generation: "test")
        for query in ["/(/", "-/(/", "line:(/[a-/)", "[status:/(/]"] {
            do {
                _ = try await index.search(query)
                XCTFail("\(query) should be reported as invalid.")
            } catch let error as SearchError {
                XCTAssertEqual(error.errorDescription?.hasSuffix("is not a valid regular expression."), true, query)
            }
        }
        let valid = try await paths("/te(x|y)t/")
        XCTAssertEqual(valid, ["Notes/A.md"])
    }

    func testRunawayRegularExpressionStopsWithAnError() async throws {
        try await index.update([try note("Notes/Runaway.md", String(repeating: "a", count: 32) + "!")], generation: "test")
        let clock = ContinuousClock()
        let startTime = clock.now
        do {
            _ = try await index.search("/(a+)+$/")
            XCTFail("A pattern that backtracks without end must stop.")
        } catch let error as SearchError {
            XCTAssertEqual(error, .regularExpressionTooSlow)
        }
        XCTAssertLessThan(clock.now - startTime, .seconds(5))
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 1)
    }

    // MARK: - Quick switcher

    func testQuickSwitcherFindsNamesWithOtherCapitalsAndAccents() async throws {
        try await index.update([
            try note("Notes/Élan vital.md", "x"),
            try note("Notes/Über.md", "x"),
            try note("Notes/東京.md", "x"),
            try note("Notes/[draft] *star?.md", "x"),
            try note("Notes/Other.md", "---\naliases: [Ärger]\n---\nx"),
        ], generation: "test")
        for (query, expectedName) in [("élan", "Élan vital.md"), ("elan", "Élan vital.md"), ("ÉLAN", "Élan vital.md"),
                                      ("über", "Über.md"), ("uber", "Über.md"), ("東京", "東京.md"),
                                      ("[d", "[draft] *star?.md"), ("*s", "[draft] *star?.md"), ("?", "[draft] *star?.md"),
                                      ("notes/über", "Über.md")] {
            let matches = try await index.quickSwitcherMatches(for: query)
            XCTAssertEqual(matches.first?.path.name, expectedName, query)
        }
        let alias = try await index.quickSwitcherMatches(for: "ärger")
        XCTAssertEqual(alias.first?.alias, "Ärger")
        let nothing = try await index.quickSwitcherMatches(for: "zzz")
        XCTAssertTrue(nothing.isEmpty)
    }

    func testQuickSwitcherAcceptsAnyLimit() async throws {
        try await index.update([try note("Notes/Alpha.md", "x"), try note("Notes/Alpine.md", "x")], generation: "test")
        let negative = try await index.quickSwitcherMatches(for: "a", limit: -1)
        XCTAssertTrue(negative.isEmpty)
        let one = try await index.quickSwitcherMatches(for: "alp", limit: 1)
        XCTAssertEqual(one.count, 1)
    }

    func testQuickSwitcherCandidatePatternKeepsWhatTheMatcherAccepts() throws {
        let names = ["Élan vital", "Straße", "ǅemal", "Ωmega", "ﬁle", "Кирилл", "東京", "a-b^c]d", "x*y?z[w", "Lecture notes", "100%_done\\x", "café au lait"]
        let databaseQueue = try DatabaseQueue()
        for name in names {
            for length in 1...min(4, name.count) {
                let query = String(name.prefix(length))
                for variant in [query, query.lowercased(), query.uppercased(), FuzzyCandidatePattern.folded(query)] {
                    guard FuzzyMatcher.match(variant, in: name) != nil else { continue }
                    // SQLite's own LIKE and GLOB, so the test reads the condition as the index does.
                    let pattern = FuzzyCandidatePattern(query: variant)
                    let isKept = try databaseQueue.read { database in
                        try Bool.fetchOne(database, sql: "SELECT \(pattern.sql(on: "name")) FROM (SELECT ? AS name)",
                                          arguments: StatementArguments(pattern.arguments + [name]))
                    }
                    XCTAssertEqual(isKept, true, "\(variant) in \(name)")
                }
            }
        }
    }

    // MARK: - Tags

    func testTagsWithNonASCIICapitalsCountOnce() async throws {
        try await index.update([
            try note("A.md", "#Été"),
            try note("B.md", "#été"),
            try note("C.md", "#Été #été"),
            try note("D.md", "#lecture"),
        ], generation: "test")
        let all = try await index.tags(matching: "")
        XCTAssertEqual(all.map(\.fileCount), [3, 1])
        XCTAssertEqual(all.first?.tag.lowercased(), "été")
        for query in ["ét", "ÉT", "Été", "é"] {
            let matching = try await index.tags(matching: query)
            XCTAssertEqual(matching.map(\.fileCount), [3], query)
        }
        let none = try await index.tags(matching: "", limit: -1)
        XCTAssertTrue(none.isEmpty)
    }
}
