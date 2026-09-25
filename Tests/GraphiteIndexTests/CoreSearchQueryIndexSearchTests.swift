import XCTest
@testable import GraphiteIndex
import GraphiteCore

/// Search through the real index for words, lines, and queries that `SearchTextTokens`,
/// `SearchQueryParser`, and `SearchMatcher` read differently before.
final class CoreSearchQueryIndexSearchTests: XCTestCase {
    private var directory: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.update([
            IndexedFile(path: try VaultPath("Russian.md"), size: 1, modified: .now, markdown: "Это мой новый дом. Ёлка."),
            IndexedFile(path: try VaultPath("Greek.md"), size: 1, modified: .now, markdown: "Το άλφα και το ωμέγα"),
            IndexedFile(path: try VaultPath("German.md"), size: 1, modified: .now, markdown: "Die Straße ist lang"),
            IndexedFile(path: try VaultPath("Tasks.md"), size: 1, modified: .now, markdown: "- [ ] buy milk\n- [x] finished report #work"),
            IndexedFile(path: try VaultPath("Windows.md"), size: 1, modified: .now, markdown: "alpha line one\r\nbeta line two\r\n\r\nother paragraph"),
        ], generation: "test")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func paths(_ query: String) async throws -> [String] {
        try await index.search(query).results.map(\.path.rawValue).sorted()
    }

    func testRussianGreekAndGermanWordsAreFoundByTheIndex() async throws {
        for query in ["мой", "новый", "МОЙ", "ёлка", "Ёлка"] {
            let found = try await paths(query)
            XCTAssertEqual(found, ["Russian.md"], query)
        }
        for query in ["άλφα", "ωμέγα"] {
            let found = try await paths(query)
            XCTAssertEqual(found, ["Greek.md"], query)
        }
        let german = try await paths("Straße")
        XCTAssertEqual(german, ["German.md"])
        let germanOrLine = try await paths("Straße OR line:zzz")
        XCTAssertEqual(germanOrLine, ["German.md"])
        let withoutGerman = try await paths("-Straße")
        XCTAssertEqual(withoutGerman, ["Greek.md", "Russian.md", "Tasks.md", "Windows.md"])
    }

    func testATagInATaskMustBeOnThatTask() async throws {
        let openWorkTasks = try await paths("task-todo:#work")
        XCTAssertEqual(openWorkTasks, [])
        let doneWorkTasks = try await paths("task-done:#work")
        XCTAssertEqual(doneWorkTasks, ["Tasks.md"])
    }

    func testBlocksOfAWindowsNoteKeepTheirLinesTogether() async throws {
        let sameBlock = try await paths("block:(alpha beta)")
        XCTAssertEqual(sameBlock, ["Windows.md"])
        let differentBlocks = try await paths("block:(alpha other)")
        XCTAssertEqual(differentBlocks, [])
    }

    func testDeeplyNestedQueriesDoNotExhaustTheStack() async throws {
        let groups = try await paths(String(repeating: "(", count: 3_000) + "дом")
        XCTAssertEqual(groups, ["Russian.md"])
        let exclusions = try await paths(String(repeating: "-", count: 3_000) + "дом")
        XCTAssertEqual(exclusions, ["Russian.md"])
        let scopes = try await paths(String(repeating: "line:", count: 3_000) + "дом")
        XCTAssertEqual(scopes, ["Russian.md"])
        // Any reading of so deep a query will do, as long as searching it returns.
        _ = try await paths(String(repeating: "-(", count: 3_000) + "дом")
        _ = try await paths(String(repeating: "[a:", count: 300) + "дом" + String(repeating: "]", count: 300))
    }
}
