import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Each note's session keeps its own last reading build, so two notes with equal text in one
/// window never show each other's blocks.
@MainActor
final class MarkdownSessionReadingBlocksCacheTests: XCTestCase {
    private var vault: URL!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "ReadingCacheVault", for: self).root
    }

    private func session(named name: String, text: String) async throws -> MarkdownSession {
        let path = try VaultPath(name)
        try Data(text.utf8).write(to: vault.appendingPathComponent(name))
        let store = VaultStore(root: vault)
        return try MarkdownSession(path: path, snapshot: try await store.read(path), store: store, didSave: { _ in })
    }

    func testTwoNotesWithEqualTextDoNotShareTheirLastReadingBuild() async throws {
        let first = try await session(named: "First.md", text: "![[Shared]]\n")
        let second = try await session(named: "Second.md", text: "![[Shared]]\n")
        XCTAssertEqual(first.text, second.text)

        XCTAssertFalse(first.readingBlocksCache === second.readingBlocksCache)
        XCTAssertNil(first.readingBlocksCache.lastBuild)
        XCTAssertNil(second.readingBlocksCache.lastBuild)
    }
}
