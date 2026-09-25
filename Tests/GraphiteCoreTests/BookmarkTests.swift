import XCTest
@testable import GraphiteCore

final class BookmarkTests: XCTestCase {
    /// As Obsidian writes it, with kinds and keys Graphite does not know.
    private let obsidianFile = """
    {
      "items": [
        {"type": "file", "ctime": 1727164800123, "path": "Course/Lecture 1.md"},
        {"type": "file", "ctime": 1727164800456, "path": "Course/Lecture 1.md", "subpath": "#Sampling#Aliasing", "title": "Aliasing"},
        {"type": "group", "ctime": 1727164800789, "title": "Exam", "items": [
          {"type": "search", "ctime": 1727164801000, "query": "tag:#exam"},
          {"type": "folder", "ctime": 1727164801001, "path": "Course/Past papers"},
          {"type": "file", "ctime": 1727164801002, "path": "Course/Summary.md", "subpath": "#^key-idea"}
        ]},
        {"type": "graph", "ctime": 1727164801003, "title": "Course graph", "options": {"search": "path:Course", "showTags": false}},
        {"type": "url", "ctime": 1727164801004, "url": "https://obsidian.md", "title": "Obsidian"}
      ],
      "futureSetting": true
    }
    """

    private func list() throws -> BookmarkList { try BookmarkList(configurationData: Data(obsidianFile.utf8)) }

    func testReadsEveryKindAndNamesThem() throws {
        let bookmarks = try list()
        XCTAssertEqual(bookmarks.items.map(\.type), ["file", "file", "group", "graph", "url"])
        XCTAssertEqual(bookmarks.items.map(\.displayTitle), ["Lecture 1", "Aliasing", "Exam", "Course graph", "Obsidian"])
        XCTAssertEqual(bookmarks.items[2].children.map(\.displayTitle), ["tag:#exam", "Past papers", "Summary › ^key-idea"])
        XCTAssertEqual(bookmarks.items[0].creationTime, 1_727_164_800_123)
        XCTAssertEqual(bookmarks.allBookmarks.count, 8)
        XCTAssertNotNil(bookmarks.fileBookmark(for: try VaultPath("Course/Lecture 1.md")))
        XCTAssertNotNil(bookmarks.fileBookmark(for: try VaultPath("Course/Lecture 1.md"), subpath: "#Sampling#Aliasing"))
        XCTAssertNil(bookmarks.fileBookmark(for: try VaultPath("Course/Summary.md")), "Only the block is bookmarked.")
        XCTAssertNotNil(bookmarks.folderBookmark(for: try VaultPath("Course/Past papers")))
        XCTAssertNotNil(bookmarks.searchBookmark(for: "tag:#exam"))
        XCTAssertEqual(Bookmark.file(try VaultPath("Note.md"), subpath: "Heading").displayTitle, "Note › Heading")
    }

    func testWritingKeepsUnknownKindsKeysAndWholeNumbers() throws {
        var bookmarks = try list()
        bookmarks.add(.search("line:(exam date)", at: Date(timeIntervalSince1970: 1_800_000_000)))
        let written = try bookmarks.configurationData()
        let reread = try BookmarkList(configurationData: written)
        XCTAssertEqual(reread, bookmarks)
        let text = String(decoding: written, as: UTF8.self)
        XCTAssertTrue(text.contains("\"futureSetting\" : true"), text)
        XCTAssertTrue(text.contains("1727164800123"), "Milliseconds stay whole numbers.")
        XCTAssertFalse(text.contains("1727164800123.0"))
        XCTAssertTrue(text.contains("\"showTags\" : false"), "A graph's options stay.")
        XCTAssertEqual(reread.items.last?.creationTime, 1_800_000_000_000)
    }

