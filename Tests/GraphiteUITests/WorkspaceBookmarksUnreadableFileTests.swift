import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A `bookmarks.json` the workspace cannot read is an error the person sees, and the file
/// stays as it was: it never shows as "no bookmarks" and is never written over.
@MainActor
final class WorkspaceBookmarksUnreadableFileTests: XCTestCase {
    private var vault: URL!
    private var bookmarksLocation: URL!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "BookmarksVault", for: self).root
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        bookmarksLocation = vault.appendingPathComponent(".obsidian/bookmarks.json")
        // One byte over the 1 MiB limit on settings files.
        try Data(repeating: 0x20, count: 1_048_576 + 1).write(to: bookmarksLocation)
    }

    private func makeWorkspace() -> WorkspaceModel {
        let workspace = WorkspaceModel()
        workspace.store = VaultStore(root: vault)
        return workspace
    }

    func testReloadingShowsAnErrorInsteadOfAnEmptyListAndLeavesTheFileAlone() async throws {
        let before = try Data(contentsOf: bookmarksLocation)
        let workspace = makeWorkspace()
        XCTAssertNil(workspace.errorMessage)

        await workspace.reloadBookmarks()

        XCTAssertNotNil(workspace.errorMessage, "The person is told the bookmarks cannot be read.")
        XCTAssertEqual(try Data(contentsOf: bookmarksLocation), before)
    }

    func testChangingBookmarksShowsAnErrorAndNeverWritesOverTheUnreadableFile() async throws {
        let before = try Data(contentsOf: bookmarksLocation)
        let workspace = makeWorkspace()

        await workspace.updateBookmarks { bookmarks in bookmarks.add(.search("todo")) }

        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertEqual(try Data(contentsOf: bookmarksLocation), before)
        XCTAssertEqual(workspace.bookmarks, BookmarkList(), "The list shown is the empty one it started as, not a rewritten file.")
    }
}