    func testAddsRenamesAndRemovesInsideGroups() throws {
        var bookmarks = try list()
        let group = bookmarks.items[2]
        bookmarks.add(.file(try VaultPath("Course/Formulas.md")), toGroup: group.id)
        XCTAssertEqual(bookmarks.items[2].children.map(\.displayTitle).last, "Formulas")

        let search = bookmarks.items[2].children[0]
        XCTAssertTrue(bookmarks.rename(id: search.id, to: "  Exam tags  "))
        XCTAssertEqual(bookmarks.items[2].children[0].displayTitle, "Exam tags")
        XCTAssertTrue(bookmarks.rename(id: search.id, to: ""))
        XCTAssertEqual(bookmarks.items[2].children[0].displayTitle, "tag:#exam", "An empty name goes back to the default.")
        XCTAssertNil(bookmarks.items[2].children[0].fields["title"])

        XCTAssertTrue(bookmarks.remove(id: search.id))
        XCTAssertEqual(bookmarks.items[2].children.count, 3)
        XCTAssertFalse(bookmarks.remove(id: search.id))
        XCTAssertTrue(bookmarks.remove(id: group.id))
        XCTAssertEqual(bookmarks.items.map(\.type), ["file", "file", "graph", "url"], "A group goes with its contents.")
    }

    func testFollowsRenamedFilesAndFolders() throws {
        var bookmarks = try list()
        XCTAssertTrue(bookmarks.followMove(from: try VaultPath("Course"), to: try VaultPath("Signals")))
        XCTAssertEqual(bookmarks.allBookmarks.compactMap(\.path),
                       ["Signals/Lecture 1.md", "Signals/Lecture 1.md", "Signals/Past papers", "Signals/Summary.md"])
        XCTAssertTrue(bookmarks.followMove(from: try VaultPath("Signals/Lecture 1.md"), to: try VaultPath("Signals/Sampling.md")))
        XCTAssertEqual(bookmarks.items[1].path, "Signals/Sampling.md")
        XCTAssertEqual(bookmarks.items[1].subpath, "#Sampling#Aliasing", "The heading stays.")
        XCTAssertFalse(bookmarks.followMove(from: try VaultPath("Elsewhere.md"), to: try VaultPath("Other.md")))
        XCTAssertFalse(bookmarks.followMove(from: try VaultPath("Signals/Lecture"), to: try VaultPath("X")), "A name that only starts the same is another file.")
    }

    func testRefusesFilesThatAreNotObsidiansFormat() {
        XCTAssertThrowsError(try BookmarkList(configurationData: Data("[1, 2]".utf8)))
        XCTAssertThrowsError(try BookmarkList(configurationData: Data(#"{"items": "none"}"#.utf8)))
        XCTAssertEqual(try BookmarkList(configurationData: nil).items, [])
        XCTAssertEqual(try BookmarkList(configurationData: Data("{}".utf8)).items, [])
    }

    func testStoreChangesTheLatestFileAndNeverCreatesAnEmptyOne() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vault) }
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let store = VaultStore(root: vault)
        let location = vault.appendingPathComponent(".obsidian/bookmarks.json")

        try await store.updateBookmarks { bookmarks in bookmarks.remove(id: "missing") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path), "Nothing to keep, no file.")

        let notePath = try VaultPath("A.md")
        try await store.updateBookmarks { bookmarks in bookmarks.add(.file(notePath)) }
        // Obsidian adds one meanwhile.
        var fromObsidian = try await store.bookmarks()
        fromObsidian.add(.folder(try VaultPath("Folder")))
        try fromObsidian.configurationData().write(to: location)
        let updated = try await store.updateBookmarks { bookmarks in bookmarks.add(.search("todo")) }
        XCTAssertEqual(updated.items.map(\.type), ["file", "folder", "search"], "The change made elsewhere is kept.")
        let reread = try await store.bookmarks()
        XCTAssertEqual(reread, updated)

        let before = try Data(contentsOf: location)
        try await store.updateBookmarks { bookmarks in bookmarks.remove(id: "missing") }
        XCTAssertEqual(try Data(contentsOf: location), before, "An unchanged list leaves the file as it was.")
    }
}
